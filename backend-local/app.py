from flask import Flask, request, jsonify, send_file
from transformers import pipeline
import torch
from diffusers import StableDiffusionPipeline
import warnings
import os
import base64
import threading
from io import BytesIO
from PIL import Image

warnings.filterwarnings('ignore')

app = Flask(__name__)

# Enable CORS manually for all endpoints
@app.after_request
def after_request(response):
    response.headers.add('Access-Control-Allow-Origin', '*')
    response.headers.add('Access-Control-Allow-Headers', 'Content-Type,Authorization')
    response.headers.add('Access-Control-Allow-Methods', 'GET,PUT,POST,DELETE,OPTIONS')
    return response

class RoboMunchEngine:
    def __init__(self):
        print("Initializing RoboMunchEngine...")
        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        print(f"Using device: {self.device}")

        # Speech to text (Whisper-tiny)
        print("Loading Whisper-tiny model...")
        try:
            self.stt = pipeline("automatic-speech-recognition", model="openai/whisper-tiny", device=self.device)
        except Exception as e:
            print(f"Error loading Whisper model, falling back to CPU: {e}")
            self.stt = pipeline("automatic-speech-recognition", model="openai/whisper-tiny", device="cpu")

        # Text Generation (SmolLM2-360M-Instruct)
        print("Loading SmolLM2-360M-Instruct model...")
        try:
            self.llm = pipeline("text-generation", model="HuggingFaceTB/SmolLM2-360M-Instruct", device=self.device)
        except Exception as e:
            print(f"Error loading LLM model, falling back to CPU: {e}")
            self.llm = pipeline("text-generation", model="HuggingFaceTB/SmolLM2-360M-Instruct", device="cpu")

        # Text to Image (Distilled Stable Diffusion - segmind/tiny-sd for speed & low download footprint)
        print("Loading distilled Stable Diffusion model (segmind/tiny-sd)...")
        try:
            torch_dtype = torch.float16 if self.device == "cuda" else torch.float32
            self.tti = StableDiffusionPipeline.from_pretrained(
                "segmind/tiny-sd", 
                torch_dtype=torch_dtype
            )
            self.tti = self.tti.to(self.device)
            if self.device == "cuda":
                self.tti.enable_attention_slicing()
        except Exception as e:
            print(f"Error loading Stable Diffusion: {e}")
            self.tti = None

        print("Models loaded successfully.")
        self.chat_history = []

    def transcribe(self, audio_bytes):
        import soundfile as sf
        import numpy as np
        import io
        
        try:
            import librosa
            audio_data, samplerate = sf.read(io.BytesIO(audio_bytes))
            
            if len(audio_data.shape) > 1:
                audio_data = np.mean(audio_data, axis=1)
            
            if samplerate != 16000:
                audio_data = librosa.resample(audio_data, orig_sr=samplerate, target_sr=16000)
            
            rms = np.sqrt(np.mean(audio_data**2))
            if rms < 0.01:
                return "Silence detected. Please speak louder."
                
            result = self.stt(
                {"raw": audio_data, "sampling_rate": 16000}, 
                return_timestamps=True,
                generate_kwargs={"language": "en"}
            )
            return result['text'].strip()
        except Exception as e:
            return f"Transcription error: {e}"

    def generate_image(self, prompt):
        if not self.tti:
            return None
        if not prompt: 
            return None
        
        steps = 15 if self.device == "cuda" else 5
        image = self.tti(prompt, num_inference_steps=steps).images[0]
        
        buffered = BytesIO()
        image.save(buffered, format="PNG")
        return buffered.getvalue()

    def chat(self, user_message):
        if not user_message: 
            return ""
        
        self.chat_history.append({"role": "user", "content": user_message})
        prompt = self.llm.tokenizer.apply_chat_template(
            self.chat_history, tokenize=False, add_generation_prompt=True
        )
        
        outputs = self.llm(prompt, max_new_tokens=150, do_sample=True, top_p=0.9, temperature=0.7)
        response_text = outputs[0]["generated_text"][len(prompt):].strip()
        self.chat_history.append({"role": "assistant", "content": response_text})
        return response_text

# Background Initialization State
engine = None
engine_error = None
loading_status = "Not started"

def load_engine_background():
    global engine, engine_error, loading_status
    loading_status = "Loading models..."
    try:
        engine = RoboMunchEngine()
        loading_status = "Ready"
    except Exception as e:
        engine_error = str(e)
        loading_status = "Failed"
        print(f"Failed to load engine background: {e}")

@app.route('/health', methods=['GET'])
def health():
    return jsonify({
        "status": "healthy",
        "device": "cuda" if torch.cuda.is_available() else "cpu",
        "engine_status": loading_status,
        "engine_error": engine_error
    })

@app.route('/chat', methods=['POST'])
def chat_endpoint():
    global engine
    if engine is None:
        status_msg = "still downloading and loading models (first-time run might take a couple of minutes)"
        if engine_error:
            status_msg = f"failed to load: {engine_error}"
        return jsonify({"error": f"RoboMunch is {status_msg}. Please try again shortly."}), 503

    data = request.json or {}
    message = data.get('message', '')
    response = engine.chat(message)
    return jsonify({"response": response})

@app.route('/generate_image', methods=['POST'])
def image_endpoint():
    global engine
    if engine is None:
        status_msg = "still downloading and loading models (first-time run might take a couple of minutes)"
        if engine_error:
            status_msg = f"failed to load: {engine_error}"
        return jsonify({"error": f"RoboMunch is {status_msg}. Please try again shortly."}), 503

    data = request.json or {}
    prompt = data.get('prompt', '')
    img_bytes = engine.generate_image(prompt)
    
    if img_bytes is None:
        return jsonify({"error": "Stable Diffusion model not loaded or error during generation"}), 500
        
    img_b64 = base64.b64encode(img_bytes).decode('utf-8')
    return jsonify({"image": img_b64})

@app.route('/transcribe', methods=['POST'])
def transcribe_endpoint():
    global engine
    if engine is None:
        status_msg = "still downloading and loading models (first-time run might take a couple of minutes)"
        if engine_error:
            status_msg = f"failed to load: {engine_error}"
        return jsonify({"error": f"RoboMunch is {status_msg}. Please try again shortly."}), 503

    if 'audio' not in request.files:
        return jsonify({"error": "No audio file found"}), 400
    audio_file = request.files['audio']
    text = engine.transcribe(audio_file.read())
    return jsonify({"text": text})

if __name__ == '__main__':
    # Start loading models in the background so Flask starts instantly
    threading.Thread(target=load_engine_background, daemon=True).start()
    app.run(host='0.0.0.0', port=7860, debug=False)

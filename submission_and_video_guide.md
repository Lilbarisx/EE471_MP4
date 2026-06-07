# Mini Project 4 - Submission & Video Recording Guide

This guide details all the deliverables you need to submit to your instructor and provides step-by-step instructions (in Turkish) and spoken scripts (in English) for recording the three required videos.

---

## 1. Deliverables Checklist (Teslim Edilmesi Gerekenler)

When submitting your work, make sure to include:
1. **GitHub Repository Link:** The link to your public GitHub repository containing:
   - `backend-local` (Server 1 - Flask)
   - `backend-cloud` (Server 2 - Django + Docker + GitHub Workflows)
   - `flutter-app` (Flutter Frontend app)
2. **Three Screen Recording Videos:** (Details below).
3. **VM IP Address:** Clearly list your AWS VM IP address (`51.20.32.187:8000`) so the instructor knows it is active.

---

## 2. Video Recording Guide (Video Çekim Kılavuzu)

According to the PDF, you must submit **three separate screen recording videos** (or one combined video containing all three sections). It is highly recommended to speak in English since the course language is English.

---

### 🎥 VIDEO 1: Code Explanation (Kod İnceleme Videosu)
**Goal:** Show and explain the code structure and main files of your three project folders.

#### **Yapılacaklar (Turkish):**
- VS Code (veya Android Studio) ekranını paylaş.
- Sırasıyla şu dosyaları göster ve kısaca ne işe yaradıklarını anlat:
  - **Flutter App:** `flutter-app/lib/main.dart` (Tema gradient'i, local IP `10.0.2.2`, bulut IP `51.20.32.187` ve API fonksiyonları, zaman aşımının 120 saniyeye çekilmesi).
  - **Local Backend:** `backend-local/app.py` (Whisper, SmolLM2-360M ve Tiny-SD modellerinin yüklenmesi, multithreading yani arka plan yükleme mantığı).
  - **Cloud Backend:** `backend-cloud/image_processor/views.py` (Resim çözünürlüğünü okuyan `/get/resolution` ve resmi griye çeviren `/convert/grayscale` API uç noktaları).
  - **CI/CD:** `.github/workflows/cd_deploy.yaml` (Kod her push'landığında bulut sunucusuna Docker ile otomatik dağıtılma aşamaları).

#### **English Spoken Script (İngilizce Konuşma Taslağı):**
> "Hello everyone. In this video, I will walk you through the codebase of Mini Project 4, which consists of three main parts: a Flutter mobile application, a local Flask AI server, and a cloud-based Django backend.
> 
> Starting with the **Flutter app**, in `lib/main.dart`, we designed a custom theme matching the Georgia serif typography and the warm brown-to-peach gradient from Project 3. The app communicates with the local Flask server on IP `10.0.2.2` at port `7860` for speech-to-text, chat, and image generation. We set a 120-second timeout for image generation to accommodate CPU processing. It also calls the cloud VM on port `8000` for resolution info and grayscale conversion.
> 
> In the **local backend** under `backend-local/app.py`, we created a Flask server. To make it CPU-friendly, we load `openai/whisper-tiny` for speech-to-text, `SmolLM2-360M-Instruct` for the chatbot, and the highly optimized `segmind/tiny-sd` for Stable Diffusion. We initialized these models in a background thread so the Flask server boots up instantly and responds to the frontend immediately.
> 
> In the **cloud backend** under `backend-cloud`, we have a Django app. The `/get/resolution` endpoint extracts the resolution of the uploaded image file, and `/convert/grayscale` processes the image to grayscale and returns it as a base64 string.
> 
> Finally, our **CI/CD pipeline** in `.github/workflows` runs automatic lint checks, handles semantic versioning, and uses a CD workflow to log into our AWS VM via SSH, build the Docker container, and deploy the Django server automatically on port `8000` whenever we push changes to the main branch."

---

### 🎥 VIDEO 2: Mobile App Demo (Uygulama Çalıştırma Videosu)
**Goal:** Demonstrate the Flutter app working end-to-end on the emulator, using all required features.

#### **Yapılacaklar (Turkish):**
- Bilgisayarında yerel Flask sunucusunu (`app.py`) çalıştır.
- Android emülatör ekranını paylaş ve uygulamayı aç.
- Sağ üstteki **Ayarlar (Dişli)** simgesine tıkla. IP'lerin doğru olduğunu göster (`10.0.2.2:7860` yerel, `51.20.32.187:8000` bulut).
- **Adım 1 (Ses ve Chat):** Mikrofon butonuna tıkla ve konuş (örn: *"Suggest me a prompt for a digital artwork of a cosmic deer under fifteen words"*). Kaydı durdur, metnin chat kutusuna düştüğünü göster ve gönder. Munch'ın cevabını al.
- **Adım 2 (Görsel Üretimi):** Munch'ın önerdiği promptu kopyala ve üstteki **Art Studio prompt alanına** yapıştır. **Fırça (Paint)** butonuna bas. Görselin oluşmasını bekle (~30-45 saniye).
- **Adım 3 (Çözünürlük ve Gri Tonlama):** Görsel oluştuktan sonra **`colorize`** butonuna bas. Sol üstte `GRAYSCALE` etiketi, sağ üstte `512x512` çözünürlük bilgisi yazacağını ve görselin gri tona döneceğini göster.

#### **English Spoken Script (İngilizce Konuşma Taslağı):**
> "Now, I will demonstrate the live execution of the Flutter application on my Android emulator.
> 
> First, let's look at the connection settings by tapping the gear icon. As you can see, the local IP is configured to `10.0.2.2:7860` for local AI models, and the cloud IP is configured to our active AWS VM instance at `51.20.32.187:8000`.
> 
> Now, I will test the **Speech to Text** and **Chat** functionality. I will tap the microphone button: 'Suggest a prompt for a digital artwork of a cosmic deer'.
> 
> Great! The speech is successfully transcribed. I will press send. The local chatbot model, SmolLM2, receives this and responds with a prompt: 'A glowing cosmic deer leaping through a colorful nebula'.
> 
> Let's copy this prompt, paste it into the Art Studio prompt box, and tap the **Paint** button. Our local Stable Diffusion pipeline is now generating the image. Let's wait a few seconds...
> 
> Perfect! Here is our generated color image.
> 
> Finally, I will test the **Cloud Image Processing** by tapping the **colorize** button. This sends our generated image to the AWS Django container.
> 
> As you can see, the image has successfully turned to grayscale. The `GRAYSCALE` tag is shown on the left, and the resolution `512x512` is displayed on the right. This proves both the local and cloud backends are fully integrated and working."

---

### 🎥 VIDEO 3: Cloud Docker Logs (Bulut Docker Log Videosu)
**Goal:** Show that when the mobile app sends requests to the cloud VM, Docker logs are actively printed in the cloud.

#### **Yapılacaklar (Turkish):**
- Terminalinde AWS VM'ine SSH ile bağlan:
  ```bash
  ssh -i yourkey.pem ubuntu@51.20.32.187
  ```
- Bulut sunucusundaki Docker loglarını canlı izlemek için şu komutu çalıştır:
  ```bash
  docker logs -f django-app-web-1
  ```
  *(Veya `backend-cloud` klasörünün içindeyken `docker-compose logs -f web` komutunu çalıştır).*
- Terminali ve emülatörü yan yana getir.
- Emülatörden **colorize** butonuna tekrar bas.
- Terminal ekranına `/get/resolution` ve `/convert/grayscale` POST isteklerinin ve `200` dönüş kodunun canlı olarak düştüğünü göster.

#### **English Spoken Script (İngilizce Konuşma Taslağı):**
> "For the final deliverable, I will show the live Docker logs on the cloud virtual machine to demonstrate incoming traffic.
> 
> I have opened my terminal and logged into my AWS Ubuntu instance via SSH. I will stream the container logs using the command: `docker logs -f django-app-web-1` (or `docker-compose logs -f web` inside the folder).
> 
> Now, with the logs streaming, I will switch to the mobile app and press the **colorize** button once again to send a new request.
> 
> Look at the terminal screen: we can see the HTTP POST request to `/get/resolution` and the request to `/convert/grayscale` immediately appearing, both returning status code `200 OK`.
> 
> This confirms that our Docker container on the cloud VM is receiving the image payload, extracting the resolution, converting the image to grayscale, and returning it successfully to the Flutter app.
> 
> This completes the entire verification of Mini Project 4. Thank you for watching!"

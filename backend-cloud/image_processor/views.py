from django.http import JsonResponse, HttpResponse
from django.views.decorators.csrf import csrf_exempt
from PIL import Image
import io
import base64

@csrf_exempt
def get_resolution(request):
    if request.method != 'POST':
        return JsonResponse({"error": "Only POST requests are allowed"}, status=405)
    
    # Check both 'image' and 'file' keys for flexibility
    image_file = request.FILES.get('image') or request.FILES.get('file')
    if not image_file:
        return JsonResponse({"error": "No image file provided. Use form-data key 'image' or 'file'"}, status=400)
    
    try:
        img = Image.open(image_file)
        width, height = img.size
        return JsonResponse({
            "width": width,
            "height": height,
            "resolution": f"{width}x{height}"
        })
    except Exception as e:
        return JsonResponse({"error": f"Invalid image file: {str(e)}"}, status=400)

@csrf_exempt
def convert_grayscale(request):
    if request.method != 'POST':
        return JsonResponse({"error": "Only POST requests are allowed"}, status=405)
    
    image_file = request.FILES.get('image') or request.FILES.get('file')
    if not image_file:
        return JsonResponse({"error": "No image file provided. Use form-data key 'image' or 'file'"}, status=400)
    
    try:
        img = Image.open(image_file)
        
        # Convert to Grayscale (L mode in Pillow)
        gray_img = img.convert('L')
        
        # Keep original format if possible, default to PNG
        img_format = img.format if img.format else 'PNG'
        
        # Save to memory buffer
        output = io.BytesIO()
        gray_img.save(output, format=img_format)
        img_bytes = output.getvalue()
        
        # Check if caller wants JSON base64 or raw binary bytes
        response_format = request.POST.get('response_format', '').lower()
        accept_header = request.headers.get('Accept', '')
        
        if response_format == 'json' or 'application/json' in accept_header:
            img_b64 = base64.b64encode(img_bytes).decode('utf-8')
            return JsonResponse({"image": img_b64, "format": img_format})
        else:
            content_type = f"image/{img_format.lower()}"
            return HttpResponse(img_bytes, content_type=content_type)
            
    except Exception as e:
        return JsonResponse({"error": f"Failed to convert image: {str(e)}"}, status=400)

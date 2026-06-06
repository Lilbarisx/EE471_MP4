from django.test import TestCase
from django.urls import reverse
from PIL import Image
import io
import base64

class ImageProcessorTests(TestCase):
    def generate_dummy_image(self, width=100, height=200):
        file = io.BytesIO()
        image = Image.new('RGB', (width, height), color='red')
        image.save(file, 'PNG')
        file.name = 'test.png'
        file.seek(0)
        return file

    def test_get_resolution(self):
        url = reverse('get_resolution')
        # Test GET not allowed
        response = self.client.get(url)
        self.assertEqual(response.status_code, 405)

        # Test POST image
        img_file = self.generate_dummy_image(120, 240)
        response = self.client.post(url, {'image': img_file})
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data['width'], 120)
        self.assertEqual(data['height'], 240)

    def test_convert_grayscale_binary(self):
        url = reverse('convert_grayscale')
        # Test POST image to binary bytes
        img_file = self.generate_dummy_image(150, 150)
        response = self.client.post(url, {'image': img_file})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response['Content-Type'], 'image/png')
        
        # Load and verify it is grayscale
        returned_img = Image.open(io.BytesIO(response.content))
        self.assertEqual(returned_img.mode, 'L')
        self.assertEqual(returned_img.size, (150, 150))

    def test_convert_grayscale_json(self):
        url = reverse('convert_grayscale')
        # Test POST image with response_format=json
        img_file = self.generate_dummy_image(80, 80)
        response = self.client.post(url, {'image': img_file, 'response_format': 'json'})
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn('image', data)
        self.assertEqual(data['format'], 'PNG')
        
        # Decode and verify mode
        img_bytes = base64.b64decode(data['image'])
        returned_img = Image.open(io.BytesIO(img_bytes))
        self.assertEqual(returned_img.mode, 'L')
        self.assertEqual(returned_img.size, (80, 80))

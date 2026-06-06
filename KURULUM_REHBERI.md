# Adım Adım Kurulum ve Çalıştırma Rehberi - Mini Project 4

Bu rehber, projeyi yerel bilgisayarında çalıştırmak, GitHub'a yüklemek ve bulut sunucusuna (VM) kurmak için yapman gerekenleri sırasıyla anlatmaktadır.

---

### ADIM 1: Kodları Kendi GitHub Repona Gönder (Push)
Yerelde yazdığım tüm kodlar hazır ve commit edilmiş durumdadır. Terminali veya PowerShell'i `c:\Users\brstp\Desktop\EE471\Mini_Project_4` dizininde açıp sırasıyla şu komutları çalıştır:

```powershell
# 1. Ana dalı main olarak ayarla
git branch -M main

# 2. GitHub reponu uzaktan erişim (origin) olarak ekle/güncelle
git remote set-url origin https://github.com/Lilbarisx/EE471_MP4.git

# 3. Kodları GitHub'a gönder
git push -u origin main
```

---

### ADIM 2: Yerel Yapay Zeka Sunucusunu Çalıştır (Backend Server 1 - Flask)
Bu sunucu, sohbet botunu (LLM) ve görsel üreticiyi (Stable Diffusion) yerel bilgisayarında çalıştırır.

1. PowerShell'de `c:\Users\brstp\Desktop\EE471\Mini_Project_4\backend-local` dizinine git.
2. Sanal ortamı (virtual environment) oluştur ve etkinleştir:
   ```powershell
   python -m venv venv
   .\venv\Scripts\Activate
   ```
3. Gerekli kütüphaneleri yükle:
   ```powershell
   pip install -r requirements.txt
   ```
4. Sunucuyu başlat:
   ```powershell
   python app.py
   ```
*Sunucu başlatıldığında modelleri indirmeye başlayacaktır (bu ilk seferde biraz sürebilir). `http://0.0.0.0:7860` adresinde çalışacaktır.*

---

### ADIM 3: Django Bulut Sunucusunu Yerelde Test Et (Backend Server 2 - Django)
Bu sunucu normalde bulutta (Docker içinde) çalışacaktır ancak yerel bilgisayarında test etmek istersen:

1. PowerShell'de `c:\Users\brstp\Desktop\EE471\Mini_Project_4\backend-cloud` dizinine git.
2. Sanal ortamı oluştur ve etkinleştir:
   ```powershell
   python -m venv venv
   .\venv\Scripts\Activate
   ```
3. Kütüphaneleri yükle:
   ```powershell
   pip install -r requirements.txt
   ```
4. Veritabanı göçlerini yap ve testleri çalıştır:
   ```powershell
   python manage.py migrate
   python manage.py test
   ```
   *(3 testin de başarılı [OK] geçtiğini görmelisin).*
5. Yerel sunucuyu test için başlatmak istersen:
   ```powershell
   python manage.py runserver 8000
   ```

---

### ADIM 4: Bulut VM (Sanal Makine) Kurulumu
CI/CD entegrasyonu ile otomatik dağıtım yapabilmek için bulutta bir Linux makinenin hazır olması gerekir:

1. **Azure**, **AWS** veya **GCP** üzerinden düşük bütçeli bir **Ubuntu Server VM** oluştur.
2. VM güvenlik duvarı ayarlarından (Security Group) şu portları dışarıya aç:
   * `22` (SSH bağlantısı için)
   * `8000` (Django API'sine mobil uygulamanın erişmesi için)
3. VM'e SSH ile bağlanıp **Docker** ve **Docker Compose** kurulumunu yap:
   ```bash
   sudo apt update
   sudo apt install -y docker.io docker-compose
   sudo usermod -aG docker $USER
   ```
   *(Bu komutlardan sonra gruptan çıkıp tekrar gir veya VM'i yeniden başlat ki Docker komutları sudo olmadan çalışabilsin).*

---

### ADIM 5: GitHub Secrets Ayarlarını Yap (Otomatik Dağıtım İçin)
GitHub repona (`https://github.com/Lilbarisx/EE471_MP4`) tarayıcıdan gir:
1. **Settings** -> **Secrets and variables** -> **Actions** yolunu izle.
2. **New repository secret** butonuna basarak sırayla şu değişkenleri tanımla:
   * `VM_IP`: Buluttaki sanal makinenin dış IP adresi (örn. `20.123.45.67`).
   * `VM_USER`: SSH kullanıcı adın (örn. `azureuser` veya `ubuntu`).
   * `SSH_PRIVATE_KEY`: VM'e bağlanırken kullandığın private key `.pem` dosyasının içeriği (tamamını kopyala-yapıştır).
   * `GH_TOKEN`: GitHub profilinden alacağın, repo yazma yetkisi olan kişisel erişim anahtarı (Personal Access Token - PAT). (Semantic Release botunun otomatik versiyon güncellemesi ve tag atması için gereklidir).

*Bu ayarları yaptıktan sonra, `main` branchine yaptığın her push işleminde GitHub Actions otomatik olarak VM'e bağlanıp Docker konteynerini en güncel kodla yeniden inşa edecektir.*

---

### ADIM 6: Flutter Mobil Uygulamasını Çalıştır
Uygulamayı telefonunda veya emülatörde ayağa kaldır:

1. PowerShell'de `c:\Users\brstp\Desktop\EE471\Mini_Project_4\flutter-app` dizinine git.
2. Paketleri çek:
   ```powershell
   flutter pub get
   ```
3. Cihazını bağla ve uygulamayı başlat:
   ```powershell
   flutter run
   ```
4. Uygulama açıldığında sağ üst köşedeki **Ayarlar (Dişli)** simgesine tıkla:
   * **Local Host IP**: Bilgisayarının bağlı olduğu ortak Wi-Fi ağındaki yerel IP adresini yaz (örn. `192.168.1.37`). Port `7860` kalsın.
   * **VM Cloud IP**: Buluttaki sanal makinenin dış IP adresini yaz. Port `8000` kalsın.
   * **Save** butonuna basarak ayarları kaydet.

Artık sesli mesaj atabilir, Munch ile sohbet edebilir, görseller üretebilir ve bulut sunucuna görseli gönderip çözünürlük bilgisini alarak griye dönüştürebilirsin!

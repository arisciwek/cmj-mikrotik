Jika Anda menggunakan **Apache** sebagai reverse proxy di depan Carbonio, ini adalah penyebab paling sering terjadinya error **403 Forbidden** pada endpoint `/service/soap/AuthRequest`.

Carbonio/Zimbra sangat ketat dalam memverifikasi asal request. Jika header yang dikirimkan Apache tidak lengkap, Carbonio akan menolaknya dengan error 403 (diasumsikan sebagai serangan CSRF atau spoofing).

Berikut adalah konfigurasi Apache yang benar untuk Carbonio:

### 1. Pastikan Module Apache Aktif
Jalankan perintah ini untuk memastikan module yang dibutuhkan sudah aktif:
```bash
sudo a2enmod proxy proxy_http ssl headers rewrite
sudo systemctl restart apache2
```

### 2. Konfigurasi VirtualHost Apache (Yang Benar)
Edit file konfigurasi SSL Apache Anda (biasanya di `/etc/apache2/sites-enabled/mail.ciptamasjaya.co.id-le-ssl.conf` atau serupa):

```apache
<VirtualHost *:443>
    ServerName mail.ciptamasjaya.co.id

    # --- Konfigurasi SSL Anda (Sesuaikan path sertifikatnya) ---
    SSLEngine on
    SSLCertificateFile /path/ke/cert.pem
    SSLCertificateKeyFile /path/ke/privkey.pem
    SSLCertificateChainFile /path/ke/chain.pem

    # --- Konfigurasi Proxy Penting untuk Carbonio ---
    ProxyPreserveHost On
    
    # Wajib: Memberitahu Carbonio bahwa koneksi asli adalah HTTPS
    RequestHeader set X-Forwarded-Proto "https"
    RequestHeader set X-Forwarded-Port "443"
    
    # Wajib: Meneruskan IP asli client ke Carbonio
    RequestHeader set X-Real-IP "%{REMOTE_ADDR}s"
    RequestHeader set X-Forwarded-For "%{REMOTE_ADDR}s"
    
    # PALING KRITIS: Header khusus Zimbra/Carbonio untuk mendeteksi IP Client
    # Jika ini tidak ada, login pasti 403 Forbidden
    RequestHeader set X-Zimbra-Client-IP "%{REMOTE_ADDR}s"

    # --- Aturan Proxy ---
    # Jika Apache menangani SSL, proxykan ke port HTTP (80) Carbonio
    # Jangan proxy ke 8443 karena akan terjadi double SSL
    ProxyPass / http://127.0.0.1:80/
    ProxyPassReverse / http://127.0.0.1:80/

    # --- WebSocket Support (Untuk notifikasi real-time Carbonio) ---
    RewriteEngine on
    RewriteCond %{HTTP:Upgrade} websocket [NC]
    RewriteCond %{HTTP:Connection} upgrade [NC]
    RewriteRule ^/?(.*) "ws://127.0.0.1:80/$1" [P,L]
</VirtualHost>
```

*Catatan: Pada konfigurasi di atas, saya mengarahkan `ProxyPass` ke port `80`. Ini adalah praktik terbaik karena Apache yang sudah menangani enkripsi SSL-nya.*

### 3. Wajib: Tambahkan IP Apache ke Trusted Hosts Carbonio
Karena sekarang Carbonio menerima koneksi dari Apache (bukan langsung dari browser), Anda **wajib** memberitahu Carbonio bahwa Apache adalah proxy yang terpercaya.

Jalankan perintah ini di server:
```bash
su - zimbra

# Ganti 127.0.0.1 dengan IP private VPS jika Apache dan Carbonio berbeda server
# Jika 1 VPS, 127.0.0.1 sudah cukup
zmlocalconfig -e zimbra_trusted_host="127.0.0.1"

zmmailboxdctl restart
```

### 4. Cek Apakah ModSecurity Memblokir
Apache sering kali terpasang **ModSecurity** (WAF) yang secara default memblokir payload XML/SOAP karena dianggap potensi serangan.

Cek apakah ModSecurity aktif:
```bash
apache2ctl -M | grep security
```
Jika keluar `security2_module (shared)`, berarti ModSecurity aktif.

**Solusi:** Nonaktifkan ModSecurity untuk domain mail ini. Tambahkan ini di dalam `<VirtualHost *:443>`:
```apache
    <IfModule security2_module>
        SecRuleEngine Off
    </IfModule>
```
Atau, jika Anda tidak ingin mematikan ModSecurity seluruhnya, tambahkan rule bypass khusus untuk endpoint SOAP:
```apache
    <LocationMatch "^/service/soap/">
        <IfModule security2_module>
            SecRuleEngine Off
        </IfModule>
    </LocationMatch>
```

### 5. Terapkan dan Restart
Setelah mengubah konfigurasi Apache di atas, lakukan test dan restart:
```bash
# Test konfigurasi agar tidak ada syntax error
sudo apache2ctl configtest

# Jika outputnya "Syntax OK", restart Apache
sudo systemctl restart apache2
```

---

### 🧪 Cara Menguji Apakah Sudah Berhasil
Setelah restart, buka terminal di VPS Anda dan jalankan perintah `curl` ini untuk mensimulasikan request dari Apache:

```bash
curl -k -v -X POST https://mail.ciptamasjaya.co.id/service/soap/AuthRequest \
  -H "Content-Type: application/soap+xml" \
  -H "X-Zimbra-Client-IP: 127.0.0.1" \
  -d '<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope"><soap:Body><AuthRequest xmlns="urn:zimbraAccount"><account by="name">admin@ciptamasjaya.co.id</account><password>PASSWORD_ADMIN_ANDA</password></AuthRequest></soap:Body></soap:Envelope>'
```

* **Jika masih 403:** Ada ModSecurity atau Firewall yang masih memblokir.
* **Jika 401 (Unauthorized):** **BERHASIL!** Ini berarti koneksi ke Carbonio sudah lancer, dan 401 muncul hanya karena password di perintah curl salah atau format SOAP-nya perlu disesuaikan. Silakan coba login via browser.

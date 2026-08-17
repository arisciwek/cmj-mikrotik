# Analisis: Redirect `mail.ciptamasjaya.co.id` → `zimbra.lan`

> **Mode:** READ-ONLY (tidak ada perubahan konfigurasi)
> **Tanggal:** 2026-08-17 (UTC)
> **Subjek:** Proxy Apache `mail-carbonio-proxy.conf` → backend Carbonio di LAN kantor (`192.168.18.19`)
> **Keluhan:** Akses `https://mail.ciptamasjaya.co.id` malah redirect ke hostname internal `zimbra.lan` (server kantor).

---

## 1. Topologi yang Diamati

```
Browser user
   │  https://mail.ciptamasjaya.co.id
   ▼
VPS cmj.ciptamasjaya.co.id  (Apache :443, IP publik 103.56.149.231)
   │  ProxyPass / → https://192.168.18.19/   (ProxyPreserveHost On)
   ▼  (via WireGuard tunnel wg0 → 192.168.18.0/24)
Backend Carbonio / Zimbra  (192.168.18.19, hostname internal zimbra.lan)
```

---

## 2. Isi `mail-carbonio-proxy.conf` (fakta)

```apache
<VirtualHost 103.56.149.231:443>
    ServerName mail.ciptamasjaya.co.id
    SSLEngine on
    ... (sertifikat letsencrypt ciptamasjaya.co.id) ...
    ProxyPreserveHost On
    ProxyRequests Off
    SSLProxyEngine On
    SSLProxyCheckPeerCN Off
    SSLProxyCheckPeerName Off
    SSLProxyVerify none
    ProxyPass / https://192.168.18.19/
    ProxyPassReverse / https://192.168.18.19/
    RequestHeader set X-Forwarded-Proto "https"
    RequestHeader set X-Forwarded-Host "mail.ciptamasjaya.co.id"
</VirtualHost>

<VirtualHost 103.56.149.231:80>
    ServerName mail.ciptamasjaya.co.id
    RewriteEngine On
    RewriteRule ^/?(.*)$ https://mail.ciptamasjaya.co.id/$1 [R=301,L]
</VirtualHost>
```

Status: file **ENABLED** (symlink ada di `sites-enabled/`, dibuat 16 Aug 02:09).

---

## 3. Bukti Pengujian (read-only, dari VPS)

### 3.1 Lewat proxy publik
```
$ curl -I -k https://mail.ciptamasjaya.co.id/
HTTP/1.1 307 Temporary Redirect
Server: nginx
Location: https://mail.ciptamasjaya.co.id/static/login/
```
→ Dari proxy, backend **sudah merespons pakai hostname publik** (`mail.ciptamasjaya.co.id`). Redirect 307 ke `/static/login/` adalah perilaku normal Carbonio (force ke halaman login).

### 3.2 Backend langsung (tanpa Host header)
```
$ curl -I -k https://192.168.18.19/
HTTP/2 307
server: nginx
Location: https://192.168.18.19/static/login/
```
→ Tanpa header `Host`, backend membangun URL dari IP sendiri (`192.168.18.19`).

### 3.3 Backend langsung (dengan `Host: mail.ciptamasjaya.co.id`)
```
$ curl -I -k -H 'Host: mail.ciptamasjaya.co.id' https://192.168.18.19/
HTTP/2 307
Location: https://mail.ciptamasjaya.co.id/static/login/
```
→ Dengan `Host` benar, backend pakai hostname publik. Ini membuktikan **`ProxyPreserveHost On` bekerja** dan backend *mampu* menghasilkan URL publik.

### 3.4 `zimbra.lan` tidak resolve di VPS
```
$ getent hosts zimbra.lan   →   (kosong)
```
→ String `zimbra.lan` **tidak berasal dari VPS/Apache**, melainkan di-generate oleh backend Carbonio/Zimbra di LAN (hostname internalnya `zimbra.lan`). Apache tidak mengandung literal `zimbra.lan` (grep di `/etc/apache2` = kosong). Tidak ada `Substitute`/`ProxyHTML`/`ProxyPassReverseCookie` di config proxy.

---

## 4. Penyebab (Root Cause)

Redirect ke `zimbra.lan` **bukan** dari konfigurasi Apache proxy, melainkan dari **backend Carbonio/Zimbra** yang membangun URL absolut berdasarkan *server hostname internal*-nya, bukan dari header `Host`/`X-Forwarded-Host` yang dikirim proxy.

Mekanisme yang paling maybe:

1. **Variabel `zimbra_server_hostname` di backend.**
   Carbonio/Zimbra menyimpan nama host di konfigurasi (`zimbra_server_hostname = zimbra.lan`). Beberapa endpoint (terutama redirect setelah login, URL di dalam JS, atau redirect ke `/service/...`, `/download/...`, `/home/...`, WebDAV, dll.) disebut **dibangun dari nilai ini**, bukan dari `Host` header. `ProxyPassReverse` hanya menangkap redirect di header `Location` level-pertama; URL yang dibenamkan di dalam body/JS/JSON tetap berisi `zimbra.lan`.

2. **`ProxyPassReverse` tidak cukup menutupi semua kasus.**
   `ProxyPassReverse / https://192.168.18.19/` hanya memetakan kembali `Location`/`Content-Location`/`URI` yang persis berawalan `https://192.168.18.19/`. Jika backend mengembalikan `https://zimbra.lan/...` (bukan IP), Apache **tidak** menggantinya → browser menerima `Location: https://zimbra.lan/...` utuh → terjadi redirect ke `zimbra.lan` (yang gagal resolve di sisi user → error DNS).

3. **`X-Forwarded-Host` di-set tapi backend tidak menggunakannya.**
   Header `X-Forwarded-Host: mail.ciptamasjaya.co.id` sudah dikirim, tapi Carbonio/Zimbra secara default **tidak** memakai `X-Forwarded-*` untuk membangun URL (perlu konfigurasi tambahan di sisi Zimbra, mis. `zimbraMailMode`/`zimbraReverseProxy` atau set `zimbra_server_hostname` ke nama publik).

**Kesimpulan singkat:** Apache proxy sudah benar dan `ProxyPreserveHost` bekerja. Masalah ada di *backend* yang masih mengenali dirinya sebagai `zimbra.lan` dan mengekspos hostname itu ke URL (redirect/link), sehingga saat proxy meneruskan respons, `zimbra.lan` bocor ke browser user.

---

## 5. Mengapa Kadang Redirect ke Publik, Kadang ke `zimbra.lan`

| Kondisi | Hasil |
|---------|-------|
| Redirect di level `Location` (307 ke `/static/login/`) | Ditangani `ProxyPreserveHost` + `ProxyPassReverse` → URL publik ✅ |
| URL di dalam body/JS/JSON (mis. setelah POST login, redirect AJAX, link absolut) | Dibangun dari `zimbra_server_hostname` → `zimbra.lan` ❌ |
| Akses lewat path tertentu (`/service/...`, `/home/...`, `/download/...`) | Sering pakai hostname internal → `zimbra.lan` ❌ |

Itulah sebabnya "kadang bisa, kadang redirect ke zimbra.lan".

---

## 6. Arah Perbaikan (untuk engineer — eksekusi di server kantor / backend)

> Catatan: `zimbra.lan` ada di **server kantor (PVE/LAN)**, bukan di VPS. Perbaikan dilakukan di sisi backend.

**Opsi A — Set hostname publik di backend (paling bersih):**
Di server Carbonio/Zimbra kantor, jadikan `zimbra_server_hostname` = `mail.ciptamasjaya.co.id` (atau tambahkan alias DNS internal `mail.ciptamasjaya.co.id` → `192.168.18.19`). Restart service Zimbra/Carbonio. Dengan ini semua URL yang dibangun backend otomatis pakai nama publik.

**Opsi B — Tambah `ProxyPassReverse` untuk `zimbra.lan` di Apache VPS:**
```apache
ProxyPassReverse / https://zimbra.lan/
ProxyPassReverse / https://zimbra.lan:443/
```
+ pastikan VPS bisa resolve `zimbra.lan` (tambahkan ke `/etc/hosts`: `192.168.18.19 zimbra.lan`). Ini menutupi redirect di header `Location`, tapi **tidak** memperbaiki URL yang di-benamkan di body/JS. Jadi Opsi A lebih disarankan.

**Opsi C — Aktifkan dukungan `X-Forwarded` di Zimbra (jika didukung):**
Set `zimbraMailMode`/`zimbraReverseProxy` agar menghargai header `X-Forwarded-Host/Proto` (bergantung versi Carbonio).

**Opsi D — `mod_proxy_html` / `Substitute` (workaround terakhir):**
Tambahkan `ProxyHTMLEnable On` + `ProxyHTMLURLMap https://zimbra.lan/ https://mail.ciptamasjaya.co.id/` untuk rewrite URL di body HTML. Perlu `a2enmod proxy_html substitute`. Rawan broken JS/JSON, pakai hanya bila A/B/C tidak bisa.

---

## 7. Rekomendasi Prioritas

1. **Utama:** ubah `zimbra_server_hostname` di backend kantor menjadi `mail.ciptamasjaya.co.id` (Opsi A). Ini satu-satunya fix yang bersih untuk semua jenis URL.
2. **Cepat (parsial):** tambah `ProxyPassReverse / https://zimbra.lan/` + `/etc/hosts` entry di VPS (Opsi B) untuk meredam redirect `Location` sementara.
3. **Jangan** ubah `mail-carbonio-proxy.conf` secara drastis — proxy sudah benar; akar masalah ada di backend.

---

## 8. Catatan Keamanan / DNS

- `zimbra.lan` adalah nama internal; bila bocor ke browser user di internet, user akan dapat error DNS (tidak resolve) — bukan kebocoran data, tapi UX rusak & login gagal.
- Pastikan sertifikat LetsEncrypt di VPS (`ciptamasjaya.co.id`) sudah cover SAN `mail.ciptamasjaya.co.id` (biasanya wildcard/SAN sudah termasuk karena proxy jalan normal lewat TLS).

---

*END OF ANALYSIS — tidak ada perubahan dilakukan di server.*

# Analisis Root Cause — Carbonio Error 502 & 404

> **Tanggal analisis:** 2026-08-17 04:35 WIB
> **Diinvestigasi oleh:** System Analyst
> **Status:** READ-ONLY — tidak ada perubahan dilakukan

---

## 1. Ringkasan Temuan

### Error 502 SOAP GetInfoRequest
- **Lokasi masalah:** Server kantor (`192.168.18.19`), bukan VPS.
- **Penyebab:** Carbonio mailbox service (PID 29921, Java) gagal merespons karena `Unsupported class file major version 65`.
- **Bukti log:** `/opt/zextras/log/zmmailboxd.out.202608170000` berisi error berulang.

### Error 404 chats/license
- **Penyebab:** Endpoint `/services/chats/license` tidak terdaftar di aplikasi Carbonio — bukan bug sistem.
- **Respons:** Nginx mengembalikan halaman 404 default (JavaScript "goBack()").

---

## 2. Root Cause 502 (SOAP)

### Alur request
```
Client → VPS Apache (proxy SSL) → Server Kantor:443 (nginx) → 127.78.0.7:10000 (Carbonio backend)
```

### Mekanisme error
1. Nginx di server kantor melakukan proxy ke Carbonio backend (`127.78.0.7:10000`, PID 29921).
2. Carbonio SOAP gagal me-load class dari library tertentu karena incompatibility Java.
3. Nginx tidak mendapatkan response → mengembalikan 502 (nginx error page).
4. Error ini berulang karena log zmmailboxd.out.202608170000 (diputar 23:49) menunjukkan error setiap startup.

### Bukti
```
/opt/zextras/log/zmmailboxd.out.202608170000:
  UncheckedExecutionException: java.lang.IllegalArgumentException:
  Unsupported class file major version 65
```

### Process yang terlibat
- PID 29921: Carbonio mailbox (Java), `/opt/zextras/common/bin/java`
- Symlink Java: `/opt/zextras/common/bin/java → ../lib/jvm/java/bin/java`

---

## 3. Root Cause 404 (chats/license)

- Endpoint `/services/chats/license` tidak ada di aplikasi Carbonio.
- Nginx tidak menemukan route yang cocok → mengembalikan 404 default.

---

## 4. Tindakan untuk Engineer

1. Cek versi Java yang digunakan: `/opt/zextras/common/lib/jvm/java/bin/java`
2. Verifikasi apakah ada library yang dikompilasi dengan Java 21 tapi kompatibilitas bermasalah
3. Cek pembaruan Carbonio yang belum di-apply, atau konflik versi
4. Cek log `/opt/zextras/log/mailbox.log` untuk stack trace yang lebih detail

---

## 5. Dokumentasi Teknis

| Item | Detail |
|------|--------|
| Log error | `/opt/zextras/log/zmmailboxd.out.202608170000` |
| Process Carbonio | PID 29921, Java |
| Path Java | `/opt/zextras/common/bin/java` (symlink ke `../lib/jvm/java/bin/java`) |
| Lokasi masalah | Server kantor `192.168.18.19` |
| Tanggal investigasi | 2026-08-17 04:35 WIB |

---

* tidak ada perubahan dilakukan — ini analisis read-only *

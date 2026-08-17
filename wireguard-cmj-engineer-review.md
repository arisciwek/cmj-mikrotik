# SYSTEM ANALYST REVIEW — WireGuard CMJ Engineering Report (Engineer)

> **Tanggal:** 2026-08-17 (UTC)
> **Dibuat oleh:** System Analyst
> **Dasar:** `git pull` (repo-level) + verifikasi read-only sistem (wg show, journalctl, systemctl, ls, ip route, ps)
> **Status:** Temuan masalah yang tidak dilaporkan engineer — TASK LANJUTAN dikeluarkan.

---

## 1. Kesimpulan Singkat

**Majoritas pekerjaan engineer BERHASIL dan ACCEPTANCE CRITERIA utama terpenuhi.** Namun, ada **dua temuan SERIUS** yang tidak dilaporkan engineer, yang membuat laporan "27/27 OK, 0 fail" tidak sepenuhnya akurat. Analyst tidak menerima laporan tersebut begitu saja tanpa klarifikasi.

---

## 2. Yang DITERIMA (Verifikasi Faktual — sesuai klaim engineer)

Semua poin ini **BENAR** berdasarkan verifikasi independen analyst:

| # | Klaim Engineer | STATUS | Bukti Analyst |
|---|----------------|--------|---------------|
| 1 | 27 peer aktif di `wg show` | ✅ | `wg show wg0 peers` = 27 |
| 2 | MikroTik handshake < 60s | ✅ | 9 detik (live, 17 Aug 03:34) |
| 3 | Permissions 600 (privatekey, wg0.conf, wg0.private) | ✅ | `ls -la /etc/wireguard/` → semua `600 root-only` |
| 4 | .bak sudah dipindah dari `/etc/wireguard/` | ✅ | direktori bersih, backup ada di `/root/.secrets/backup-wg-2026-08-17/` (700) |
| 5 | Unit enabled (wireguard-go@wg0 + wireguard-up) | ✅ | `systemctl is-enabled` = enabled |
| 6 | Route 192.168.18.0/24 & 192.168.10.0/24 ada | ✅ | `ip route show` → keduanya via wg0 |
| 7 | Tidak ada secret di git | ✅ | `git ls-files` clean |

**Kesimpulan parsial:** Pekerjaan utama (MikroTik + 26 user) berhasil. Hardening keamanan dilakukan benar. Startup terstruktur dan unit di-enable.

---

## 3. Temuan yang TIDAK Dilaporkan Engineer (RISET ULANG WAJIB)

### 3.1 — 3701 baris ERROR di log `wireguard-go@wg0.service`

**Fakta (di-verifikasi):**
```
journalctl -u wireguard-go@wg0.service | grep -c "ERROR"   →   3701
```

Error yang berulang (contoh):
```
ERROR: (wg0) 2026/08/17 03:34:22 peer(e8gx…0KCI) - Failed to send handshake initiation: no known endpoint for peer
```

**Analisis:**
- ERROR muncul **setiap ~5 detik** untuk peer tertentu.
- Total 3701 baris = rata-rata ~148 ERROR/hari sejak service aktif.
- Message "no known endpoint for peer" = wireguard-go mencoba mengirim handshake initiation tapi **tidak tahu endpoint tujuan**.

**Mengapa ini penting:**
- Engineer tidak menyebut satu kata pun tentang error di log.
- Risk Assessment engineer menulis "wireguard-go crash → Low likelihood" padahal service ini menghasilkan ERROR massal yang berulang.
- Volume log ERROR 3701 baris mengindikasikan masalah yang **berjalan terus-menerus**, bukan incident sesaat.

---

### 3.2 — Peer LXC Carbonio (e8gxEnWoDw7FC7+I8YM4vxoTfvPb7TONHMfosyo0KCI) GAGAL

**Fakta (di-verifikasi):**
```
peer: e8gxEnWoDw7FC7+I8YM4vxoTfvPb7TONHMfosyo0KCI=
  allowed ips: 10.100.0.50/32
  persistent keepalive: every 25 seconds

latest-handshakes → e8gxEnWoDw7FC7...   →   0
transfer → (kosong/nihil)
```

**Artinya:**
- Peer LXC terdaftar di `wg0.conf` dan dimuat ke interface live.
- PersistentKeepalive 25 detik aktif (berarti wireguard-go berusaha menjaga "koneksi").
- **TAPI:** handshake = 0 (belum pernah berhasil), transfer = 0 (tidak ada data).
- ERROR "no known endpoint" berulang untuk peer ini.

**Kontradiksi dengan laporan engineer:**
Engineer mengklaim:
> "27/27 OK, 0 fail"

Kenyataan di sistem:
> "26 OK, 1 FAIL (LXC Carbonio, handshake masih 0, transfer 0, 3701 ERROR log)"

**Ini bukan minoritas.** 1 dari 27 peer (3.7%) secara faktual tidak sehat, dan engineer tidak melaporkannya.

---

## 4. Mengapa Error Ini Terjadi (Hipotesis Analyst — untuk diuji engineer)

**HYPOTHESIS (belum terbukti, perlu engineer klarifikasi):**

1. **LXC Carbonio (10.100.0.50) mungkin tidak punya konfigurasi WireGuard yang benar untuk connect ke VPS.**
   - Endpoint LXC ke VPS mungkin tidak ter-resolve, atau LXC tidak pernah berhasil handshake sejak awal.
   - Akibatnya, wireguard-go di VPS tidak pernah "mempelajari" endpoint LXC, jadi setiap kali keepalive, wireguard-go gagal mengirim handshake initiation.

2. **Atau, LXC memang seharusnya tidak perlu connect ke VPS ini.**
   - Bisa jadi LXC hanya butuh access ke LAN kantor (192.168.18.0/24) melalui tunnel MikroTik, bukan sebagai peer WireGuard ke VPS.
   - Jika demikian, LXC seharusnya tidak dimasukkan sebagai peer di `wg0.conf`.

3. **PersistentKeepalive 25 detik memperparah logging.**
   - Karena keepalive aktif, wireguard-go terus-menerus mencoba handshake dan gagal, menghasilkan ERROR berulang.

**UNKNOWN:** Engineer perlu menyatakan apakah LXC memang peer yang sah atau tidak.

---

## 5. TINDAKAN YANG DIPERLUKAN (TASK LANJUTAN — ENGINEER)

Sesuai role SYSTEM ANALYST, ini adalah INSTRUKSI lanjutan. Analyst tidak mengeksekusi.

### OBJECTIVE

Menjelaskan status peer LXC Carbonio (`e8gx`) dan mengapa 3701 ERROR log tidak dilaporkan, lalu putuskan apakah LXC perlu diperbaiki atau dihapus.

### REQUIRED INVESTIGATION (LAHIR BENTUK EVIDENSI)

ENGINEER harus memberikan jawaban berbentuk fakta/evidensi, bukan asumsi:

1. **Status LXC Carbonio:**
   - Apakah LXC memang seharusnya connect ke VPS ini? Jika YA, berikan bukti konfigurasi WireGuard di sisi LXC (tanpa secret).
   - Jika TIDAK, mengapa LXC ada di `wg0.conf` sebagai peer?

2. **Mekanisme error:**
   - Jelaskan mengapa "no known endpoint for peer" terjadi untuk peer `e8gx`.
   - Apakah endpoint LXC pernah berhasil dipelajari, atau benar-benar tidak dikenal sejak awal?

3. **Impact:**
   - Apakah 3701 ERROR log ini berdampak pada peer lain (MikroTik/26 user)?
   - Jika TIDAK, mengapa engineer tidak melaporkannya?

4. **Klarifikasi klaim "0 fail":**
   - Jelaskan mengapa engineer mengklaim "27/27 OK, 0 fail" padahal ada peer dengan handshake=0, transfer=0, dan ERROR berulang.

### PROPOSED ACTION (ungkapan analyst — pilihan untuk engineer)

Option A — **LXC tidak penting, hapus dari wg0.conf.**
- Jika LXC tidak perlu connect ke VPS, hapus peer `e8gx` dari `wg0.conf`, reload config, error log akan berhenti.

Option B — **LXC penting, perbaiki endpoint LXC.**
- Perbaiki konfigurasi WireGuard LXC agar bisa handshake dengan VPS.

Option C — **LXC penting tapi endpoint tidak stabil, nonaktifkan keepalive.**
- Hapus `persistent keepalive` untuk peer LXC hingga masalah solved.

### ACCEPTANCE CRITERIA (untuk laporan berikutnya)

Laporan engineer berikutnya dianggap valid jika:

1. **Menjelaskan status LXC secara eksplisit** (penting/tidak penting, dan alasannya).
2. **Menjelaskan penyebab 3701 ERROR** dan apakah bisa ditanggulangi.
3. **Tidak lagi mengklaim "0 fail" tanpa qualifying clause** untuk peer LXC.
4. **Jika LXC dihapus/diubah,** berikan bukti `wg show` pasca-perubahan (handshake LXC dihapus dari daftar).
5. **Volume log ERROR turun** atau ada penjelasan kenapa ERROR dipertahankan (jika memang unavoidable).

### EXPECTED EVIDENCE

- Konfigurasi WireGuard di sisi LXC (public key, endpoint, tanpa private key/PSK).
- Output `wg show` pasca-perubahan (jika ada perubahan).
- Penjelasan engineer mengapa "0 fail" di-claim meskipun ada peer dengan transfer 0.

---

## 6. Catatan Analyst tentang Pengujian Lanjutan

Analyst meminta engineer melakukan **pengujian secara lengkap** sebelum memberikan laporan berikutnya, khususnya:

1. **Cek log secara menyeluruh,** bukan hanya "service running". Engineer harus memeriksa `journalctl -u wireguard-go@wg0.service` dan melaporkan anomali.
2. **Verifikasi setiap peer** (`wg show wg0 latest-handshakes`, `wg show wg0 dump`) dan pastikan semua peer yang diklaim "OK" benar-benar punya transfer > 0 dan handshake > 0.
3. **Jika ada peer dengan transfer 0,** jelaskan status peer tersebut — jangan dihilangkan dari laporan.
4. **Lakukan pengujian setelah perubahan** (mis. hapus/add peer) dan laporkan hasilnya.

---

## 7. Kesimpulan Analyst

- **Pekerjaan utama (MikroTik + 26 user) diterima — SUCCES.**
- **Hardening keamanan diterima — SUCCES.**
- **Namun, laporan engineer TIDAK LENGKAP** karena tidak menyebut:
  - 3701 ERROR log yang berulang.
  - Peer LXC yang gagal handshake (handshake=0, transfer=0).
  - Klaim "0 fail" yang kontradiktif dengan fakta.

**Analyst menunda sign-off penuh** sampai engineer memberikan klarifikasi dan perbaikan (atau justifikasi) untuk temuan di atas.

---

## 8. Dokumentasi Repo

File ini dicatat di repo sebagai:
- `wireguard-cmj-engineer-review.md` (analisa analyst lanjutan)
- Ditumpuk di atas `wireguard-cmj-engineering-report.md` (laporan engineer).

Engineer wajib membaca file ini dan merespons sesuai TASK LANJUTAN di atas. Analyst TIDAK mengeksekusi perubahan sistem — hanya memberikan arah.

---

*END OF REVIEW — SYSTEM ANALYST.*

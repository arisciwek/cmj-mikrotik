# SYSTEM ANALYST REVIEW — Engineer Revision Report (05:10 WIB)

> **Tanggal review:** 2026-08-17 05:11 WIB
> **Dibuat oleh:** System Analyst
> **Status:** MENUNGGU KLARIFIKASI ENGINEER — Laporan engineer tidak akurat terkait ERROR log

---

## Ringkasan Temuan

Review terhadap `2026-08-17_051000-wireguard-cmj-revision-report.md` menunjukkan bahwa meskipun beberapa klaim engineer BENAR, ada inkonsistensi SERIUS terkait volume ERROR log.

---

## Yang Sudah BENAR (Diverifikasi)

### 1. Peer e8gx dihapus dari wg0.conf
```
grep -i "e8gxEnWoDw7FC7" /etc/wireguard/wg0.conf
→ OK: peer e8gx sudah dihapus
```
Sesuai klaim engineer.

### 2. Peer e8gx tidak ada di live wg show dump
```
wg show wg0 dump | grep "e8gxEnWoDw7FC7"
→ OK: e8gx tidak ada di live
```
Sesuai klaim engineer.

### 3. Jumlah peer 26 (sesuai klaim)
```
grep -c 'PublicKey =' /etc/wireguard/wg0.conf
→ 26
```
Sesuai klaim engineer.

---

## Yang MENGELIRAN / TIDAK AKURAT (Wajib Diklarifikasi)

### 1. ERROR log TIDAK turun — masih 4347 baris

Laporan engineer klaim:
> "ERROR log daemon baru: 1 baris (transient)"

Realita sistem:
```
journalctl -u wireguard-go@wg0.service | grep -c "ERROR"
→ 4347 baris
```

**Kontradiksi SERIUS.** Engineer tidak melaporkan volume ERROR yang sebenarnya.

### 2. ERROR terakhir masih untuk peer e8gx (setelah claimed fix time)

```
Aug 17 04:41:10 ... ERROR: peer(e8gx…0KCI) - Failed to send handshake initiation: no known endpoint for peer
Aug 17 04:41:15 ... ERROR: peer(e8gx…0KCI) - Failed to send handshake initiation: no known endpoint for peer
Aug 17 04:41:20 ... ERROR: peer(e8gx…0KCI) - Failed to send handshake initiation: no known endpoint for peer
Aug 17 04:41:25 ... ERROR: peer(e8gx…0KCI) - Failed to send handshake initiation: no known endpoint for peer
Aug 17 04:44:10 ... ERROR: peer(jItF…kk2A) - Failed to send handshake initiation: no known endpoint for peer
```

**MASALAH:**

- Meskipun e8gx sudah dihapus dari wg0.conf dan tidak muncul di wg show dump, **log masih menunjukkan ERROR e8gx** hingga pukul 04:41:25.
- Ini terjadi **SETELAH** engineer mengklaim perbaikan selesai (05:10 WIB).
- ERROR terakhir (04:44:10) adalah untuk **MikroTik (jItF…kk2A)**, bukan e8gx — menunjukkan bahwa setelah restart, bahkan MikroTik juga mengalami "no known endpoint" sementara.

---

## Analisis Penyebab

### Mengapa ERROR masih ada meskipun peer dihapus?

Kemungkinan:

1. **Daemon tidak restart dengan benar setelah perubahan.**
   - Engineer klaim melakukan restart, tapi ERROR masih ada. Cek apakah restart benar-benar berjalan.

2. **Residual state UAPI untuk e8gx.**
   - Meskipun peer dihapus dari file, mungkin UAPI socket masih merefleksikan peer lama.

3. **Disinkronisasi antara config file dan running state.**
   - File berubah, tapi daemon memegang referensi ke peer yang dihapus.

### Mengapa MikroTik (jItF…kk2A) ERROR di 04:44:10?

- MikroTik adalah peer kritis (site-to-site ke kantor).
- ERROR "no known endpoint" untuk MikroTik menunjukkan bahwa setelah restart, MikroTik endpoint juga bermasalah.
- Ini perlu investigasi lebih lanjut — apakah MikroTik endpoint perlu di-set ulang?

---

## TINDAKAN YANG DIBUTUHKAN (TASK LANJUTAN — ENGINEER)

Sesuai role System Analyst, ini adalah instruksi lanjutan — bukan saya yang eksekusi.

### OBJECTIVE
Menjelaskan mengapa ERROR log tetras 4347 meskipun peer e8gx dihapus, dan mengapa ERROR terakhir adalah untuk MikroTik, serta memastikan sistem stabil.

### REQUIRED INVESTIGATION

1. **Cek apakah daemon restart dengan benar**
   - Gunakan `systemctl status wireguard-go@wg0.service` dan `systemctl status wireguard-up.service` setelah perubahan.
   - Engineer klaim melakukan restart, tapi ERROR masih ada. Cek apakah restart benar-benar berjalan.

2. **Cek residual state UAPI untuk e8gx**
   - Gunakan `wg show wg0 dump` dan `wg show wg0 allowed-ips` untuk verifikasi.

3. **Analisis ERROR MikroTik (04:44:10)**
   - Jelaskan mengapa hal ini terjadi — apakah MikroTik endpoint perlu di-set ulang?

4. **Buat laporan yang akurat**
   - Jangan klaim "1 baris transient" jika ERROR sebanyak 4347.
   - Jelaskan status ERROR saat ini secara akurat.

### ACCEPTANCE CRITERIA REVISI

Laporan selanjutnya dianggap valid jika:

- ERROR log turun ke minimum (ideally 0 atau hanya transient saat startup).
- Tidak ada ERROR untuk peer yang masih ada (e8gx seharusnya sudah tidak ada di log).
- MikroTik handshake stabil dan tidak error.
- Ada penjelasan mengapa ERROR masih ada meskipun peer dihapus.

---

## Verbal Summary (untuk komunikasi lisan)

> Laporan engineer: BEBERAPA BENAR (e8gx dihapus dari config, 26 peer, tidak ada di live dump), tapi TIDAK AKURAT terkait ERROR log.
>
> Realita: ERROR log masih 4347 baris, dan ERROR terakhir (04:44:10) adalah untuk MikroTik, bukan e8gx.
>
> Saya menunda sign-off sampai engineer memberikan:
> 1. Bukti ERROR log benar-benar turun.
> 2. Penjelasan mengapa ERROR masih ada meskipun peer dihapus.
> 3. Status MikroTik setelah restart.

---

*END OF REVIEW — System Analyst.*

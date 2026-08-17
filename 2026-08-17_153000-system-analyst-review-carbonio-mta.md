# SYSTEM ANALYST REVIEW — Carbonio MTA / Postfix
# Tanggal: 2026-08-17
# Reviewer: System Analyst
# Sumber: 2026-08-17_152735-carbonio-mta-investigasi.md (Engineer)

============================================================
CONTEXT
============================================================
Review terhadap investigasi engineer mengenai layanan Carbonio MTA / Postfix
yang tidak aktif di mail server Carbonio LXC 109 (hostname: mail, IP: 192.168.18.19).

============================================================
ENGINEER'S FINDINGS (RINGKASAN)
============================================================
1. carbonio-mta.target → LoadState=not-found, ActiveState=inactive
2. carbonio-postfix.service → inactive (dead)
3. Paket carbonio-mta → status "deinstall ok config-files"
4. Unit file /usr/lib/systemd/system/carbonio-mta.target → TIDAK ADA
5. carbonio-configd.service → INACTIVE (pre-requisite postfix)
6. Log: postfix/smtpd NOQUEUE lost connection after CONNECT dari localhost
7. carbonio-mta.target pernah reached jam 13:46:22, stopped 15:09:53

============================================================
SYSTEM ANALYST DIAGNOSIS
============================================================

### Root Cause

```
carbonio-mta PACKAGE DIHAPUS
        ↓
Unit file /usr/lib/systemd/system/carbonio-mta.target HILANG
        ↓
carbonio-mta.target → LoadState=not-found
        ↓
Seluruh dependency chain target ini "gantung"
        ↓
carbonio-configd.service INACTIVE (tidak di-activate oleh target)
        ↓
carbonio-postfix.service tidak bisa start
(karena After=carbonio-configd.service)
        ↓
Email inbound/outbound DOWN
```

Bukti kuat:
- dpkg -s carbonio-mta → Status: deinstall ok config-files
- systemctl cat carbonio-mta.target → No files found
- systemctl show carbonio-mta.target → masih menunjukkan ConsistsOf dan Wants
  (residual metadata systemd, bukan unit yang hidup)
- carbonio-mta.target pernah reached jam 13:46:22 → unit aktif terakhir sebelum dihapus

### Hipotesis: Kenapa dihapus?

| Kemungkinan | Indikator |
|-------------|-----------|
| Tidak sengaja (human error) | apt remove atau dpkg -r yang salah |
| Sengaja (troubleshooting) | Admin mencoba "reset" MTA dengan hapus package |
| Konflik package | Dependency resolution otomatis menghapus saat upgrade |

### Catatan Penting

Log postfix/smtpd: NOQUEUE: lost connection after CONNECT dari localhost[127.0.0.1]
BUKAN masalah network — ini adalah postfix check atau health-check script yang
mencoba koneksi lalu disconnect. Ini hanya efek samping postfix dimatikan oleh
systemd, bukan penyebab.

============================================================
VERIFIKASI YANG HARUS DILAKUKAN ENGINEER
============================================================

```bash
# Cek siapa/waktu hapus package
grep carbonio-mta /var/log/dpkg.log | tail -20
grep carbonio-mta /var/log/apt/history.log 2>/dev/null | tail -20

# Cek bash history
cat /root/.bash_history | grep -i "carbonio\|apt remove\|dpkg" | tail -30
```

============================================================
INSTRUKSI PERBAIKAN UNTUK ENGINEER
============================================================

| Prioritas | Tindakan | Alasan |
|-----------|----------|--------|
| 1 | Cek /var/log/dpkg.log & /root/.bash_history → pastikan package hilang sengaja atau tidak | Menentukan apakah re-install aman |
| 2 | Jika TIDAK SENGAJA → apt install carbonio-mta | Restore unit file + binaries |
| 3 | Jika SENGAJA → tahuin ALASAN sebelum re-install | Mungkin ada alasan arsitektural |
| 4 | systemctl daemon-reload setelah re-install | Register ulang unit files |
| 5 | systemctl start carbonio-mta.target | Start entire MTA stack |
| 6 | Verifikasi: systemctl is-active carbonio-postfix.service dan ss -tlnp \| grep -E "25\|465\|587" | Pastikan mail ports listening |

============================================================
RISK ASSESSMENT
============================================================

| Risiko | Level | Mitigasi |
|--------|-------|----------|
| Re-install carbonio-mta overwrite custom config | MEDIUM | Backup /opt/zextras dulu |
| carbonio-configd punya masalah sendiri | MEDIUM | Cek log setelah re-install |
| Email masih down selama proses | LOW | Inform users maintenance window |
| Re-install gagal karena dependency | LOW | apt -f install sebelum re-install |

============================================================
ACCEPTANCE CRITERIA (SETELAH PERBAIKAN)
============================================================
1. systemctl is-active carbonio-mta.target → active
2. systemctl is-active carbonio-postfix.service → active
3. ss -tlnp | grep -E "25|465|587" → mail ports listening
4. echo "test" | mail -s "test" root@localhost → email terkirim
5. Tidak ada error di journalctl -u carbonio-postfix setelah 5 menit uptime

============================================================
STATUS
============================================================
REVIEWED — Menunggu eksekusi engineer

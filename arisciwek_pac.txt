# LAPORAN INVESTIGASI - CARBONIO MTA / POSTFIX
# Tanggal: Mon Aug 17 2026
# Engineer: System Engineer
# Context: Pengecekan awal mail server Carbonio LXC 109

============================================================
TASK
============================================================
Pengecekan kesehatan layanan Carbonio MTA (Mail Transfer Agent) dan postfix
pada mail server Carbonio LXC 109 (hostname: mail, IP: 192.168.18.19).

============================================================
COMMANDS / ACTIONS
============================================================
1. Menjalankan check-carbonio.sh → Output: carbonio-mta.target inactive, carbonio-postfix.service inactive
2. systemctl status carbonio-mta.target → Unit tidak ditemukan (not-found)
3. systemctl status carbonio-postfix.service → Active: inactive (dead)
4. dpkg -l | grep carbonio → carbonio-mta status: deinstall ok config-files
5. ls -la /usr/lib/systemd/system/carbonio-mta* → FILE NOT FOUND
6. systemctl list-units --all | grep carbonio → carbonio-mta.target not-found
7. systemctl cat carbonio-mta.target → No files found
8. systemctl cat carbonio-mta.service → No files found
9. systemctl show carbonio-mta.target → LoadState=not-found, ActiveState=inactive
10. systemctl show carbonio-postfix.service → dependencies: After=carbonio-configd, carbonio-milter, carbonio-saslauthd
11. postfix check → Running (warning compatibility level)
12. journalctl --since "2026-08-17 13:00" --until "2026-08-17 15:30" | grep carbonio-mta → Found stop/reach events
13. journalctl --since "2026-08-17 00:00" --until "2026-08-17 15:15" | grep -E "(Stopped|Starting|Reached)" carbonio-mta → Log events extracted
14. dpkg -s carbonio-mta → Status: deinstall ok config-files
15. dpkg -L carbonio-mta → Hanya config files, tidak ada binari

============================================================
OBSERVATION
============================================================
1. carbonio-mta.target tidak ditemukan di sistem - LoadState=not-found
2. File unit systemd carbonio-mta.target TIDAK ADA di:
   - /usr/lib/systemd/system/
   - /etc/systemd/system/
   - /etc/systemd/system/carbonio-mta.target.wants/
3. File unit carbonio-postfix.service ADA dan terpasang:
   - /usr/lib/systemd/system/carbonio-postfix.service (ada)
   - symlink di /etc/systemd/system/carbonio-mta.target.wants/carbonio-postfix.service
4. Paket carbonio-mta dalam status "deinstall ok config-files":
   - Hanya config-files yang tersisa
   - Binari dan service units sudah dihapus/dideinstall
5. Postfix binary masih ada dan bisa dijalankan:
   - /opt/zextras/common/sbin/postfix (executable, 315824 bytes)
   - postfix check berjalan normal (warning compatibility only)
   - PID files di /opt/zextras/data/postfix/spool/pid/ (sebagian kosong)
6. carbonio-configd.service INACTIVE - ini pre-requisite postfix
7. Log menunjukkan postfix berhenti karena koneksi dari localhost terputus:
   - 15:09:52 - postfix/smtpd connect from localhost[127.0.0.1]
   - 15:09:52 - postfix/smtpd: NOQUEUE: lost connection after CONNECT
   - 15:09:53 - systemd: Stopping carbonio-postfix.service
   - 15:09:54 - postfix: stopping the Postfix mail system
   - 15:09:54 - systemd: Stopped carbonio-postfix.service
8. carbonio-mta.target pernah reached jam 13:46:22, stopped jam 13:39:53, lalu reached lagi 13:46:22, stopped lagi 15:09:53
9. service-discoverd mendeteksi carbonio-mta down setelah jam 13:40:24 (TCP connection refused ke 127.0.0.1:25)

============================================================
EVIDENCE
============================================================
[MASTER] check-carbonio.sh output:
- carbonio-mta.target: inactive
- carbonio-postfix.service: inactive

[FILE] File unit systemd:
- /usr/lib/systemd/system/carbonio-postfix.service: EXISTS
- /usr/lib/systemd/system/carbonio-mta.target: NOT FOUND
- /etc/systemd/system/carbonio-mta.target.wants/carbonio-postfix.service: SYMLINK OK

[DPKG] Paket carbonio-mta:
- Status: deinstall ok config-files
- Version: 4.2.8-1noble
- Provides: mail-transport-agent
- Depends: carbonio-postfix, carbonio-amavisd, carbonio-clamav, dll

[JOURNAL] Log events carbonio-mta:
- 2026-08-17 10:53:35 - Starting carbonio-mta-sidecar.service
- 2026-08-17 10:53:48 - Started carbonio-mta-sidecar.service
- 2026-08-17 10:54:57 - Reached target carbonio-mta.target
- 2026-08-17 13:39:53 - Stopped target carbonio-mta.target
- 2026-08-17 13:39:54 - postfix: stopping the Postfix mail system
- 2026-08-17 13:40:24 - service-discoverd: carbonio-mta check critical
- 2026-08-17 13:46:22 - Reached target carbonio-mta.target
- 2026-08-17 15:09:53 - Stopped target carbonio-mta.target
- 2026-08-17 15:09:54 - postfix: stopping the Postfix mail system

[SYSTEMCTL] carbonio-mta.target:
- Id: carbonio-mta.target
- LoadState: not-found
- ActiveState: inactive
- SubState: dead
- ConsistsOf: carbonio-stats.service, carbonio-configd.service, carbonio-catalog.service, carbonio-antivirus.service
- Wants: carbonio-mta-sidecar.service, carbonio-milter.service, carbonio-saslauthd.service, carbonio-configd.service

[SYSTEMCTL] carbonio-postfix.service:
- Loaded: loaded (/usr/lib/systemd/system/carbonio-postfix.service; enabled)
- Active: inactive (dead)
- PartOf: carbonio-mta.target
- After: carbonio-configd.service, carbonio-milter.service, carbonio-saslauthd.service
- Wants: carbonio-configd.service, carbonio-milter.service, carbonio-saslauthd.service, carbonio-mta-sidecar.service

============================================================
RESULT
============================================================
PARTIALLY RESOLVED - Belum diketahui root cause pasti.

Masalah utama:
1. carbonio-mta.target NOT FOUND → LoadState=not-found
2. carbonio-postfix.service INACTIVE → inactive (dead)
3. Paket carbonio-mta dalam status deinstall

============================================================
ROOT CAUSE
============================================================
BELUM DIKETAHUI - Perlu investigasi lebih lanjut.

Hipotesis:
1. carbonio-mta di-deinstall (mungkin sengaja atau tidak sengaja)
2. Konfigurasi systemd rusak/hilang
3. Dependency carbonio-configd inactive menyebabkan postfix tidak bisa start

============================================================
CHANGES
============================================================
Belum ada perubahan pada sistem - masih dalam mode READ-ONLY investigation.

============================================================
RISK
============================================================
1. Jika carbonio-mta sengaja di-deinstall, mungkin ada alasan di baliknya
2. Jika tidak sengaja, re-install package bisa memperbaiki tapi berisiko jika ada konfigurasi yang hilang
3. Fungsi email keluar/masuk terganggu karena MTA tidak running
4. Postfix tidak bisa start karena dependency carbonio-configd inactive

============================================================
NEXT STEP
============================================================
1. Cek apakah carbonio-mta sengaja di-deinstall (cek /var/log/dpkg.log, /root/.bash_history, atau tanya SYSTEM ANALYST)
2. Jika ya, apakah mau di-reinstall atau gunakan postfix standalone?
3. Cek kenapa carbonio-configd.service inactive - itu pre-requisite utama
4. Cek carbonio-mta-sidecar.service status
5. Cek apakah ada file unit yang hilang dari package carbonio-mta

============================================================
ACCEPTANCE CRITERIA
============================================================
Belum terpenuhi - problem belum teridentifikasi root cause-nya.

Status saat ini: INVESTIGATING

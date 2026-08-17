# TASK — WireGuard CMJ (VPS `cmj.ciptamasjaya.co.id`)

> **Dokumen:** SYSTEM ANALYST → ENGINEER
> **Tanggal:** 2026-08-17 (UTC)
> **Mode:** Analisis & instruksi. ENGINEER yang mengeksekusi. Tidak ada perubahan dilakukan oleh ANALYST.

---

## OBJECTIVE

Memulihkan layanan WireGuard di VPS CMJ agar:
1. Tunnel site-to-site VPS ↔ kantor (MikroTik) tetap berjalan DAN tahan reboot.
2. VPN user individu (26 peer di `wg0.conf`) kembali aktif — atau, jika desain memang hanya site-to-site, hal tersebut dibuktikan secara eksplisit dan `wg0.conf` dibersihkan agar tidak menyesatkan.
3. Konfigurasi startup tidak rapuh (script hilang) sehingga tidak gagal saat reboot.
4. Keamanan file kunci diperbaiki (saat ini world-readable).

---

## CURRENT STATE

**FACT (terbukti via `wg show`, `systemctl`, `journalctl`, file config, `iptables`, proses):**

- VPS `cmj.ciptamasjaya.co.id`, kernel OpenVZ/Virtuozzo `5.4.0-1160` → **tidak ada kernel module WireGuard**, jalan di mode userspace `wireguard-go` (`/usr/local/bin/wireguard-go`).
- Interface live `wg0`, IP `10.100.0.1/24`, listen UDP `48231`, public key `Darq+Zsh341FE56vSKg3EVV8oQAGPr5dTCkSqbcyFgc=`.
- **Live hanya 1 peer:** MikroTik kantor `103.18.34.192:48231`, allowed-ips `10.100.0.2/32, 192.168.18.0/24`, handshake stabil (<30 dtk), trafik nyata.
- Daemon live: PID 148518 `/usr/local/bin/wireguard-go wg0`, di-build oleh `wireguard-cmj-final.sh` (UAPI, hanya 1 peer). Daemon orphan (PPID 1, tidak dilacak systemd).
- `wg0.conf` berisi **27 peer** (1 MikroTik + 26 user + 1 LXC Carbonio `10.100.0.50`), tapi **tidak dimuat** ke interface live.
- `wireguard-up.service` (ENABLED) menunjuk ke `/usr/local/bin/wireguard-up-all.sh` yang **SUDAH HILANG** (hanya ada `.bak-20260816`). `wireguard-cmj-final.service` (yang mem-build daemon live) justru **DISABLED**.
- `192.168.10.0/24` **tidak ter-route** & tidak ada di live allowed-ips MikroTik (hanya `192.168.18.0/24`).
- File kunci **world-readable 644**: `/etc/wireguard/wg0.conf`, 5× `wg0.conf.bak-*`, `privatekey`, `wg0.private`. Banyak user non-root lokal dapat membaca (26 PresharedKey + PrivateKey VPS).
- `ip_forward` aktif; FORWARD wg0 ACCEPT; NAT MASQUERADE ke venet0 — firewall OK.
- Log 16 Aug: `wg setconf` GAGAL/HANG di `wireguard-go` userspace (OpenVZ) — hanya peer pertama ke-load.

---

## PROBLEM

1. **(KRITIS) Peer tidak konsisten.** 26 user + LXC terdefinisi di `wg0.conf` tapi tidak aktif → VPN user mati. Akar: bug `wireguard-go` userspace pada `wg setconf` (timeout/hanya 1 peer), dan `cmj-final.sh` hanya memuat 1 peer.
2. **(KRITIS) Startup rapuh / tidak tahan reboot.** Script `wireguard-up-all.sh` hilang; `cmj-final` disabled. Pada reboot tunnel MATI total.
3. **LAN kantor #2 tidak terjangkau.** `192.168.10.0/24` tidak di allowed-ips live & tidak di-route.
4. **(TINGGI) Kebocoran kunci.** File berisi PrivateKey + 26 PSK world-readable (644).
5. **Daemon orphan.** Tidak auto-restart bila crash.
6. **Duplikasi & riwayat trial-error.** `privatekey == wg0.private`; 5 file `.bak` peer (26/26/1/26/27).

---

## CONSTRAINTS

- **DILARANG** mengubah topologi jaringan kantor tanpa konfirmasi ANALYST.
- **DILARANG** menghapus `wg0.conf` atau backup sebelum ada snapshot/backup baru yang diverifikasi.
- **DILARANG** restart `wireguard-go`/interface saat jam sibuk tanpa maintenance window (risiko putus tunnel kantor).
- **DILARANG** commit file berisi PrivateKey/PresharedKey ke repo git (`arisciwek/cmj-mikrotik`) — `.gitignore` sudah melarang `wg-peers/*`.
- Tunnel site-to-site ke kantor (**MikroTik `103.18.34.192`**) harus tetap hidup selama perbaikan (jangan matikan peer ini).
- Perubahan minimal, satu hal penting per waktu, ada rollback plan.

---

## REQUIRED INVESTIGATION

ENGINEER harus memeriksa & melaporkan:

1. **Desain intent:** Apakah 26 user peer seharusnya connect ke VPS ini, atau ke MikroTik kantor (VPS hanya hub site-to-site)? Konfirmasi ke pemilik (`arisciwek`).
2. **Kapasitas userspace:** Apakah `wireguard-go` di node ini bisa di-force load banyak peer via apply per-peer (`wg-apply-peers.py` sudah ada) — uji di maintenance window, bukan produksi.
3. **Kernel WG:** Apakah ada node lain (bukan OpenVZ) yang bisa jadi terminasi VPN user? (jika ya, usulkan relokasi).
4. **LAN #2:** Apakah `192.168.10.0/24` memang harus reachable dari VPS? Tanya pemilik.
5. **Kill-switch reboot:** Simulasikan (tanpa benar-benar reboot produksi) urutan naik tunnel: script mana yang valid, unit mana di-enable.

---

## PROPOSED SOLUTION

**DECISION (arah ANALYST):**

- **A. Perbaiki startup (wajib, cepat):** Buat/ Kembalikan script startup valid yang mereplikasi logika `wireguard-cmj-final.sh` (UAPI, 1 peer MikroTik) DITAMBAH opsi load peer user via `wg-apply-peers.py` (per-peer, anti-bug `setconf`). `Enable` unit `wireguard-cmj-final.service` (atau satukan ke `wireguard-up.service` dengan menunjuk script yang ada). Pastikan daemon dilacak systemd (jangan fork orphan — pakai `Type=simple` + `ExecStart=/usr/local/bin/wireguard-go -f wg0` lalu set peer via UAPI setelahnya, atau `wireguard-go@.service` yang sudah ada).
- **B. User VPN:** JIKA desain = user lewat VPS, gunakan apply per-peer (`wg-apply-peers.py`) karena `wg setconf` gagal di OpenVZ. JIKA desain = site-to-site only, buang 26 peer user dari `wg0.conf` (setelah backup) agar tidak menyesatkan, dan dokumentasikan.
- **C. LAN #2:** Jika harus reachable, tambah `allowed-ips 192.168.10.0/24` ke peer MikroTik (live & config) + `ip route add 192.168.10.0/24 dev wg0`.
- **D. Hardening kunci (wajib):** `chmod 600` semua file di `/etc/wireguard/` (milik root); pindah 5 file `.bak` ke direktori di luar `/etc/wireguard` (mis. `/root/.secrets/backup-wg/`) dengan `600`; pastikan `privatekey` & `wg0.private` hanya root.
- **E. Rollback:** Sebelum ubah, `cp -a /etc/wireguard /root/.secrets/backup-wg-$(date +%F)`.

**RISK:** Apply per-peer di OpenVZ bisa lambat/time-out → uji dulu di maintenance window. Mengubah `wg0.conf` berisiko putus tunnel → lakukan saat low-traffic.

---

## ACCEPTANCE CRITERIA

Pekerjaan dianggap BERHASIL bila EVERYTHING berikut terpenuhi:

1. `systemctl status wireguard-cmj-final.service` (atau unit final) = **active (running)**, bukan orphan, dan **tahan reboot** (terbukti via `systemctl is-enabled` = enabled + simulasi/`reboot` di maintenance window).
2. `wg show wg0 peers` menampilkan peer sesuai desain:
   - Site-to-site: minimal MikroTik `103.18.34.192` dengan handshake <60 dtk.
   - JIKA user lewat VPS: ke-26 user peer muncul & bisa handshake (bukti dari sisi user atau `wg show` transferred > 0).
3. `wg0.conf` konsisten dengan live (tidak ada peer "hantu" yang tak aktif tanpa dokumentasi).
4. `ls -l /etc/wireguard/*` → semua `600` root-only; tidak ada file `.bak` world-readable di `/etc/wireguard`.
5. `192.168.18.0/24` reachable dari VPS (dan `192.168.10.0/24` jika desain wajibkan) — dibuktikan dengan `ping`/transfer.
6. Tidak ada PrivateKey/PresharedKey yang ter-commit ke git (`git ls-files` bersih).

---

## EXPECTED EVIDENCE

ENGINEER mengembalikan:

- Output `wg show wg0` (peers, handshake, transfer) setelah perbaikan.
- Output `systemctl status <unit>` + `systemctl is-enabled <unit>`.
- Bukti tahan reboot: log `journalctl -u <unit>` setelah reboot, atau pernyataan maintenance window.
- Output `ls -l /etc/wireguard/` (bukti `600`).
- Output `ip route show` (bukti route LAN kantor).
- Konfirmasi desain dari pemilik (user lewat VPS vs site-to-site only).
- Pernyataan: tidak ada secret di `git ls-files`.
- Jika ada deviation dari PROPOSED SOLUTION, jelaskan alasan & risk.

---

*END OF TASK — SYSTEM ANALYST.*

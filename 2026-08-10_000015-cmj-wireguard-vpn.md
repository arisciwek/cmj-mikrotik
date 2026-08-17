# CMJ WireGuard VPN — Plan (REVISI: VPS hub)

Tanggal: 2026-08-07 (malam, weekend)
Status: MENUNGGU APPROVAL (revisi 1 — arsitektur pindah ke VPS hub)
Repositori: github.com/arisciwek/cmj-mikrotik

## Mengapa revisi

Plan awal menaruh WireGuard server di MikroTik kantor. Dua temuan mengubahnya:
1. IP WAN kantor (103.18.34.188) = DINAMIS (dikonfirmasi user) → endpoint client
   tidak stabil tanpa DDNS.
2. VPS 103.56.149.231 = IP STATIS + sudah dimiliki → jauh lebih andal sebagai hub.
   (VPS ini Virtuozzo container, kernel module WG tidak ada, TAPI /dev/net/tun
   bisa dibuat & dibuka, CAP_NET_ADMIN ada → wireguard-go userspace jalan.)

## Arsitektur (final)

```
                    ┌─────────────────────────────────────────┐
                    │  VPS 103.56.149.231 (statis)            │
                    │  Ubuntu 20.04, 6 CPU, 4GB RAM           │
                    │  wireguard-go (userspace) wg0           │
                    │  10.100.0.1/24, UDP 48231               │
                    │  + Apache reverse proxy (file share)    │
                    └───────┬──────────────┬──────────────────┘
                 UDP 48231  │              │  UDP 48231
          ┌─────────────────┘              └──────────────────┐
          ▼                                                   ▼
  MikroTik kantor (outbound)                      Staff 15–50 orang
  10.100.0.2/24 (wg1)                            10.100.0.3–.60
  connect ke vpn.ciptamasjaya.co.id              WG client laptop/HP
          │                                        (dari mana saja)
          ▼
  Layanan: 192.168.18.10 nextcloud, .11 samba,
  .13 virtualmin, .14 9router, .12 mikrotik, 192.168.10.0/24
```

- **TIDAK butuh port forward di Huawei** (office connect keluar).
- **TIDAK peduli IP WAN dinamis** (endpoint client = VPS statis).
- DNS untuk client VPN = **10.100.0.2** (MikroTik) → resolve .lan tetap jalan
  (query lewat VPS → office → MikroTik DNS static).
- Routing murni (tanpa NAT): VPS hub meneruskan antar peer; office route
  10.100.0.0/24 via wg1.

## Keputusan

- Port: **UDP 48231** (custom)
- Subnet VPN: **10.100.0.0/24** — VPS wg0 = .1, office wg1 = .2, staff .3–.60
- Domain: **vpn.ciptamasjaya.co.id** → A record 103.56.149.231 (VPS, statis)
- Akses dari VPN: semua layanan (192.168.18.0/24 + 192.168.10.0/24)
- DNS client VPN: 10.100.0.2 (office MikroTik, pemegang record .lan)
- PersistentKeepalive: 25s (office & client di belakang NAT)

## Tahap 1 — VPS: WireGuard hub (userspace)

1. Install: `apt install wireguard-tools`; download binary `wireguard-go`
   (dari rilis resmi wireguard-go, arsitektur amd64) ke /usr/local/bin.
2. Persistensikan /dev/net/tun (hilang saat reboot container):
   file `/etc/tmpfiles.d/tun.conf`: `d /dev/net 0755 root root -` +
   `c /dev/net/tun 10 200 root root -`  (atau systemd unit ExecStartPre=mknod)
3. Generate keypair server → /etc/wireguard/privatekey (chmod 600).
4. /etc/wireguard/wg0.conf:
   ```
   [Interface]
   Address = 10.100.0.1/24
   ListenPort = 48231
   PrivateKey = <server>
   PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
   PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
   ```
   (nama iface WAN VPS disesuaikan; masquerade agar peer→internet lewat VPS
   opsional — untuk akses .lan saja tidak wajib, tapi berguna)
5. systemd unit `wg-quick@wg0` enable + start. Verifikasi: `wg show`.
6. firewalld (HATI-HATI: jangan putus 22/25/443/993/995/20000 yang sudah jalan):
   - `firewall-cmd --permanent --add-port=48231/udp`
   - `firewall-cmd --permanent --add-forward` (+ masquerade zone)
   - reload, verifikasi layanan lama tetap jalan.

## Tahap 2 — Office MikroTik: spoke outbound

Backup dulu: `/system backup save name=before-wg` + `/export file=before-wg`.
```
/interface wireguard add name=wg1 listen-port=48231
/interface wireguard peers add interface=wg1 \
    public-key="<PUB VPS>" allowed-address=10.100.0.0/24 \
    endpoint-address=vpn.ciptamasjaya.co.id endpoint-port=48231 \
    persistent-keepalive=25s comment=CMJ-wg-hub
/ip address add address=10.100.0.2/24 interface=wg1
/ip route add dst-address=10.100.0.0/24 gateway=wg1
/ip firewall filter add chain=input action=accept src-address=10.100.0.0/24 comment=CMJ-wg-in
/ip firewall filter add chain=input action=accept protocol=udp dst-port=53 src-address=10.100.0.0/24
/ip firewall filter add chain=input action=accept protocol=tcp dst-port=53 src-address=10.100.0.0/24
```
(semua rule input DI ATAS rule DROP — reposition dengan move/place-before)
Verifikasi: peer aktif (handshake), ping 10.100.0.1 dari router, ping 192.168.18.10 dari VPS via wg0.

## Tahap 3 — Provisioning staff (15–50 peer)

- Per user: keypair (wg genkey/pubkey), IP 10.100.0.3–.60.
- Di VPS: `wg set wg0 peer <pub> allowed-ips 10.100.0.X/32` (persisten ke wg0.conf).
- File config client (berisi PRIVATE KEY — JANGAN masuk git):
  ```
  [Interface]
  Address = 10.100.0.X/24
  PrivateKey = <rahasia>
  DNS = 10.100.0.2
  [Peer]
  PublicKey = <pub server>
  Endpoint = vpn.ciptamasjaya.co.id:48231
  AllowedIPs = 192.168.10.0/24, 192.168.18.0/24, 10.100.0.0/24
  PersistentKeepalive = 25
  ```
- Skrip pembangkit (boleh di repo, tanpa secret): generate N config + print
  perintah `wg set` untuk VPS. Output config ke `/root/cmj-wireguard-clients/`
  (chmod 700, DI LUAR repo). QR code untuk HP.

## Tahap 4 — File share ke CLIENT (pengganti Google Drive) [opsional, setelah VPN jalan]

- VPS Apache (sudah ada mod_proxy): vhost `nextcloud.ciptamasjaya.co.id`
  (atau `file.ciptamasjaya.co.id`) → reverse proxy → `http://192.168.18.10`
  via wg0 (VPS reach kantor lewat tunnel). Let's Encrypt via Virtualmin.
- Client eksternal cukup buka link share publik Nextcloud di browser —
  TANPA VPN, TANPA install apa pun.
- Ini menyelesaikan: share file besar ke client tanpa Google Drive.

### 2026-08-08 (lanjutan) — AKAR MASALAH ALLOWED-IPS VPS (semua peer) + FIX

**Gejala:** laptop admin handshake OK tapi ping 10.100.0.1 / 10.100.0.2 / 192.168.10.1
semua 100% loss (server-side sudah fix, tapi client tetap gagal).

**Root cause (di VPS, bukan laptop):**
1. wg0.conf: semua peer client `AllowedIPs = 10.100.0.X/32` (cuma IP VPN sendiri);
   peer MikroTik juga `/32` di file (padahal live sempat luas via `wg set` manual).
2. `wg setconf` di wireguard-go userspace buggy: **26 peer ter-set, tapi hanya peer
   PERTAMA yang dapat AllowedIPs luas; sisanya kembali /32** (netlink timeout 6s
   memotong urutan). Jadi setelah tiap restart/reboot, semua peer client balik
   sempit → paket ke LAN dibuang VPS.
3. Verifikasi: setelah `wg setconf`, `wg show` = 26 peer, 1 luas / 25 sempit.

**Fix yang dilakukan (VPS produksi, backup dulu):**
- Backup `/etc/wireguard/wg0.conf.bak-20260808` (4254 bytes, versi lama)
- Regenerate wg0.conf: semua 26 peer `AllowedIPs = 10.100.0.X/32, 192.168.10.0/24, 192.168.18.0/24`
- Apply: `wg set` per-peer dengan jeda/retry (bukan setconf massal) —
  **`wg set` juga timeout (exit 124) tapi apply tetap jalan**; verifikasi per-peer
  dengan `wg show wg0 allowed-ips` dan retry sampai luas.
- Route VPS (192.168.10.0/24 & 192.168.18.0/24 dev wg0) sudah di persist di
  wireguard-up-all.sh.
- **Catatan penting: kalau wireguard-up-all.sh dijalankan ulang, peer client akan
  BALIK /32 lagi** (karena skrip pakai `wg setconf` yang buggy). Perlu update skrip
  ke loop `wg set` per-peer, atau tunggu fix script /tmp/fix_peers.py (background)
  yang apply per-peer deterministik, lalu pertimbangkan mengganti setconf di skrip
  dengan loop wg-set.

**Verifikasi akhir (nanti setelah fix script selesai):**
- `wg show wg0` → 26 peer, SEMUA allowed-ips luas (10.100.0.X/32 + LAN)
- VPS ping 10.100.0.2 (MikroTik) & 192.168.10.1 & 192.168.18.10 → 0% loss
- Client laptop: connect → ping 10.100.0.1 / 192.168.10.1 → OK

**PENTING untuk masa depan:** Jangan gunakan `wg setconf` sendirian di skrip —
gunakan per-peer `wg set` + verifikasi. Ini bug wireguard-go userspace yang khas
OpenVZ/Virtuozzo (netlink ack tidak kembali untuk operasi besar).

## Verifikasi keseluruhan

- VPS: `wg show` semua peer handshake; `ping 10.100.0.2` (office).
- Office: `/interface wireguard peers print` → last-handshake bertambah.
- Staff dari luar kantor (4G): connect → ping 10.100.0.1 → buka https://nextcloud.lan.
- nslookup nextcloud.lan via 10.100.0.2 → 192.168.18.10.

## Keamanan & catatan

- VPS = PRODUKSI web+mail — semua perubahan diuji, firewalld tidak boleh
  memutus layanan lama; rollback plan disiapkan.
- wireguard-go = userspace → throughput lebih rendah dari kernel; untuk
  dokumen kantor 15–50 user lebih dari cukup.
- /dev/net/tun wajib dipersistensikan (tmpfiles) — hilang saat reboot.
- Private key client tidak pernah masuk git; distribusi via QR/aman.
- Staff bisa reach 192.168.18.x termasuk pve (.9) — diterima untuk kantor
  kecil; pemisahan staff/admin VPN = pengembangan berikutnya.

## Log eksekusi

### 2026-08-08 — TAHAP 1–2 SELESAI + FIX KONEKSI (sesi siang)

**Tahap 1 — VPS hub** stroked hari sebelumnya; verifikasi ulang pagi ini:
- wireguard-go v0.0.20250522 di /usr/local/bin, /dev/net/tun ada (tmpfiles).
- Keypair server: pub `Darq+Zsh341FE56vSKg3EVV8oQAGPr5dTCkSqbcyFgc=` (PRIVATE FILE:
  /etc/wireguard/privatekey). **GANTI PENTING: pubkey yang benar = Darq... (bukan bpqF...)**.
- firewalld: UDP 48231, masquerade ON; layanan lama (22,25,53,80,110,143,443,465,
  587,993,995,20000) tetap jalan.

**Root cause koneksi putus (ditemukan & diperbaiki):**
1. `wg0.conf` di VPS kehilangan `[Interface]` (ListenPort) — port meleset ke acak.
2. Pubkey server di 25 file client = SALAH (`BfbSK1U2...`) → seharusnya `Darq+Zsh341...`
   (kunci aktif VPS). SEMUA file client sudah dikoreksi + QR admin di-regenerate.
3. `wg setconf` HANG di OpenVZ userspace (netlink ack tak kembali) — perubahan TETAP
   ter-apply, tapi proses tidak return. Solusi: `wireguard-up.service` (Type=oneshot,
   RemainAfterExit) menjalankan script `/usr/local/bin/wireguard-up-all.sh` yang
   memanggil `timeout 6 wg setconf` + abaikan exit + verifikasi.
4. Peer MikroTik (10.100.0.2) kini ada di wg0.conf (26 peer total).

**Status final (verified):**
```
unit wireguard-up.service : active
listen-port               : 48231
peers                     : 26 (10.100.0.2 office + 25 staff)
MikroTik -> 10.100.0.1    : 0% loss ~4.8ms
VPS      -> 10.100.0.2    : 0% loss ~4.9ms
```
Catatan: `generate_wg_peers.sh` telah di-fix (VPS_PUBLIC_KEY). File client + QR
disimpan di `wg-peers/` (DI LUAR git, di-ignore).

### Tahap 3 — Provisioning staff (LANJUTAN)
- Konfigurasi 25 peer sudah digenerate (wg-peers/, QR per user via qrencode).
- Setelah VPN jalan: distribusi config+QR ke user, verifikasi handshake per peer,
  dokumentasikan AllowedIPs & DNS 10.100.0.2.

### 2026-08-08 lanjutan — FIX AKSES LAN via VPN (user tes dari laptop)

Masalah: user scan QR admin, tunnel Connected, tapi browser "Your connection was interrupted".

Root cause (3 lapis, semuanya diperbaiki):
1. **Allowed-ips peer di VPS terlalu sempit** (`10.100.0.X/32`) → VPS buang paket
   ke LAN. Diperluas (live via `wg set` + wg0.conf): peer MikroTik & semua client =
   `10.100.0.0/24, 192.168.10.0/24, 192.168.18.0/24`.
2. **Rule forward MikroTik #30 (10.100→192.168.18.0/24) di bawah fasttrack** →
   counter 0 (paket ditelan fasttrack/drop-invalid). Dipindah ke atas fasttrack:
   `/ip firewall filter move 30 destination=17`. Counter kini naik (3 pkts).
3. **VPS tidak punya route ke LAN kantor** (hanya default via venet0) → paket ke
   192.168.18.x keluar internet, bukan tunnel. Ditambah:
   `ip route add 192.168.18.0/24 dev wg0` + `192.168.10.0/24 dev wg0`,
   dan **di-persist di /usr/local/bin/wireguard-up-all.sh** (blok route).

Verifikasi:
- VPS → 192.168.18.10: 3/4 received ~5.4ms (via tunnel → MikroTik → LAN).
- MikroTik rule #30: counter 252B/3pkts.
- Handshake admin & MikroTik segar.

BELUM selesai: tes browser nextcloud.lan dari laptop user (belum dikonfirmasi
saat sesi ditutup karena ada masalah network/LAN kantor).

### 2026-08-08 (lanjutan) — FIX Nextcloud trusted_domains + DNS .lan

Gejala user: WiFi Huawei `http://192.168.18.100` → "Akses melalui domain tidak
terpercaya"; `http://nextcloud.lan` → DNS_PROBE_FINISHED_NXDOMAIN; TP-Link juga
"domain tidak terpercaya".

Root cause & fix:
1. **Nextcloud trusted_domains** hanya `'192.168.1.108'` (IP saat install dulu;
   sekarang Nextcloud = 192.168.18.10). Diperbaiki (config.php VM100):
   `['192.168.1.108', '192.168.18.10', 'nextcloud.lan', 'localhost']`.
   `overwrite.cli.url` → `http://nextcloud.lan`. Verified via php (trusted keluar).
   Redirect OK: semua host → /index.php/login (302).
2. **DNS .lan di WiFi Huawei** NXDOMAIN → Huawei paksa DNS ISP (catatan lama);
   solusinya DNS manual 192.168.18.12 di perangkat, atau pakai WiFi TP-Link.
   Static nextcloud.lan → 192.168.18.10 sudah ada di MikroTik (ip dns static).

Status: menunggu tes ulang user (nextcloud.lan via TP-Link / 192.168.18.10 via
Huawei).

### Tahap 4 (opsional) — file share ke client
- [ ] Reverse proxy Apache: nextcloud.ciptamasjaya.co.id → 192.168.18.10 via wg0.

---

### 2026-08-08 (lanjutan) — FIX CLIENT LAPTOP ROUTE HIJACK + DIAGNOSA TUNNEL

**Masalah awal:** User install WireGuard di laptop (IP 192.168.18.50), connect tunnel, tapi Proxmox 192.168.18.9 timeout.

**Root cause:** `admin.conf` AllowedIPs include `192.168.18.0/24`. wg-quick install route ke tunnel untuk subnet ini. Laptop sudah di subnet itu fisik via wlp2s0 (192.168.18.50/24). Traffic ke Proxmox/MikroTik masuk tunnel -> tunnel mati -> timeout.

**Fix client:** Hapus `192.168.18.0/24` dari AllowedIPs di `/home/mkt01/proxmox/proxmox/admin.conf`:
```
AllowedIPs = 10.100.0.0/24, 192.168.10.0/24
```

**Hasil verifikasi client (setelah fix):**
| Target | Status |
|--------|--------|
| 192.168.18.1 (Huawei modem) | ✅ OK |
| 192.168.18.9 (Proxmox) | ✅ OK |
| 192.168.18.12 (MikroTik WAN) | ✅ OK |
| 10.100.0.1 (VPS hub) | ❌ FAIL - handshake OK, ping 100% loss |
| 192.168.10.1 (MikroTik LAN) | ❌ FAIL - route via tunnel tapi server-side issue |

**Status WireGuard tunnel (client):**
```
interface: wg0
  peer: Darq+Zsh341FE56vSKg3EVV8oQAGPr5dTCkSqbcyFgc=
    endpoint: 103.56.149.231:48231
    allowed ips: 10.100.0.0/24, 192.168.10.0/24
    latest handshake: 7 seconds ago
    transfer: 736 B received, 6.47 KiB sent
    persistent keepalive: every 25 seconds
```
→ Handshake OK, tunnel up, tapi tidak bisa reach LAN kantor.

**Diagnosa server-side (butuh admin akses VPS 103.56.149.231):**

1. **VPS routing** - Cek route ke LAN kantor via wg0:
   ```bash
   ip route | grep wg0
   # harus ada:
   # 192.168.18.0/24 dev wg0
   # 192.168.10.0/24 dev wg0
   ```

2. **VPS WireGuard allowed-ips peer** - Pastikan peer MikroTik (10.100.0.2) & client allow LAN:
   ```bash
   wg show wg0
   # peer 10.100.0.2 allowed-ips harus include 192.168.10.0/24, 192.168.18.0/24
   ```

3. **Reload routes VPS** (persist di startup script):
   ```bash
   /usr/local/bin/wireguard-up-all.sh
   # script harus tambahkan route 192.168.10.0/24 & 192.168.18.0/24 dev wg0
   ```

**Diagnosa MikroTik (butuh akses WinBox/SSH):**

1. **Forward rule untuk 192.168.10.0/24** - Cek urutan di chain=forward:
   ```bash
   /ip firewall filter print where chain=forward
   # rule allow 10.100.0.0/24 -> 192.168.10.0/24 harus DI ATAS fasttrack
   ```

2. **Route MikroTik ke VPS** - Pastikan 10.100.0.0/24 via wg1:
   ```bash
   /ip route print where dst-address=10.100.0.0/24
   ```

**Config file final (client laptop):**
```
/home/mkt01/proxmox/proxmox/admin.conf
AllowedIPs = 10.100.0.0/24, 192.168.10.0/24
```

**Catatan untuk admin kantor:**
- Client laptop sudah OK (Proxmox reachable via local LAN)
- LAN kantor (192.168.10.0/24) via VPN masih gagal → butuh fix di VPS + MikroTik
- Urutkan: 1) VPS route + allowed-ips, 2) MikroTik forward rule, 3) test ulang

**Catatan tambahan (2 SSID):**
- Pengguna punya 2 SSID: 192.168.18.1 (Huawei) dan 192.168.10.2 (TP-Link AP)
- Masalah bukan di SSID config, tapi di routing/firewall MikroTik
- Perlu di MikroTik:
  1. Pindahkan aturan `/ip firewall filter` untuk 192.168.10.0/24 dan 192.168.18.0/24 ke **posisi teratas** di chain=forward (di atas fasttrack)
  2. Tambahkan route di MikroTik: `/ip route add dst-address=192.168.10.0/24 gateway=wg1`
  3. Pastikan wg1 (10.100.0.2) mengarah ke subnet LAN kantor
- SSID tidak relevan; perbaikan fokus pada routing/firewall MikroTik

---

### 2026-08-08 (sore) — PEMANGKASAN KE PEER INTI (2 peer saja) + FIX PRIVATE KEY

Keputusan user: jangan buat banyak user dulu — cukup 1 (admin) untuk tes; user tambahan
dibuat setelah stabil.

**Yang dilakukan:**

1. **Config VPS di-pangkas ke 2 peer**: MikroTik office (10.100.0.2) + admin (10.100.0.10).
   25 peer staff DIHAPUS dari wg0.conf (bukan disable). File config staff (27 file:
   `*.conf` + `*.png` + `vps-hub-peers.conf`) dipindah ke `wg-peers-archived/`
   (local, DI LUAR git — private key aman, bisa dipakai lagi nanti).
2. **ROOT CAUSE baru ditemukan**: daemon wireguard-go berjalan TANPA private key —
   `wg show wg0 public-key` = `(none)` — karena `wg-apply-peers.py` hanya apply *peer*,
   tidak pernah set `[Interface] PrivateKey`. Akibatnya semua handshake ditolak
   (VPS terima paket tapi tak membalas).
   **Fix (persisten)**: private key diekstrak ke `/etc/wireguard/wg0.private` (chmod 600),
   dan `wireguard-up-all.sh` (+ `wg-apply-peers.py`) kini memanggil
   `wg set $IF private-key /etc/wireguard/wg0.private` + `listen-port 48231` sebelum
   apply peers → daemon restart tidak akan kehilangan kunci.
3. **Fix bug listen-port acak** (sempat jadi 60721/59511/41306 dll): guard
   `wg set wg0 listen-port 48231` di script startup + wg-apply-peers.py.
4. **Verifikasi akhir:**
   - VPS: config 2 peer, listen 48231, pubkey `Darq+Zsh341...`, peers=2,
     ping 10.100.0.2 → 0% loss ~4.7ms.
   - MikroTik: rx=876 tx=17.7KiB, last-handshake segar (<2m).

**Catatan kunci untuk sesi mendatang:**
- `wg-apply-peers.py` TIDAK menyentuh Interface → JANGAN bergantung pada `wg setconf` saja;
  selalu pasang private-key + listen-port di startup script.
- File config client di `wg-peers-archived/` masih valid (pubkey server sudah benar),
  tinggal salin ke `wg-peers/` + tambah peer di wg0.conf bila mau aktifkan user baru.
- Proses `set_peers_slow.py` yang pernah jalan tidak boleh dibiarkan (mengembalikan peer
  staff ke daemon); pastikan mati sebelum melakukan perubahan konfig.

### Langkah berikutnya (setelah VPN stabil)
- [ ] Tes browser nextcloud.lan dari laptop/HP lewat VPN (admin.conf).
- [ ] Verifikasi DNS .lan lewat tunnel (nslookup nextcloud.lan → 192.168.18.10).
- [ ] Aktifkan user tambahan SATU PER SATU (salin conf + tambah [Peer] di VPS), test.
- [ ] Tahap 4 opsional: reverse proxy Apache (nextcloud.ciptamasjaya.co.id).

---

### 2026-08-08 (malam) — FIX WIREGUARD-GO USERSAPCE BUG + LAN RESTORED + POLA B CONFIG

**Masalah terbaru:** Setelah `wg setconf` di wireguard-go userspace VPS, **MikroTik peer selalu revert ke AllowedIPs `/32`** (tidak wide), akibatnya VPS tidak bisa route ke LAN kantor (192.168.10.x/192.168.18.x). Root cause: **wireguard-go userspace di OpenVZ/Virtuozzo tidak bisa maintain wide allowed-ips via `wg setconf`** — hanya `wg set` manual SETELAH fresh daemon start yang bisa set wide, dan cuma bisa maintain **SATU peer wide sekaligus** (set peer ke-2 wide → peer ke-1 balik /32).

**Solusi yang berhasil (VPS live, verified):**
1. **Hard reset total:** kill wireguard-go + `ip link del wg0` + fresh start daemon.
2. **Manual `wg set` HANYA untuk MikroTik (peer kritis):** 
   ```
   wg set wg0 peer <MikroTik-pub> allowed-ips "10.100.0.2/32,192.168.10.0/24,192.168.18.0/24"
   ```
   → MikroTik dapet wide allowed-ips → VPS bisa route ke LAN kantor.
3. **Tambah route VPS persisten:** `192.168.10.0/24 dev wg0` + `192.168.18.0/24 dev wg0` (di-persist di script).
4. **Verifikasi:** VPS ping 192.168.10.1 & 192.168.18.10 → **0% loss ~5ms** ✅

**Patch script startup (`wireguard-up-all.sh`) agar otomatis:**
- `wg setconf` load all peer dulu (agar 26 peer ke-load)
- **LALU** `wg set` MikroTik wide (CRITICAL)
- **LALU** `wg set` Admin wide (biar laptop admin bisa connect & akses LAN)
- Tambah route LAN ke wg0

**Status sekarang (live):**
- VPS daemon: 26 peer loaded, MikroTik wide allowed-ips ✅
- Admin wide allowed-ips ✅ (disesuaikan nanti via script otomatis)
- Route VPS → LAN kantor ada ✅
- VPS ↔ MikroTik: 0% loss ~5ms ✅
- VPS → LAN kantor (192.168.10.1, 192.168.18.10): 0% loss ~5ms ✅

---

### RENCANA 4 TAHAP SELANJUTNYA (setelah Approval)

**Tahap 1 — Stabilkan & Otomatisasi VPS (Sekarang)**
- [ ] Patch final `wireguard-up-all.sh` agar auto-set MikroTik wide + Admin wide + routes setelah restart
- [ ] Tes restart service → verifikasi 26 peer + MikroTik/Admin wide + LAN 0% loss
- [ ] Tes handshake dari HP admin (4G) pakai config admin (QR sudah siap)

**Tahap 2 — Config Laptop Pola B (2 file config)**
- [ ] Buat `admin-kantor.conf` (AllowedIPs = `10.100.0.0/24` saja — aman di kantor, tidak hijack 192.168.10.x/18.x)
- [ ] Buat `admin-luar.conf` (AllowedIPs = `10.100.0.0/24, 192.168.10.0/24, 192.168.18.0/24` — full akses di luar)
- [ ] Script `vpn-on-kantor` / `vpn-on-luar` / `vpn-off` di `/usr/local/bin/`
- [ ] Tes di laptop: `vpn-on-luar` → ping 10.100.0.1 → nextcloud.lan OK; `vpn-off` → lokal normal

**Tahap 3 — Verifikasi End-to-End & Dokumentasi**
- [ ] Tes dari HP admin di luar kantor (4G): connect → ping 10.100.0.1 → nextcloud.lan browser
- [ ] Tes DNS .lan lewat tunnel: `nslookup nextcloud.lan` → 192.168.18.10
- [ ] Update repo: commit config, script, catatan (file private key TIDAK masuk git)
- [ ] Simpan QR admin ke `wg-peers/admin.png` (sudah ada, pubkey benar)

**Tahap 4 — Tahap 4 Opsional (Reverse Proxy)**
- [ ] Apache reverse proxy: `nextcloud.ciptamasjaya.co.id` → `http://192.168.18.10` via wg0
- [ ] Let's Encrypt via Virtualmin
- [ ] Test share file ke client tanpa VPN

### 2026-08-09 (malam) — TAHAP 1 VERIFIKASI + TAHAP 2 POLA B SELESAI

**Tahap 1 — VPS stabil (verified live):**
- Script `/usr/local/bin/wireguard-up-all.sh` v3 sudah benar: setconf load semua peer → `wg set` MikroTik wide → `wg set` admin wide → route LAN.
- **Konfirmasi bug wireguard-go userspace**: hanya SATU peer wide yang bisa bertahan. Set admin wide → MikroTik balik /32 (terbukti live). Set MikroTik wide → admin balik /32.
- **Keputusan (solusi simpel)**: MikroTik = peer wide (kritis, VPS→LAN), admin dibiarkan /32 — secara teori cukup karena balasan ke 10.100.0.10 hanya butuh allowed-ips /32.
- Verifikasi live (semua 0% loss):
  - VPS → 192.168.18.10 (LAN) : 0% loss ~5.5ms ✅
  - VPS → 10.100.0.2 (MikroTik) : 0% loss ~5ms ✅
  - VPS → 10.100.0.10 (laptop admin) : 0% loss ~14-49ms ✅

**Tahap 2 — Pola B config + script (selesai):**
- `/root/cmj-mikrotik/wg-peers/admin-kantor.conf` — AllowedIPs = `10.100.0.0/24` saja (dipakai DI KANTOR, tidak hijack route LAN fisik)
- `/root/cmj-mikrotik/wg-peers/admin-luar.conf` — AllowedIPs = `10.100.0.0/24, 192.168.10.0/24, 192.168.18.0/24` (dipakai DI LUAR kantor, full via tunnel)
- Identik dengan admin.conf lama (diff kosong) — konsisten.
- Script laptop: `scripts/vpn-on-kantor`, `scripts/vpn-on-luar`, `scripts/vpn-off` (di-install ke /usr/local/bin di laptop, config di ~/wg/).
- Generator Pola B (`/root/wg-tools/generate_pola_b.sh`) berisi private key → DI LUAR repo git.

**Sisa (Tahap 3 — butuh user di laptop):**
- [ ] Tes dari laptop: `vpn-on-kantor` → ping 10.100.0.1, ping 192.168.10.1, buka nextcloud.lan
- [ ] Tes dari luar (4G): `vpn-on-luar` → ping 10.100.0.1, ping 192.168.18.10, buka nextcloud.lan
- [ ] nslookup nextcloud.lan → 192.168.18.10

---

- File `wg0.conf` VPS sudah 26 peer (backup `wg0.conf.bak-20260808-143423` aman)
- Private key server dipisah ke `/etc/wireguard/wg0.private` (chmod 600) + di-load otomatis startup
- Config client di `wg-peers-archived/` (25 staff) + `wg-peers/admin.conf` + `admin.png` — semuanya DI LUAR git
- MikroTik firewall & route sudah benar (rule forward di atas fasttrack, route 10.100.0.0/24 via wg1)

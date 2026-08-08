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

### Tahap 4 (opsional) — file share ke client
- [ ] Reverse proxy Apache: nextcloud.ciptamasjaya.co.id → 192.168.18.10 via wg0.

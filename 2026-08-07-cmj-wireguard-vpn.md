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

## Log eksekusi (diisi setelah approve)

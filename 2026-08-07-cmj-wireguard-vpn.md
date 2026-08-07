# CMJ WireGuard VPN — Plan

Tanggal: 2026-08-07 (malam, weekend)
Status: MENUNGGU APPROVAL
Repositori: github.com/arisciwek/cmj-mikrotik

## Goal

Karyawan (15 orang, bisa bertambah sampai <50) bisa akses layanan kantor
(nextcloud, samba, virtualmin) dari mana saja via VPN WireGuard — tanpa buka
port 80/443 ke publik. "Ngantor di mana saja".

## Arsitektur

```
Internet (dari mana saja)
   │  UDP 48231
   ▼
vpn.ciptamasjaya.co.id  (A → 103.18.34.188, IP publik statis)
   │
   ▼
Huawei EG8041V5 (192.168.18.1) — PORT FORWARD UDP 48231 → 192.168.18.12
   │
   ▼
MikroTik VM 102 (192.168.18.12) — interface WireGuard wg1, IP 10.100.0.1/24
   │  routing + masquerade (rule VPN-NET sudah ada di config)
   ▼
Layanan kantor: 192.168.18.10 (nextcloud), .11 (samba), .13 (virtualmin),
                 .14 (9router), .12 (mikrotik) + LAN 192.168.10.0/24
```

## Keputusan

- Port: **UDP 48231** (custom, bukan 51820 default — lebih tidak kentara)
- Subnet VPN: **10.100.0.0/24** (VPN-NET — sudah ada di address-list + NAT masquerade di config router)
- Gateway VPN: **10.100.0.1** (IP di interface wg1)
- Alokasi peer: 10.100.0.2 – 10.100.0.60 (59 slot, cukup untuk 50 user)
- Domain: **vpn.ciptamasjaya.co.id** (A record → 103.18.34.188, TTL rendah 60–300s; IP statis dari VPS)
- Akses dari VPN: semua layanan (192.168.18.0/24 + 192.168.10.0/24)
- DNS untuk client VPN: **10.100.0.1** (router; resolve .lan via DNS static)

## Perubahan di MikroTik (VM 102)

1. Interface WireGuard:
   ```
   /interface wireguard add name=wg1 listen-port=48231
   /ip address add address=10.100.0.1/24 interface=wg1
   ```
2. Firewall input (semua sebelum rule DROP):
   ```
   # izinkan WireGuard dari internet
   /ip firewall filter add chain=input action=accept protocol=udp dst-port=48231 comment=CMJ-wg-in
   # izinkan DNS untuk client VPN (agar .lan resolve)
   /ip firewall filter add chain=input action=accept protocol=udp dst-port=53 src-address=10.100.0.0/24
   /ip firewall filter add chain=input action=accept protocol=tcp dst-port=53 src-address=10.100.0.0/24
   ```
3. Firewall forward (VPN → layanan):
   ```
   /ip firewall filter add chain=forward action=accept src-address=10.100.0.0/24 dst-address=192.168.18.0/24
   /ip firewall filter add chain=forward action=accept src-address=10.100.0.0/24 dst-address=192.168.10.0/24
   /ip firewall filter add chain=forward action=accept src-address=192.168.18.0/24 dst-address=10.100.0.0/24
   /ip firewall filter add chain=forward action=accept src-address=192.168.10.0/24 dst-address=10.100.0.0/24
   ```
   (NAT masquerade VPN-NET sudah ada: `src-address=10.100.0.0/24 out-interface-list=WAN`)
4. Backup config sebelum perubahan: `/system backup save name=before-wireguard` + `/export file=before-wireguard`

## Peer & provisioning client (15–50 user)

- Setiap user: 1 pasang key (private di client, public di router), 1 IP dari
  10.100.0.2–60.
- Client config (dibagikan ke user, berisi PRIVATE KEY — TIDAK boleh masuk git):
  ```
  [Interface]
  Address = 10.100.0.X/24
  PrivateKey = <rahasia>
  DNS = 10.100.0.1
  [Peer]
  PublicKey = <public key server>
  Endpoint = vpn.ciptamasjaya.co.id:48231
  AllowedIPs = 192.168.10.0/24, 192.168.18.0/24, 10.100.0.0/24
  ```
- Di router, per user:
  ```
  /interface wireguard peers add interface=wg1 public-key="<pub>" allowed-address=10.100.0.X/32 comment="user-N"
  ```
- Provisioning massal: buat skrip pembangkit (generate keypair + perintah router + file config client) yang jalan di server, output ke folder `/root/cmj-wireguard-clients/` (chmod 700, DI LUAR repo git). Skripnya sendiri boleh di repo (tidak berisi secret), hasilnya tidak.

## Perubahan di luar router

1. **Huawei** (web UI 192.168.18.1): port forward UDP 48231 → 192.168.18.12
2. **DNS** (provider domain): A record `vpn` → 103.18.34.188 (TTL rendah). Sedang propagasi.
3. **Client**: install WireGuard (laptop/HP), import config dari skrip provisioning.

## Verifikasi

- Dari router: `/interface wireguard print`, `/interface wireguard peers print`
- Dari client luar kantor (mis. HP 4G): konek → ping 10.100.0.1 → ping 192.168.18.10 → buka https://nextcloud.lan
- `nslookup nextcloud.lan` via DNS 10.100.0.1 → 192.168.18.10
- Dari router: `/ping 10.100.0.X` (peer aktif)

## Keamanan & catatan

- WireGuard: key kriptografis kuat; tidak ada username/password — yang penting private key tidak bocor.
- Client config berisi private key → distribusi via cara aman (jangan via chat/email plaintext; QR code untuk HP ok).
- VPN user bisa mencapai 192.168.18.x termasuk pve (18.9) — untuk kantor kecil ini diterima; kalau nanti mau lebih ketat, pisah "VPN staff" vs "VPN admin" (subnet berbeda + firewall lebih sempit). Catat sebagai pengembangan berikutnya.
- IP publik statis → tidak perlu DDNS.
- CHR 2GB RAM: WireGuard untuk 50 peer ringan, tidak masalah.
- Kalau user tidak perlu akses LAN 10.x, boleh disempitkan nanti (AllowedIPs tanpa 192.168.10.0/24).

## Log eksekusi (diisi setelah approve)

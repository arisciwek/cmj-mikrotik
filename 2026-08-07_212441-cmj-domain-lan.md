# CMJ Domain Lokal (.lan) — Plan

Tanggal: 2026-08-07 (Jumat malam)
Status: DONE (dieksekusi 2026-08-07 malam, terverifikasi)
Repositori: github.com/arisciwek/cmj-mikrotik

## Goal

User tidak perlu akses IP di URL browser maupun samba. Semua layanan kantor
dipanggil via nama domain lokal pendek, akhiran `.lan` (bukan `.local` —
menghindari ambigu dengan mDNS/Bonjour yang dipakai virtualmin di laptop).

## Keputusan (dari diskusi user)

1. **Domain final: `.lan`** (bukan `cmj.lan`) — paling pendek, enak diketik.
2. **Daftar nama** (pola `nama.lan`):

| Nama | IP | Keterangan |
|---|---|---|
| nextcloud.lan | 192.168.18.10 | VM 100 nextcloud |
| samba.lan | 192.168.18.11 | VM 101 samba (SMB) |
| mikrotik.lan | 192.168.18.12 | VM 102 router WAN |
| virtualmin.lan | 192.168.18.13 | VM 103 virtualmin |
| 9router.lan | 192.168.18.14 | VM 104 9router (nama tetap) |
| pve.lan | 192.168.18.9 | Host Proxmox |
| ap.lan | 192.168.10.2 | TP-Link AP (migrasi dari ap.office.cmj.local) |
| router.lan | 192.168.10.1 | Router LAN side (migrasi router/gateway lama) |

> Bisa ditambah nama lain di kemudian hari (user: "bisa ditambah nanti").

3. **Entry lama (`*.office.cmj.local`)**: dibiarkan sampai Senin (masa
   transisi), lalu dihapus. Weekend ini fokus selesaikan infrastruktur Proxmox.

## Perubahan di router (VM 102 MikroTik)

1. **Tambah DNS static** di `/ip dns static` (8 entry, lihat tabel di atas).
2. **Ubah DHCP option** di `/ip dhcp-server option`:
   - option `domain-search` (code 119): `'office.cmj.local'` → `'lan'`
   - option `domain-name` (code 15): `'office.cmj.local'` → `'lan'`
3. **TIDAK menyentuh**: IP address, route, firewall, NAT — aman.
4. Backup config RouterOS sebelum perubahan (`before-domain-lan`).

## Verifikasi

- Dari client LAN (WiFi TP-Link): `nslookup nextcloud.lan` → 192.168.18.10
- Browser: `https://nextcloud.lan` (dan virtualmin.lan)
- Samba: `\\samba.lan` (Windows) / `smb://samba.lan` (macOS)
- Semua nama lain resolve (mikrotik.lan, 9router.lan, pve.lan, ap.lan)

## Catatan

- Client butuh **renew DHCP** (atau reboot) untuk mendapat suffix search `lan`
  yang baru — lease 1 hari, jadi otomatis dalam ≤24 jam.
- `.lan` bukan TLD resmi, tapi aman untuk DNS internal (tidak akan di-resolve
  publik; request keluar untuk `.lan` tidak akan terjadi dari client karena
  suffix search dijawab DNS router).
- Rollback mudah: kembalikan nilai DHCP option + hapus static baru.

## Follow-up Senin

- Hapus entry lama: `router.office.cmj.local`, `gateway.office.cmj.local`,
  `ap.office.cmj.local` (sudah digantikan router.lan / ap.lan).
- Verifikasi client setelah 1 hari lease (suffix baru aktif).

## Log Eksekusi (2026-08-07 malam)

1. Backup config: `/system backup save name=before-domain-lan` → "Configuration backup saved" ✓
2. Tambah 8 DNS static (verifikasi `/ip dns static print`):
   - nextcloud.lan → 192.168.18.10, samba.lan → 192.168.18.11, mikrotik.lan → 192.168.18.12,
     virtualmin.lan → 192.168.18.13, 9router.lan → 192.168.18.14, pve.lan → 192.168.18.9,
     ap.lan → 192.168.10.2, router.lan → 192.168.10.1
3. Ubah DHCP option: domain-search (119) dan domain-name (15) → `'lan'` ✓
4. Verifikasi resolve dari LAN (via 192.168.10.1): semua 8 nama resolve ke IP yang benar ✓
   (WAN side 18.12 timeout = normal, router hanya layani DNS untuk LAN 192.168.10.0/24)
5. Client butuh renew DHCP (≤24 jam, lease 1d) untuk dapat suffix search `lan`.

## Follow-up Senin (belum dikerjakan)

- Hapus 3 entry lama: `router.office.cmj.local`, `gateway.office.cmj.local`, `ap.office.cmj.local`
- Verifikasi client setelah 1 hari lease (suffix baru aktif)

## Temuan: Urutan DNS penting (2026-08-07 malam, via WiFi Huawei)

- Client WiFi Huawei dapat DNS dari ONT = 192.168.18.1 (Huawei, ISP-locked,
  field DHCP DNS di web UI disable — template ISP mengunci).
- Solusi: set DNS manual di perangkat admin → 192.168.18.12 (MikroTik).
- PENTING — urutan DNS menentukan hasil:
  - `1.1.1.1, 8.8.8.8, 192.168.18.12` → virtualmin.lan TIDAK bisa
    (1.1.1.1 jawab NXDOMAIN cepat untuk .lan, client berhenti di situ)
  - `192.168.18.12, 1.1.1.1, 8.8.8.8` → virtualmin.lan BISA
- Rekomendasi: di WiFi Huawei, DNS manual = `192.168.18.12` SAJA
  (MikroTik sudah forward internet ke 1.1.1.1/8.8.8.8; .lan selalu resolve).

## Perubahan tambahan di router (2026-08-07 malam)

- Firewall input: tambah rule izinkan query DNS (udp+tcp 53) dari
  `192.168.18.0/24` (WiFi Huawei/admin) — sebelumnya hanya 192.168.10.0/24.
  - Rule: `CMJ-allow-dns-wan-admin` (udp & tcp), posisi di atas DROP.
  - Ini memungkinkan client WiFi Huawei query DNS MikroTik untuk domain .lan.
- Verifikasi: resolve .lan dari segmen WAN (query ke 18.12) berhasil
  (nextcloud.lan, virtualmin.lan, samba.lan → IP benar).

# CMJ Domain Lokal (.lan) — Plan

Tanggal: 2026-08-07 (Jumat malam)
Status: MENUNGGU APPROVAL
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

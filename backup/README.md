# CMJ RouterOS Backup & Recovery

Prosedur backup dan recovery untuk router MikroTik VM 102 (CHR 7.23.1).

## File di folder ini

| File | Isi | Dipakai untuk |
|---|---|---|
| `config-full.rsc` | Export mentah lengkap dari router (2026-08-07) | Referensi / diff / arsip |
| `config-import.rsc` | Export TANPA `/ip address` & `/ip route` | Import setelah bootstrap |
| `README.md` | Dokumen ini | Prosedur recovery |

## Kenapa config-import.rsc tidak berisi IP address & route?

Setelah `reset-configuration`, router dalam kondisi kosong (0). Untuk bisa SSH, kita
harus bootstrap manual dulu: IP address (WAN + LAN), default route, dan user.

Kalau file import MASIH berisi `/ip address` dan `/ip route`, import akan error
"duplicate" karena IP/route itu sudah dibuat manual saat bootstrap. Maka dari itu
kedua section itu DIHAPUS dari file import.

> Catatan: user/password TIDAK ada di export `.rsc` (RouterOS sengaja tidak
> mengekspor user). User harus dibuat ulang manual setelah reset.

## Prosedur Recovery (reset → import)

> ⚠️ Lakukan saat jam sepi. Reset memutus semua koneksi LAN/WAN router.

### 1. Reset router ke kondisi 0
```
/system reset-configuration no-defaults=yes
```
(setelah ini router reboot ke kondisi factory, IP kosong, user default `admin` tanpa password?)

### 2. Bootstrap manual via console (qm terminal / monitor+keyboard)
Setelah reset, router belum punya IP. Login via console, lalu:
```
/interface ethernet set [ find default-name=ether1 ] disable-running-check=no
/interface ethernet set [ find default-name=ether2 ] disable-running-check=no

/ip address add address=192.168.18.12/24 comment=WAN interface=ether1 network=192.168.18.0
/ip address add address=192.168.10.1/24 comment=LAN interface=ether2 network=192.168.10.0
/ip route add dst-address=0.0.0.0/0 gateway=192.168.18.1

/user add name=admin-baru group=full password=<PASSWORD_ANDA>
/user remove admin
/ip service set ssh address=192.168.10.0/24,192.168.18.0/24
```

### 3. SSH masuk & verifikasi
```
ssh admin-baru@192.168.18.12
/ip address print        # harus ada WAN + LAN
/ip route print          # harus ada default route
/ping 1.1.1.1            # harus reply
```

### 4. Upload & import config
Dari PC yang bisa akses router:
```
scp config-import.rsc admin-baru@192.168.18.12:/
```
Lalu di SSH router:
```
/import config-import.rsc
```

### 5. Verifikasi lengkap
```
/ip address print
/ip route print
/ip dns print
/ip firewall filter print
/ip firewall nat print
/ping 8.8.8.8
/resolve google.com
```

## Catatan penting

- **Backup binary (`.backup`) JANGAN di-commit ke repo** — berisi user & password.
  Simpan di router + lokal `/root` saja. (Ada `before-dns-fix.backup` di router.)
- Password user baru → isi manual saat bootstrap, jangan pernah masuk file repo.
- Reset-configuration TIDAK menghapus lisensi CHR (tetap di disk).
- File `config-full.rsc` = export mentah (referensi). Jangan di-import langsung
  setelah bootstrap — akan error duplikat (IP/route sudah ada).
- Scheduler `daily-backup` sudah ada di config → otomatis backup harian ke router.

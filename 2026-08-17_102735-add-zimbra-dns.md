# Tambah DNS static zimbra.lan di MikroTik LXC102

## Tujuan
- Menambahkan entri DNS `zimbra.lan` → `192.168.18.19`
- Memastikan klien kantor mendapat DNS server MikroTik lewat DHCP
- Memastikan firewall mengizinkan ICMP (ping) ke alamat Zimbra

## Langkah‑langkah
1. **Backup konfigurasi router**
   ```
   /system backup save name=pre-zimbra-dns
   ```
2. **Tambah entri DNS static**
   ```
   /ip dns static add name=zimbra.lan address=192.168.18.19 ttl=1h type=A comment="zimbra server"
   ```
3. **Pastikan DNS server di‑enable & ter‑publish ke DHCP**
   - Pastikan `/ip dns set servers=192.168.18.12`
   - Tambahkan opsi DHCP domain‑search `.lan` jika belum ada:
     ```
     /ip dhcp-server option set [find code=119] value="'lan'"
     /ip dhcp-server option set [find code=15]  value="'lan'"
     /ip dhcp-server network set [find] dns-server=192.168.18.12
     ```
   - Terapkan perubahan dengan `:ip dhcp-server lease reset` (opsional; klien akan mengambil lease baru pada renew).
4. **Verifikasi**
   - Dari router: `/resolve zimbra.lan` → harus mengembalikan `192.168.18.19`
   - Dari klien kantor (setelah DHCP renew): `nslookup zimbra.lan` atau `ping zimbra.lan` → harus berhasil.
5. **Pastikan firewall mengizinkan ICMP** (biasanya sudah, tapi tambahkan rule eksplisit bila perlu)
   ```
   /ip firewall filter add chain=input protocol=icmp action=accept comment="allow ping to internal hosts"
   ```
6. **Commit (opsional)** – Simpan skrip `.rsc` di `scripts/add-zimbra-dns.rsc` dan commit ke repo.

## Catatan Pitfall
- **Urutan DNS pada klien** – DNS internal (192.168.18.12) harus berada **pertama** dalam daftar DNS klien, bila tidak klien akan mengirim query ke resolver publik yang tidak mengenal `.lan`.
- **Cache** – setelah menambah entri, klien mungkin masih menyimpan cache lama. Lakukan `ipconfig /flushdns` (Windows) atau `systemctl restart systemd-resolved` (Linux) bila masih tidak ter‑resolusi.
- **Backup** – langkah 1 wajib; bila ada masalah, restore dengan `system backup load name=pre-zimbra-dns`.

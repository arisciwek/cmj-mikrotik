# Rencana: Bind‑mount seluruh /var ke /mnt/vmdata/pve/var

## 1. Prasyarat
- Disk SAS sudah ada dan dipasang di `/mnt/vmdata` (lihat `lsblk` → `/dev/sdb1` 1.3 TB).
- Semua layanan yang menulis ke `/var` (systemd‑journald, apt, dpkg, nginx, mysql, dll.) **harus dihentikan** sementara.
- Cadangan singkat (snapshot) LV root `pve-root` dibuat untuk keamanan:
  ```bash
  lvcreate -L 5G -s -n snap-root /dev/pve/root
  ```
- Pastikan ada cukup ruang pada `/mnt/vmdata` (akan dipakai ≈ < 300 GiB untuk seluruh /var saat ini).

## 2. Langkah‑langah

| No | Deskripsi | Perintah yang akan dijalankan |
|----|-----------|------------------------------|
| 1 | **Buat target directory** di SAS | `mkdir -p /mnt/vmdata/pve/var` |
| 2 | **Hentikan layanan kritis** (systemd‑journald, rsyslog, apt‑daily, dll.) | ```bash
systemctl stop systemd-journald.service
systemctl stop rsyslog.service
systemctl stop apt-daily.service
# tambahkan layanan lain bila diperlukan
``` |
| 3 | **Salin isi /var** ke target dengan `rsync -aHAX` (menjaga hard‑link, ACL, xattr). | ```bash
rsync -aHAX --info=progress2 /var/ /mnt/vmdata/pve/var/
``` |
| 4 | **Verifikasi** bahwa semua file tersalin (opsional). | `diff -qr /var /mnt/vmdata/pve/var || echo "perbedaan ditemukan – periksa!"` |
| 5 | **Bersihkan /var** (kosongkan) – hanya setelah yakin bahwa salinan lengkap. | ```bash
rm -rf /var/*
``` |
| 6 | **Bind‑mount** target ke lokasi asal. | `mount --bind /mnt/vmdata/pve/var /var` |
| 7 | **Persist ke /etc/fstab** (bind‑mount pada boot). | ```bash
cat <<EOF >> /etc/fstab
/mnt/vmdata/pve/var   /var   none   bind   0 0
EOF
``` |
| 8 | **Update initramfs** agar bind‑mount dilakukan sebelum layanan systemd‑journald dimulai (penting karena `/var/log/journal` berada di dalam /var). | ```bash
mkdir -p /etc/initramfs-tools/scripts/local-top/bindmount-var
cat <<'EOS' > /etc/initramfs-tools/scripts/local-top/bindmount-var/bindmount-var
#!/bin/sh
PREREQ=""
prereqs()
{
    echo "$PREREQ"
}
case "$1" in
prereqs) prereqs; exit 0 ;;
esac

# Mount bind‑mount
mount -o bind /mnt/vmdata/pve/var /var
EOS
chmod +x /etc/initramfs-tools/scripts/local-top/bindmount-var/bindmount-var
update-initramfs -u
``` |
| 9 | **Restart layanan** (atau reboot) untuk mengaktifkan bind‑mount secara permanen. | ```bash
systemctl start systemd-journald.service
systemctl start rsyslog.service
systemctl start apt-daily.service
# atau cukup reboot
reboot
``` |
|10| **Verifikasi** ruang bebas pada `/` dan keberadaan bind‑mount. | ```bash
df -h /
mount | grep ' on /var '
``` |
|11| **Commit rencana** ke repo (dokumenasi). | ```bash
git add 2026-08-09-bind-mount-var-plan.md
git commit -m "Add bind‑mount plan for moving /var to SAS storage"
git push origin main
``` |

## 📌 Catatan penting
- **Stop layanan**: `systemd-journald` menulis ke `/var/log/journal`. Jika tidak dihentikan, file jurnal akan tetap terbuka dan bind‑mount tidak dapat dipasang secara bersih.
- **Snapshot LV root**: memungkinkan rollback cepat bila sesuatu tidak berjalan (hapus snapshot dengan `lvremove /dev/pve/snap-root` setelah semua beres).
- **Initramfs script**: memastikan bind‑mount terjadi sebelum `systemd` memulai layanan yang mengandalkan `/var`. Tanpa ini, pada boot pertama setelah perubahan, `systemd-journald` akan gagal karena tidak menemukan `/var/log/journal`.
- **Hak akses**: `rsync -aHAX` menyalin semua ACL, extended attributes, dan hak kepemilikan. Pastikan UID/GID tetap konsisten (biasanya tetap karena Anda masih di mesin yang sama).
- **Rollback cepat**: bila bind‑mount tidak bekerja, cukup `umount /var` (jika masih dalam initramfs) atau boot ke rescue mode, hapus baris fstab, dan gunakan snapshot LV root untuk mengembalikan state.

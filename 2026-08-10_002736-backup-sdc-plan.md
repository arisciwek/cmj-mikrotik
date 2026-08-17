# Rencana: Backup Image Disk Proxmox Host /dev/sdc

## Tujuan
- Membuat backup image dari **seluruh disk /dev/sdc** (host Proxmox) sebelum melakukan perubahan bind‑mount /var ke storage SAS.
- Backup ini adalah **fallback** — jika bind‑mount gagal atau menyebabkan masalah, kita bisa restore ke kondisi semula.
- **VM sudah berada di /dev/sdb** (SAS 1.3 TB), jadi backup ini HANYA untuk host Proxmox, bukan VM.

## Info Disk
```
/dev/sdc  = SSD 120GB (boot Proxmox, LVM pve-root, pve-data, pve-swap)
/dev/sdb1 = SAS 1.3TB (mnt/vmdata — tempat image VM sudah disimpan)
/dev/sda  = HDD (mnt/vmbackup — tempat backup akan disimpan)
```

## Bentuk Backup
| Format | Deskripsi | Ukuran Estimasi | Restore Command |
|--------|-----------|-----------------|-----------------|
| **`.img.gz` (raw + gzip)** | Raw image 1:1 dikompres gzip | ≈ 30-50 GB | `gunzip -c <file>.img.gz \| dd of=/dev/sdc bs=4M` |
| **`.qcow2`** (opsional) | Konversi dari raw, bisa di‑import ke Proxmox | ≈ 30-40 GB | `qm importdisk <VMID> <file>.qcow2 local` |

## Lokasi Backup
`/mnt/vmbackup/disk-backups/` — saat ini tersedia ≈ 276 GB free.

---

# DUA ALTERNATIF BACKUP

## ⭐ Alternatif A: Backup via LiveCD (Cold Backup) — DIREKOMENDASIKAN

> Boot server dari **LiveCD/USB** (SystemRescue, Ubuntu Live Server, atau Proxmox Installer mode rescue).
> Tidak ada layanan yang berjalan → tidak ada yang menulis ke disk → backup paling konsisten.

### LiveCD yang bisa dipakai
| LiveCD | Download | Catatan |
|--------|----------|---------|
| **SystemRescue** | https://www.systemrescue.org | Ringan, punya LVM tools bawaan |
| **Ubuntu Live Server 24.04** | https://ubuntu.com/download/server | Familiar, punya LVM + gzip |
| **Proxmox VE Installer** | https://proxmox.com/en/downloads | Bisa masuk shell recovery |

### Langkah‑langkah Alternatif A

#### Langkah 1: Siapkan LiveCD/USB
- Download ISO LiveCD yang dipilih
- Burning ke USB (gunakan `dd` atau Rufus/Etcher)
- Boot server dari USB → pilih mode "Try" atau "Rescue Shell"

#### Langkah 2: Mount disk yang diperlukan
```bash
# Update kernel device nodes
partprobe

# Mount storage backup (HDD /dev/sda)
mkdir -p /mnt/vmbackup
mount /dev/sda1 /mnt/vmbackup

# Mount storage data (SAS /dev/sdb1) — jika diperlukan
mkdir -p /mnt/vmdata
mount /dev/sdb1 /mnt/vmdata

# Buat direktori backup
mkdir -p /mnt/vmbackup/disk-backups
```

#### Langkah 3: Backup raw image (TANPA snapshot, karena tidak ada layanan jalan)
```bash
dd if=/dev/sdc bs=4M status=progress | \
    gzip > /mnt/vmbackup/disk-backups/sdc-backup-$(date +%Y%m%d%H%M%S).img.gz
```

**Estimasi waktu:** ≈ 30-60 menit tergantung kecepatan disk.

> **Kelebihan:** Tidak perlu `lvcreate snapshot`, tidak perlu `systemctl stop`.
> Seluruh disk dalam kondisi **idle** → backup paling bersih.

#### Langkah 4: Verifikasi Checksum
```bash
sha256sum /mnt/vmbackup/disk-backups/sdc-backup-*.img.gz > \
    /mnt/vmbackup/disk-backups/sdc-backup-$(date +%Y%m%d%H%M%S).sha256
```

#### Langkah 5 (Opsional): Konversi ke QCOW2
```bash
# Decompress
gunzip -c /mnt/vmbackup/disk-backups/sdc-backup-*.img.gz > \
    /mnt/vmbackup/disk-backups/sdc-backup-raw.img

# Convert raw → qcow2
qemu-img convert -f raw -O qcow2 \
    /mnt/vmbackup/disk-backups/sdc-backup-raw.img \
    /mnt/vmbackup/disk-backups/sdc-backup-$(date +%Y%m%d%H%M%S).qcow2

# Cleanup
rm /mnt/vmbackup/disk-backups/sdc-backup-raw.img
```

#### Langkah 6: Verifikasi & unmount
```bash
ls -lh /mnt/vmbackup/disk-backups/sdc-backup-*
df -h /mnt/vmbackup

umount /mnt/vmbackup
umount /mnt/vmdata
```

#### Langkah 7: Reboot ke Proxmox normal
```bash
reboot
```

### Kelebihan Alternatif A
- ✅ **Paling aman** — tidak ada proses yang menulis ke disk
- ✅ **Tidak perlu snapshot LV** — menghemat ruang
- ✅ **Tidak perlu stop/start layanan** — lebih simple
- ✅ **Konsistensi terjamin** — disk benar‑benar idle
- ✅ **Restore juga bisa via LiveCD** — prosedur yang sama

### Kekurangan Alternatif A
- ❌ Server harus **downtime** selama backup (≈ 30-60 menit)
- ❌ Memerlukan akses fisik atau IPMI/iLO/iDRAC untuk mount ISO dari remote
- ❌ Jika hanya SSH, perlu reboot ke LiveCD via `reboot` + intercept GRUB

---

## Alternatif B: Backup Online (dari Proxmox yang sedang berjalan)

> Backup dilakukan dari Proxmox yang masih berjalan. Menggunakan LV snapshot untuk konsistensi.

### Langkah‑langkah Alternatif B

#### Langkah 1: Buat Snapshot LVs
```bash
# Snapshot root LV (5G cukup untuk perubahan selama backup)
lvcreate -L 5G -s -n snap-root /dev/pve/root

# Snapshot data LV (ukuran tergantung penggunaan aktif)
lvcreate -L 10G -s -n snap-data /dev/pve/data
```

#### Langkah 2: Hentikan Layanan yang Menulis ke Disk (opsional)
```bash
systemctl stop systemd-journald.service
systemctl stop rsyslog.service
systemctl stop apt-daily.service
systemctl stop pve-manager.service
# Tambahkan layanan lain jika diperlukan
```

> **Catatan:** Jika tidak ingin menghentikan layanan, backup tetap bisa dilakukan
> dengan hanya snapshot LVs. Risikonya sedikit perubahan pada data yang sedang aktif ditulis.

#### Langkah 3: Buat Backup Raw Image (gzip)
```bash
mkdir -p /mnt/vmbackup/disk-backups

dd if=/dev/sdc bs=4M status=progress | \
    gzip > /mnt/vmbackup/disk-backups/sdc-backup-$(date +%Y%m%d%H%M%S).img.gz
```

**Estimasi waktu:** ≈ 30-60 menit.

#### Langkah 4: Verifikasi Checksum
```bash
sha256sum /mnt/vmbackup/disk-backups/sdc-backup-*.img.gz > \
    /mnt/vmbackup/disk-backups/sdc-backup-$(date +%Y%m%d%H%M%S).sha256
```

#### Langkah 5 (Opsional): Konversi ke QCOW2
```bash
gunzip -c /mnt/vmbackup/disk-backups/sdc-backup-*.img.gz > \
    /mnt/vmbackup/disk-backups/sdc-backup-raw.img

qemu-img convert -f raw -O qcow2 \
    /mnt/vmbackup/disk-backups/sdc-backup-raw.img \
    /mnt/vmbackup/disk-backups/sdc-backup-$(date +%Y%m%d%H%M%S).qcow2

rm /mnt/vmbackup/disk-backups/sdc-backup-raw.img
```

#### Langkah 6: Restart Layanan
```bash
systemctl start systemd-journald.service
systemctl start rsyslog.service
systemctl start apt-daily.service
systemctl start pve-manager.service
```

#### Langkah 7: Bersihkan Snapshot
```bash
lvremove -f /dev/pve/snap-root
lvremove -f /dev/pve/snap-data
```

#### Langkah 8: Verifikasi & Laporkan
```bash
ls -lh /mnt/vmbackup/disk-backups/sdc-backup-*
df -h /mnt/vmbackup
```

### Kelebihan Alternatif B
- ✅ Server tetap **online** selama backup (VM tetap jalan)
- ✅ Tidak perlu akses fisik/IPMI
- ✅ Bisa dilakukan via SSH saja

### Kekurangan Alternatif B
- ❌ Memerlukan **LV snapshot** (butuh ruang ekstra di VG)
- ❌ Ada risiko **sedikit inkonsistensi** pada data yang sedang ditulis
- ❌ Server tetap berjalan → CPU/IO terbagi (backup lebih lambat)

---

## Perbandingan Alternatif

| Kriteria | Alternatif A (LiveCD) | Alternatif B (Online) |
|----------|----------------------|----------------------|
| **Konsistensi backup** | ⭐ Paling konsisten (cold) | Bagus (dengan snapshot) |
| **Downtime server** | ≈ 30-60 menit | 0 (tetap jalan) |
| **Ruang di VG pve** | Tidak butuh | Butuh 15G untuk snapshot |
| **Risiko kegagalan** | ⭐ Sangat rendah | Rendah |
| **Kemudahan restore** | ⭐ Sangat mudah (LiveCD juga) | Mudah (dari running Proxmox) |
| **Akses yang dibutuhkan** | Fisik/IPMI atau reboot via SSH | SSH saja |

---

# Restore (Fallback) — Untuk KEDUA Alternatif

### Restore dari file .img.gz ke /dev/sdc
```bash
# 1. Boot dari LiveCD (atau Proxmox rescue shell)

# 2. Mount storage backup
mkdir -p /mnt/vmbackup
mount /dev/sda1 /mnt/vmbackup

# 3. Deactivate semua LV di /dev/sdc
vgchange -an pve

# 4. Restore
gunzip -c /mnt/vmbackup/disk-backups/sdc-backup-YYYYMMDDHHMMSS.img.gz | \
    dd of=/dev/sdc bs=4M conv=fsync status=progress

# 5. Aktifkan kembali LV
vgchange -ay pve

# 6. Reboot
reboot
```

### Restore dari file .qcow2
```bash
# 1. Boot ke Proxmox normal
# 2. Import ke Proxmox:
qm importdisk <VMID> /mnt/vmbackup/disk-backups/sdc-backup-YYYYMMDDHHMMSS.qcow2 local

# 3. Attach disk ke VM atau replace disk root
qm set <VMID> -scsi0 local:vm-<VMID>-disk-0
```

---

## Catatan Penting
- **VM tidak perlu di‑backup** — sudah berada di /dev/sdb (SAS), terpisah dari host Proxmox.
- **Alternatif A (LiveCD) direkomendasikan** karena paling aman dan konsisten.
- **Enkripsi** (opsional): Tambahkan `gpg --symmetric` jika backup berisi data sensitif.
- **Ruang:** Pastikan `/mnt/vmbackup` memiliki minimal 60 GB free (untuk file gzip ≈ 30‑50 GB).
- **Rollback:** Jika bind‑mount bermasalah, restore dari backup lebih cepat daripada memperbaiki manual.

---

## Pilihan
| | Alternatif A (LiveCD) | Alternatif B (Online) |
|--|----------------------|----------------------|
| **Direkomendasikan?** | ⭐ Ya | Boleh |

> **Rekomendasi:** Gunakan **Alternatif A (LiveCD)**. Server downtime 30-60 menit
> terbayar dengan konsistensi backup yang sempurna. Setelah backup selesai, server
> boot normal → jalankan bind-mount /var.

---

## Urutan Eksekusi Keseluruhan
1. **Backup /dev/sdc via LiveCD** (Alternatif A) → file .img.gz tersimpan di /mnt/vmbackup
2. **Reboot ke Proxmox normal**
3. **Jalankan bind-mount /var** (lihat: 2026-08-09-bind-mount-var-plan.md)
4. **Verifikasi** semua berjalan normal

## File Terkait
- `/root/cmj-mikrotik/2026-08-09-bind-mount-var-plan.md` — rencana bind‑mount /var
- `/root/cmj-mikrotik/2026-08-09-backup-sdc-plan.md` — rencana ini (backup host Proxmox)

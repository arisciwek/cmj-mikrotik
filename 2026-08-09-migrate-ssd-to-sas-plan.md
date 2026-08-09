# Rencana: Pindahkan LXC 105 ke SAS & Hapus Thin Pool (Free 42GB di SSD)

## Tujuan
- Memindahkan **LXC 105 (9router1)** dari thin pool `pve-data` di SSD ke storage SAS (`HDD01SAS2TB`).
- **Menghapus thin pool** `pve-data` dari VG `pve`.
- **OS Proxmox tetap di SSD** — tidak perlu pindah /usr, /var, /root.
- Hasil: VFree di VG bertambah dari **12.25 GB → ~54 GB**.

## Situasi Saat Ini
```
VG pve (di SSD /dev/sdc3): Total 99 GB, VFree 12.25 GB
├─ root     34.75 GB  (terpakai 6.3 GB)  ← OS Proxmox
├─ swap      8.00 GB                      ← OK
└─ data     42.00 GB  (terpakai 2.6 GB)  ← HANYA LXC 105!
                                          ↑ inilah yang boros ruang

Isi thin pool pve-data:
  └─ vm-105-disk-0 (LXC 105 - 9router1)
     - 8 GB virtual, ~2.6 GB terpakai
     - Saat ini di storage: local-lvm

VM lainnya (100,101,102,103,104,106) sudah di SAS (HDD01SAS2TB).
```

## Situasi Setelah Migrasi
```
VG pve (di SSD /dev/sdc3): Total 99 GB, VFree ~54 GB
├─ root     34.75 GB  (terpakai 6.3 GB)  ← OS Proxmox (tetap)
└─ swap      8.00 GB                      ← OK (tetap)

Thin pool pve-data: DIHAPUS
LXC 105: pindah ke HDD01SAS2TB (SAS)
```

---

# BAGIAN 1: BACKUP

## Backup 1: Image disk /dev/sdc (host Proxmox)

> Direkomendasikan via **LiveCD** (cold backup, paling konsisten).

### LiveCD yang bisa dipakai
| LiveCD | Download | Catatan |
|--------|----------|---------|
| **SystemRescue** | https://www.systemrescue.org | Ringan, LVM tools bawaan |
| **Ubuntu Live Server 24.04** | https://ubuntu.com/download/server | Familiar, LVM + gzip |
| **Proxmox VE Installer** | https://proxmox.com/en/downloads | Bisa masuk shell recovery |

### Backup dari LiveCD
```bash
# Mount backup HDD
mkdir -p /mnt/vmbackup/disk-backups
mount /dev/sda1 /mnt/vmbackup

# Backup seluruh /dev/sdc
dd if=/dev/sdc bs=4M status=progress | \
    gzip > /mnt/vmbackup/disk-backups/sdc-backup-$(date +%Y%m%d%H%M%S).img.gz

# Verifikasi checksum
sha256sum /mnt/vmbackup/disk-backups/sdc-backup-*.img.gz > \
    /mnt/vmbackup/disk-backups/sdc-backup-$(date +%Y%m%d%H%M%S).sha256
```

**Estimasi waktu:** ≈ 30-60 menit

### Alternatif B: Backup Online (dari Proxmox yang jalan)
```bash
# Snapshot LV
lvcreate -L 5G -s -n snap-root /dev/pve/root

# Backup
mkdir -p /mnt/vmbackup/disk-backups
dd if=/dev/sdc bs=4M status=progress | \
    gzip > /mnt/vmbackup/disk-backups/sdc-backup-$(date +%Y%m%d%H%M%S).img.gz

# Hapus snapshot
lvremove -f /dev/pve/snap-root
```

## Backup 2: Konfigurasi Proxmox
```bash
mkdir -p /mnt/vmbackup/config-backup

cp -a /etc/pve /mnt/vmbackup/config-backup/pve-conf
cp -a /etc/network/interfaces /mnt/vmbackup/config-backup/
cp -a /etc/fstab /mnt/vmbackup/config-backup/
cp -a /etc/pve/storage.cfg /mnt/vmbackup/config-backup/

lsblk -f > /mnt/vmbackup/config-backup/lsblk-output.txt
pvs > /mnt/vmbackup/config-backup/pvs-output.txt
vgs > /mnt/vmbackup/config-backup/vgs-output.txt
lvs > /mnt/vmbackup/config-backup/lvs-output.txt
blkid > /mnt/vmbackup/config-backup/blkid-output.txt
```

## Backup 3: Dump LXC 105
```bash
# Backup konfigurasi & data LXC 105
pct dump 105
# atau
vzdump 105 --compress zstd --storage vmbackup
```

---

# BAGIAN 2: MIGRASI LXC 105 ke SAS

> **Dilakukan dari Proxmox yang berjalan** (online migration).
> Tidak perlu LiveCD, tidak perlu reboot.

### Langkah 1: Stop LXC 105
```bash
pct stop 105
```

### Langkah 2: Pindahkan disk LXC 105 dari local-lvm ke HDD01SAS2TB
```bash
# Cara 1: Migrate disk (paling bersih)
qm disk migrate 105 --target-storage HDD01SAS2TB

# Cara 2: Jika cara 1 tidak work untuk LXC, lakukan manual:
#   a. Buat target di SAS
pvesm alloc HDD01SAS2TB 105 vm-105-disk-0 8G
#   b. Copy data dari thin pool ke target baru
dd if=/dev/pve/vm--105--disk--0 of=/dev/mapper/HDD01SAS2TB-vm--105--disk--0 bs=4M status=progress
#   c. Update config LXC
pct set 105 --rootfs HDD01SAS2TB:vm-105-disk-0
```

### Langkah 3: Verifikasi LXC 105 di storage baru
```bash
pvesm list HDD01SAS2TB
# Harus ada: vm-105-disk-0

pct config 105
# rootfs harus menunjuk: HDD01SAS2TB:vm-105-disk-0
```

### Langkah 4: Test boot LXC 105
```bash
pct start 105
pct status 105

# Test akses
pct exec 105 -- hostname
pct exec 105 -- systemctl status 9router
pct exec 105 -- curl -s http://localhost:20127 | head -5
```

> **VERIFIKASI KRITIS:** Pastikan LXC 105 berjalan normal di SAS sebelum melanjutkan!

### Langkah 5: Stop LXC 105 lagi (untuk proses hapus thin pool)
```bash
pct stop 105
```

---

# BAGIAN 3: HAPUS THIN POOL pve-data

> **HATI-HATI:** Pastikan LXC 105 sudah benar-benar berpindah dan berjalan normal
> di SAS sebelum menghapus thin pool!

### Langkah 6: Hapus thin volume dari thin pool
```bash
# Hapus virtual disk dari thin pool
lvremove /dev/pve/vm-105-disk-0
# Konfirmasi: y
```

### Langkah 7: Hapus thin pool
```bash
# Hapus thin pool (data_tpool)
lvremove /dev/pve/data
# Konfirmasi: y

# Jika ada error "in use", pastikan semua sudah di-deactivate:
lvchange -an /dev/pve/vm-105-disk-0
lvremove /dev/pve/data
```

### Langkah 8: Hapus metadata & spare
```bash
# Biasanya otomatis terhapus bersama thin pool
# Jika masih ada:
lvremove -f /dev/pve/data_tmeta 2>/dev/null
lvremove -f /dev/pve/lvol0_pmspare 2>/dev/null
```

### Langkah 9: Verifikasi VG setelah hapus
```bash
vgs
# Harusnya:
#   pve   1   2   0 wz--n- <99.00g  ~54.00g
#   (hanya root + swap, VFree ≈ 54 GB)

lvs
# Harusnya hanya ada root dan swap
```

### Langkah 10: Update storage config (hapus local-lvm)
```bash
# Hapus storage local-lvm dari config Proxmox
pvesm remove local-lvm

# Atau edit manual:
nano /etc/pve/storage.cfg
# Hapus bagian:
#   lvmthin: local-lvm
#       thinpool data
#       vgname pve
#       content rootdir,images
```

---

# BAGIAN 4: SELESAI

### Langkah 11: Start LXC 105
```bash
pct start 105
pct status 105
```

### Langkah 12: Verifikasi lengkap
```bash
# 1. Cek VG — VFree harus ~54 GB
vgs

# 2. Cek LXC berjalan
pct status 105
pct exec 105 -- systemctl status 9router

# 3. Cek akses web 9router
curl -s http://192.168.18.15:20127 | head -5

# 4. Cek storage
pvesm status

# 5. Cek free space root SSD
df -h /

# 6. Cek semua VM/LXC
qm list
pct list
```

---

# BAGIAN 5: ROLLBACK (Jika GAGAL)

### Rollback 1: Restore dari backup .img.gz
```bash
# Boot dari LiveCD
gunzip -c /mnt/vmbackup/disk-backups/sdc-backup-*.img.gz | \
    dd of=/dev/sdc bs=4M conv=fsync status=progress
reboot
```

### Rollback 2: Restore LXC 105 dari dump
```bash
# Jika thin pool sudah terhapus tapi LXC bermasalah
pct destroy 105
pct restore 105 /mnt/vmbackup/dump/vzdump-lxc-105-*.tar.zst \
    --storage local-lvm
```

### Rollback 3: Restore storage config
```bash
# Jika local-lvm sudah dihapus tapi perlu dikembalikan
cat <<'EOF' >> /etc/pve/storage.cfg

lvmthin: local-lvm
    thinpool data
    vgname pve
    content rootdir,images
EOF
```

---

# BAGIAN 6: CATATAN PENTING

1. **SELALU backup sebelum menghapus thin pool** — rollback tidak mungkin tanpa backup.
2. **Pastikan LXC 105 verified** berjalan normal di SAS SEBELUM hapus thin pool.
3. **Jangan wipe /dev/sdc** — SSD tetap boot disk, hanya thin pool yang dihapus.
4. **VFree bertambah ~42 GB** — ruang ini bisa dipakai untuk LV baru, extend root, dll.
5. **Local-lvm dihapus dari storage config** — tidak ada lagi storage LVM thin.

---

# ESTIMASI WAKTU

| Langkah | Estimasi Waktu |
|---------|---------------|
| Backup /dev/sdc (LiveCD) | 30-60 menit |
| Backup konfigurasi + dump LXC | 5 menit |
| Migrasi LXC 105 ke SAS | 5-10 menit |
| Hapus thin pool | 1-2 menit |
| Verifikasi | 5 menit |
| **TOTAL** | **≈ 40-80 menit** |

> Sebagian besar waktu adalah backup image /dev/sdc. Migrasi + hapus thin pool
> hanya **~15 menit**. Jauh lebih cepat dari rencana sebelumnya!

---

# URUTAN EKSEKUSI

```
FASE 1: BACKUP
  1. Backup konfigurasi Proxmox + dump LXC 105
  2. Reboot ke LiveCD
  3. Backup /dev/sdc → .img.gz
  4. Reboot ke Proxmox normal

FASE 2: MIGRASI LXC 105
  5. pct stop 105
  6. Migrate disk dari local-lvm → HDD01SAS2TB
  7. pct start 105 → verifikasi berjalan normal
  8. pct stop 105

FASE 3: HAPUS THIN POOL
  9.  lvremove vm-105-disk-0
  10. lvremove data (thin pool)
  11. pvesm remove local-lvm
  12. vgs → VFree harus ~54 GB

FASE 4: SELESAI
  13. pct start 105
  14. Verifikasi semua (VG, LXC, storage, root)
```

## File Terkait
- `/root/cmj-mikrotik/2026-08-09-migrate-ssd-to-sas-plan.md` — rencana ini
- `/root/cmj-mikrotik/2026-08-09-backup-sdc-plan.md` — rencana backup host Proxmox
- `/root/cmj-mikrotik/2026-08-09-bind-mount-var-plan.md` — rencana lama (TIDAK DIPERLUKAN lagi)

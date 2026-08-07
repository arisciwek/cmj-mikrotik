# CMJ Office — Perbaikan Internet Client, DNS, dan WiFi (Plan)

> **Status:** PROGRESS — Task 1 (DNS fix) & Task 4 (channel WiFi) **SELESAI & terverifikasi**. Task 2 (IP conflict + pindah bridge ke enp9s0f0) & Task 3 (DHCP reservation AP) **belum dieksekusi** — menunggu konfirmasi jadwal (jam sepi). Task 5 (verifikasi end-to-end) belum tuntas.

**Goal:** Client LAN (via TP-Link AP) bisa konek internet dengan stabil: DNS resolusi jalan, gateway stabil, WiFi tidak drop ke signal 0.

**Lingkup:** VM 102 (MikroTik CHR 7.23.1, 192.168.18.12 WAN / 192.168.10.1 LAN), host Proxmox (pve), TP-Link AP mode (192.168.10.2), Huawei EG8041V5 (192.168.18.1, WiFi admin).

**Referensi konfigurasi saat ini:** `~/cmj-mikrotik/scripts/mikrotik-configuration-check-script.rsc` (yang di-import ke router), base config = `mikrotik-configuration-script.rsc`.

---

## Ringkasan Temuan Diagnosa (sudah diverifikasi, read-only)

### T1. DNS router MATI total untuk client LAN — akar masalah "tidak bisa konek internet"
- Konfigurasi router: `/ip dns` pakai **DoH** (`use-doh-server: https://cloudflare-dns.com/dns-query`, `verify-doh-cert: yes`).
- Firewall **output chain** hanya mengizinkan: established/related, icmp, **dst-port=53 udp**, dst-port=123 udp, lalu **drop semua**.
- DoH butuh koneksi **TCP 443 keluar** → **DIDROP** oleh output chain. Resolver router macet menunggu DoH (`doh-timeout 5s`, `query-total-timeout 10s`) → client timeout.
- **Bukti tes dari host (8 Agu 2026, ~11:00):**
  - `dig @1.1.1.1 google.com` (langsung, baseline): **OK** → internet host sehat.
  - `dig @192.168.18.12 google.com` (dari ADMIN-NET): **timeout** → wajar, input rule DNS hanya untuk 192.168.10.0/24.
  - `dig -b 192.168.10.1 @192.168.18.12 google.com` (simulasi client LAN): **timeout** → DNS router TIDAK menjawab walau source diizinkan firewall.
  - `dig ... +tcp` (TCP 53): **timeout** juga.
- Kesimpulan: client dapat IP dari DHCP, dapat gateway/DNS 192.168.10.1, tapi query DNS tidak pernah dijawab → browser gagal, "tidak bisa konek internet".

### T2. IP CONFLICT: host Proxmox = 192.168.10.1 = IP LAN router
- Host `vmbr1` = **192.168.10.1/24**; router ether2 (LAN) = **192.168.10.1/24** — **dua perangkat, satu IP, satu segmen L2 (vmbr1)**.
- Akibat: ARP untuk 192.168.10.1 (gateway + DNS client) dijawab bergantian oleh host (yang tidak NAT/forward) dan router → koneksi client **intermiten**, bisa terlihat "kadang bisa kadang tidak", plus risk conflict di DHCP/management.
- Ini kandidat penyebab sekunder kenapa internet client tidak stabil, dan bisa mengganggu TP-Link AP kalau AP memakai 192.168.10.1 sebagai gateway.

### T3. WiFi TP-Link signal drop ke 0
- TP-Link dalam **AP mode** (DHCP dimatikan, DHCP diambil alih MikroTik) — ini setup yang benar.
- Signal drop ke 0 = masalah sisi radio AP (bukan DHCP/DNS): kemungkinan **auto channel** bertabrakan dengan WiFi admin Huawei, firmware AP, power supply/PoE tidak stabil, atau AP restart.
- Perlu diagnosa on-site via web UI AP (192.168.10.2) — tidak bisa 100% diperbaiki dari sisi server, tapi bisa dibantu dari sisi konfigurasi.

### T5. NIC host: 2 port bebas + 2 masalah link aktif (ditemukan 2026-08-07)
- Inventaris fisik host (4 port ethernet):
  - **Dipakai:** Broadcom BCM5720 dual (tg3) → `nic0` = vmbr0 (192.168.18.9), `nic1` = vmbr1 (192.168.10.1). Keduanya UP.
  - **Bebas:** Intel 82580 dual (igb) → `enp9s0f0`, `enp9s0f1` — DOWN, tanpa kabel/link, belum ada konfigurasi di /etc/network/interfaces.
- Masalah link aktif:
  1. **nic0 & nic1 hanya 100Mb/s** (NIC Gigabit tapi negosiasi 100M) → kabel/port switch/auto-neg bermasalah atau peer memang 100M.
  2. **nic1 (LAN) flapping** — dmesg menunjukkan link down/up berulang dalam hitungan detik → sumber instabilitas segmen LAN, kandidat penyebab client "kadang putus" di sisi fisik.
- Peta segmen (hasil cek qm config, 2026-08-07):
  - vmbr0 (nic0 → Huawei): host mgmt 192.168.18.9 + SEMUA VM (100 nextcloud, 101 samba, 102 mikrotik ether1/WAN, 103 virtualmin, 104 9router).
  - vmbr1 (nic1 → TP-Link AP?): hanya VM102 ether2 (LAN 192.168.10.1) + host 192.168.10.1 (konflik) + physical nic1.
- Keputusan kabel (user punya 1 kabel RJ45 cadangan, 2026-08-07):
  - **Langkah 1 (tanpa kabel baru):** pindahkan kabel LAN dari nic1 → port Intel bebas (enp9s0f1), vmbr1 bridge-ports → enp9s0f1. Keluar dari port BCM yang flapping. Kalau flapping masih terjadi → ganti kabelnya dengan yang cadangan.
  - **Langkah 2 (pakai kabel cadangan → Huawei):** enp9s0f0 → Huawei LAN port bebas, buat bridge baru vmbr2, pindahkan VM102 net0 (ether1/WAN) ke vmbr2. Router dapat jalur WAN dedicated, terpisah dari NIC management host.
  - Identifikasi port Intel secara fisik: colok kabel lalu cek `ethtool enp9s0f1 | grep "Link detected"` (atau f0) untuk tahu mana port yang kepasang.
  - Catatan: pindah bridge VM102 net0 butuh restart VM (downtime singkat); lakukan saat jam sepi.
- Status fisik TERBARU (setelah user swap kabel nic1 + tambah kabel baru, 2026-08-07 ~13:35 WIB):
  - **Swap kabel nic1 = SUKSES**: dmesg menunjukkan down di tick 149222, up di 149286, lalu STABIL (tidak ada flapping lagi ±15 menit). Penyebab flapping = kabel lama, bukan port. TP-Link AP (192.168.10.2, c0:3a:55:ad:5f:c4) reachable via vmbr1, 0% loss.
  - **Kabel baru ke TP-Link = TERDETEKSI di enp9s0f0** (Intel 82580 port 1) setelah `ip link set enp9s0f0 up`: link UP 100Mb/s Full Duplex (konsisten — port AP kemungkinan 100M). enp9s0f1 masih kosong.
  - **LOOP RISK**: sekarang ada 2 jalur host→TP-Link (nic1 dan enp9s0f0). JANGAN bridge keduanya ke vmbr1 tanpa STP (loop L2 / broadcast storm). Keputusan pemakaian masih DISKUSI (Opsi A: vmbr1 → enp9s0f0, nic1 jadi cadangan — rekomendasi; Opsi B: simpan enp9s0f0 untuk WAN dedicated/management; Opsi C: dual dengan STP, tidak disarankan).

### T6. DNS router TERVERIFIKASI HIDUP — root cause sebenarnya = DoH (ditemukan 2026-08-07 ~17:36 WIB)
- **Bukti packet capture** (tcpdump di vmbr0, host satu bridge dengan router): query `192.168.18.12 → 1.1.1.1:53` dan `→ 8.8.8.8:53` KELUAR dan reply MASUK normal (google.com → CNAME forcesafesearch → 216.239.38.120; mikrotik.com → 159.148.172.205). Cache DNS router berisi google.com & mikrotik.com → `/resolve` dan `allow-remote-requests` bekerja.
- **Root cause asli:** DoH (`use-doh-server=https://cloudflare-dns.com/dns-query`) butuh TCP 443 keluar, TAPI output chain router hanya mengizinkan icmp/udp53/udp123 (+tcp53 setelah fix) dan DROP sisanya → resolver mati selama DoH aktif. Fix Opsi A (DoH off, 2026-08-07) = resolver hidup. Rule `CMJ-allow-tcp-dns-out` kini valid di index 6 (sebelum drop index 4).
- **Catatan metodologi:** tes `dig -b 192.168.10.1 @192.168.18.12` dari host TIDAK VALID — paket masuk via WAN (vmbr0) dengan source IP LAN, reply router nyasar ke segmen ether2 (LAN) dan tidak kembali ke host → timeout ≠ bukti DNS mati. Verifikasi LAN yang benar: client beneran di 192.168.10.x, ATAU dari host setelah Task 2 (host dapat 192.168.10.250 di segmen LAN).
- **Observasi:** reply google.com dari 1.1.1.1 berisi CNAME `forcesafesearch.google.com` → indikasi Huawei/ISP intercept & paksa SafeSearch (fitur parental control Huawei ONT). Tidak memutus koneksi, tapi search Google ter-filter. Opsional dicek di web UI Huawei (192.168.18.1) bila mau dimatikan.
- **Catatan desain:** output chain (by design dari base config) memblokir TCP keluar router selain 53 → fetch/update/DoH dari router tidak jalan. Aman untuk client (client lewat FORWARD chain), hanya catatan untuk kebutuhan admin di masa depan.

### T4. Temuan sekunder (dicek saat eksekusi)
- Rule `fasttrack-connection` pertama di forward chain tanpa filter out-interface — aman umumnya, tapi lebih baik dibatasi ke WAN; juga berpotensi mengganggu kalau ada VPN/queue.
- `admin` user masih aktif (hasil verifikasi lama menunjukkan last-logged-in), `admin-baru` & BLACKLIST belum terkonfirmasi — sesuai section 9-10 check script.
- DHCP pool hanya 100 alamat (100-199) — berisiko habis kalau device > 100.
- NTP client belum diverifikasi (penting untuk timestamp & kalau DoH dipertahankan, karena verify-doh-cert butuh jam yang benar).

---

## Pendekatan yang Diusulkan

1. **Perbaiki DNS dulu (T1)** — ini bloker utama. Pilih opsi A (direkomendasikan) atau B.
   - **Opsi A (rekomendasi): matikan DoH**, pakai DNS biasa 1.1.1.1/8.8.8.8 via UDP 53, tambah izin TCP 53 keluar. Sederhana, sedikit failure mode, cocok untuk router kantor.
   - **Opsi B: pertahankan DoH** + tambah rule output izinkan TCP 443 (idealnya dibatasi ke IP Cloudflare). Lebih privat tapi kompleksitas & syarat jam NTP akurat.
2. **Hilangkan IP conflict (T2)** — pindahkan IP host vmbr1 ke 192.168.10.250/24 (di luar pool DHCP), atau hapus kalau tidak dipakai.
3. **Stabilkan WiFi (T3)** — panduan & langkah di sisi AP (web UI 192.168.10.2): channel tetap, hindari overlap dengan SSID admin Huawei, cek firmware & power; tambah DHCP reservation untuk AP di MikroTik.
4. **Verifikasi end-to-end** dari perspektif client LAN + update dokumen repo.

---

## Step-by-Step Plan

### Task 1: Fix DNS di RouterOS (bloker utama)

> **STATUS: DONE (2026-08-07)** — DoH dimatikan, rule `CMJ-allow-tcp-dns-out` terpasang (valid, sebelum drop). Resolver terverifikasi hidup: cache berisi google.com & mikrotik.com (bukti tcpdump di T6). Verifikasi dari client LAN beneran masih bagian dari Task 5.

**Objective:** Client LAN bisa resolve nama domain via 192.168.10.1.

**Files:**
- Create: `~/cmj-mikrotik/scripts/20-fix-dns.rsc` (versi Opsi A)

**Step 1: Backup config router dulu**
```
/system backup save name=before-dns-fix
/export file=before-dns-fix
```
(lewat SSH `admin@192.168.18.12` atau qm terminal 102)

**Step 2: Import fix DNS (Opsi A)**
```routeros
# 20-fix-dns.rsc
/ip dns set use-doh-server="" verify-doh-cert=no
/ip firewall filter add chain=output action=accept protocol=tcp dst-port=53 comment="CMJ: allow TCP DNS out"
```
Opsi B (kalau dipilih):
```routeros
/ip dns set verify-doh-cert=no
/ip firewall filter add chain=output action=accept protocol=tcp dst-port=443 comment="CMJ: allow DoH out (TCP 443)"
/system ntp client set enabled=yes
```

**Step 3: Verifikasi (harus PASS setelah fix)**
```
# dari host, simulasikan client LAN:
dig -b 192.168.10.1 @192.168.18.12 google.com +short   # -> harus return IP
dig -b 192.168.10.1 @192.168.18.12 +tcp google.com +short
# dari client LAN beneran:
nslookup google.com 192.168.10.1
```
Sebelum fix: timeout. Sesudah fix: IP google.com muncul. Ini bukti sukses.

**Step 4: Re-run check script & simpan hasil**
```
/import mikrotik-configuration-check-script.rsc
```

**Step 5: Commit**
```
cd ~/cmj-mikrotik && git add scripts/20-fix-dns.rsc && git commit -m "fix: disable DoH, allow TCP DNS out"
```

### Task 2: Hilangkan IP Conflict vmbr1 (T2)

**Objective:** Hanya router yang punya 192.168.10.1 di segmen LAN.

**Files:**
- Modify: `/etc/network/interfaces` (host pve)
- Catatan: JANGAN lakukan via koneksi yang lewat 192.168.10.1; kita akses host via vmbr0 (192.168.18.9) / console.

**Step 1:** Edit `/etc/network/interfaces`:
```
iface vmbr1 inet static
    address 192.168.10.250/24    # <- ganti dari 192.168.10.1
    ...
```
**Step 2:** Terapkan: `ifreload -a` (atau `systemctl restart networking`), cek `ip -4 addr show vmbr1`.
**Step 3:** Verifikasi ARP dari sisi LAN: client `arp -n` untuk 192.168.10.1 harus = MAC ether2 router `BC:24:11:F4:9E:3F`, bukan MAC host.
**Step 4:** Cek layanan host yang mungkin bergantung IP lama (monitoring, backup, DNS?) — update referensi ke 192.168.10.250.
**Step 5:** Commit catatan perubahan (bisa jadi file `docs/` di repo).

### Task 3: DHCP Reservation untuk TP-Link AP

**Objective:** IP AP 192.168.10.2 permanen (tidak berubah walau lease habis).

**Files:**
- Create: `~/cmj-mikrotik/scripts/21-dhcp-reservation.rsc`

**Step 1:** Cari MAC AP di lease:
```
/ip dhcp-server lease print
```
**Step 2:** Tambah reservation (isi MAC dari step 1):
```routeros
/ip dhcp-server lease add address=192.168.10.2 mac-address=XX:XX:XX:XX:XX:XX comment="CMJ: TP-Link AP"
```
**Step 3:** Verifikasi: `/ip dhcp-server lease print` → baris AP bound ke .2.

### Task 4: Stabilisasi WiFi TP-Link (T3) — butuh akses web UI AP

**Objective:** Signal tidak drop ke 0; koneksi client stabil.

**Aksi di web UI AP (192.168.10.2), panduan:**
1. Konfirmasi mode = Access Point, DHCP server = OFF (sudah benar menurut user — verifikasi ulang).
2. Wireless 2.4GHz: **channel tetap** (1/6/11), pilih yang TIDAK dipakai SSID admin Huawei (cek channel Huawei via web UI 192.168.18.1). Hindari "Auto".
3. Kalau AP support 5GHz: aktifkan SSID 5GHz untuk user (channel 36/40/44/48), lebih sedikit interferensi.
4. Cek firmware AP → update ke versi terbaru (sering jadi penyebab radio drop).
5. Cek power: PoE/injector/adaptor — kalau drop selalu di jam tertentu, curigai power/panas; kalau acak, curigai channel/interferensi.
6. Batasi SSID 2.4GHz kalau perangkat mendukung 5GHz (atau set airtime fairness kalau ada).

**Aksi di MikroTik (jika perlu):** tidak ada perubahan firewall untuk ini. Reservation sudah di Task 3.

**Verifikasi:** pantau 1-2 hari dengan `~/cmj-mikrotik/scripts/cek-jaringan.sh` di laptop (log di `~/network_logs/`), pastikan tidak ada sample signal 0 dan fluktuasi < 10dBm.

### Task 5: Verifikasi End-to-End & Hardening (opsional/sekunder)

**Objective:** Pastikan client beneran bisa internet + tutup lubang security.

**Step 1: Uji dari client LAN (satu laptop/HP di WiFi user):**
```
ping 192.168.10.1        # gateway -> harus reply dari router
ping 8.8.8.8             # internet IP -> harus reply
nslookup google.com      # DNS -> harus resolve
buka browser -> https://google.com
```
**Step 2: Cek NAT/fasttrack kalau masih gagal:**
```
/ip firewall filter print where chain=forward
/ip firewall nat print
/ip firewall connection print count
```
**Step 3 (opsional, dari check script):** matikan `admin`, pastikan `admin-baru` aktif, BLACKLIST terisi — sesuai section 9-10 `mikrotik-configuration-check-script.rsc`.
**Step 4:** Pertimbangkan perbesar pool DHCP (misal 192.168.10.50-192.168.10.250) kalau device > 100.
**Step 5:** Update `mikrotik-configuration-result.md` dengan hasil verifikasi baru + commit.

---

## Files yang Berubah
- `~/cmj-mikrotik/scripts/20-fix-dns.rsc` (baru)
- `~/cmj-mikrotik/scripts/21-dhcp-reservation.rsc` (baru)
- `/etc/network/interfaces` di host pve (vmbr1 → 192.168.10.250)
- `~/cmj-mikrotik/scripts/mikrotik-configuration-result.md` (update hasil)
- (opsional) `~/cmj-mikrotik/scripts/mikrotik-configuration-script.rsc` — sinkronkan fix DNS agar konfigurasi idempotent

## Risiko & Tradeoff
- **Opsi A (matikan DoH):** kehilangan enkripsi DNS (minor untuk kantor; DNS lokal tetap privat dari ISP karena pakai 1.1.1.1/8.8.8.8 langsung — catatan: lalu lintas DNS tetap terlihat ISP kecuali DoH/DoT).
- **Ganti IP vmbr1:** blip singkat di segmen LAN; jangan dilakukan sambil konek via 192.168.10.1. Service host yang memakai IP lama harus diupdate.
- **WiFi:** perubahan channel/firmware bisa bikin client putus sesaat; lakukan di jam sepi.
- **FastTrack** dibiarkan dulu (tidak disentuh) kecuali verifikasi gagal.
- Semua perubahan di router didahului backup (`/system backup save`) — rollback mudah.

## Open Questions (perlu jawaban sebelum eksekusi)
1. **Kredensial router**: boleh saya SSH ke 192.168.18.12 (user admin/admin-baru + password), atau Anda yang jalankan perintahnya sendiri (saya kasih perintah persisnya)?

jawab: silahkan anda akses.
→ **KEPUTUSAN (2026-08-07): saya (agent) yang akses via SSH. Kredensial disimpan di `/root/cmj-router-credentials` (DI LUAR repo, tidak akan di-commit).**

2. **Akses TP-Link**: web UI 192.168.10.2 bisa diakses dari mana? (laptop admin di WiFi user?) Siapa yang pegang passwordnya?

jawab: web UI 192.168.10.2 dipegang admin.

3. **vmbr1 di host dipakai untuk apa?** (monitoring? backup? cuma kebawa config?) — menentukan apakah diganti 192.168.10.250 atau dihapus.

saat ini hanya ada 1 yang dipakai untuk WAL ke huawei dan LAN ke TP-link.
jika diperlukan tambah eternet sudah saya pasang 1 lagi agar setting lebih leluasa.
saya juga masih ada 1 ethernet kosong (ada 4 port di srver itu)
→ **KEPUTUSAN KABEL (2026-08-07): Opsi A disetujui — vmbr1 pindah dari nic1 → enp9s0f0 (Intel, kabel baru ke TP-Link), nic1 diistirahatkan. enp9s0f1 tetap kosong (cadangan).**

4. **Channel WiFi Huawei (SSID admin)** berapa? (biar TP-Link pilih channel non-overlap)

jawab: channel 6. TP-Link juga channel 6 (SAMA) → **interferensi ko-channel**, kandidat kuat penyebab signal drop ke 0. TP-Link harus pindah ke channel 1 atau 11 (non-overlap dengan 6).
→ **DONE (2026-08-07): TP-Link sudah dipindah ke channel 11** oleh admin (non-overlap dengan Huawei channel 6). Pantau signal beberapa hari untuk konfirmasi perbaikan.

5. **Opsi DNS**: setuju Opsi A (matikan DoH) atau mau pertahankan DoH (Opsi B)?

jawab setuju opsi A
→ **DONE (2026-08-07):** DoH dimatikan, resolver terverifikasi hidup (T6).

6. **WiFi Huawei (SSID admin, 192.168.18.1) mau diapakan?** (kandidat overlap channel dengan TP-Link)

jawab: wifi dari huawei bisa internet; saat ini masih dipakai user untuk keperluan samba.
→ **KEPUTUSAN AWAL (2026-08-07):** WiFi Huawei **TETAP AKTIF** — jangan dimatikan/diubah. Internet-nya jalan dan user masih pakai untuk akses samba (VM101, segmen 192.168.18.x via vmbr0 — reachable dari kedua segmen sudah otomatis: LAN 192.168.10.0/24 → FORWARD → WAN 192.168.18.x). TP-Link tetap di channel 11 (non-overlap dengan Huawei ch 6); tidak ada migrasi paksa user.
→ **PENYEMPURNAAN KEPUTUSAN (2026-08-07, update user):**
- **Kondisi saat ini:** SSID Huawei dipakai user untuk samba (VM101) + internet — **DIIZINKAN sementara** (interim).
- **Kondisi target:** user **HANYA** akses SSID TP-Link (LAN 192.168.10.x → samba + internet). SSID Huawei **khusus admin** — akses darurat ke Proxmox (pve 192.168.18.9 / vmbr0) & router (192.168.18.12).
- **Interim:** SSID Huawei tetap aktif untuk user **selama TP-Link belum bisa diakses** (vmbr1 belum pindah ke enp9s0f0 / WiFi TP-Link belum terverifikasi stabil dari sisi client).
- **Langkah migrasi (setelah TP-Link terverifikasi stabil):** ganti password SSID Huawei via web UI 192.168.18.1 → hanya admin yang tahu; user diarahkan pindah ke SSID TP-Link.
- **Catatan akses admin:** via SSID Huawei masuk segmen 192.168.18.x → pve 192.168.18.9 (Proxmox UI) & router 192.168.18.12 — persis untuk kondisi darurat.


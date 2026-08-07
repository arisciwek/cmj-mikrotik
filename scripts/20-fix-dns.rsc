# 20-fix-dns.rsc — CMJ: Fix DNS (Opsi A) — matikan DoH, izinkan TCP DNS keluar
# Status: DITERAPKAN 2026-08-07 via SSH (Opsi A disetujui user).
# Catatan re-import: yang menentukan urutan eksekusi adalah POSISI VERTIKAL rule di list,
# BUKAN angka index-nya. Rule "CMJ-allow-tcp-dns-out" harus tampil DI ATAS rule action=drop
# chain=output (boleh bernomor lebih besar, mis. 6 di atas drop 4 — tetap dieksekusi duluan).
# Kalau posisinya salah setelah import, perbaiki dengan:
#   /ip firewall filter move [find comment="CMJ-allow-tcp-dns-out"] <index-drop-target>

/ip dns set use-doh-server="" verify-doh-cert=no

# izinkan TCP 53 keluar (fallback DNS via TCP) — posisikan sebelum rule drop output
/ip firewall filter add chain=output action=accept protocol=tcp dst-port=53 comment="CMJ-allow-tcp-dns-out"

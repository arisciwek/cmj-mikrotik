# 20-fix-dns.rsc — CMJ: Fix DNS (Opsi A) — matikan DoH, izinkan TCP DNS keluar
# Status: DITERAPKAN 2026-08-07 via SSH (Opsi A disetujui user).
# Catatan re-import: rule "CMJ-allow-tcp-dns-out" HARUS berada SEBELUM rule action=drop
# di chain=output (di sini index 6 sebelum drop index 4). Kalau posisi salah setelah import,
# perbaiki dengan: /ip firewall filter move [find comment="CMJ-allow-tcp-dns-out"] <index-drop>

/ip dns set use-doh-server="" verify-doh-cert=no

# izinkan TCP 53 keluar (fallback DNS via TCP) — posisikan sebelum rule drop output
/ip firewall filter add chain=output action=accept protocol=tcp dst-port=53 comment="CMJ-allow-tcp-dns-out"

#!/bin/bash
set -u

IF="wg0"
SOCK="/run/wireguard/${IF}.sock"

# ============================================================
# CMJ WireGuard Hub - FINAL
# wireguard-go userspace
# HANYA peer MikroTik
# ============================================================

PRIVATE_KEY="/etc/wireguard/privatekey"

MIKROTIK_PUBLIC="jItFxQEe4nxCb/67mA+6nDhAxEmQAZ6lVazF+Ankk2A="
MIKROTIK_ENDPOINT="103.18.34.192:48231"

HUB_ADDR="10.100.0.1/24"
MIKROTIK_ADDR="10.100.0.2/32"
OFFICE_NET="192.168.18.0/24"

WGGO="/usr/local/bin/wireguard-go"

log() {
    echo "$(date '+%F %T') $*"
}

die() {
    log "ERROR: $*"
    exit 1
}

# ============================================================
# 1. Cek binary dan key
# ============================================================

[ -x "$WGGO" ] || die "$WGGO tidak ditemukan"

[ -f "$PRIVATE_KEY" ] || die "$PRIVATE_KEY tidak ditemukan"

# ============================================================
# 2. Pastikan wg0 ada
# ============================================================

if ip link show "$IF" >/dev/null 2>&1; then

    log "$IF sudah ada"

else

    log "Membuat $IF dengan wireguard-go..."

    export WG_I_PREFER_BUGGY_USERSPACE_TO_POLISHED_KERNEL_IMPLEMENTATION=1

    "$WGGO" "$IF" >/tmp/${IF}-wireguard-go.log 2>&1 &

    sleep 2

fi

# ============================================================
# 3. Pastikan socket UAPI tersedia
# ============================================================

for i in $(seq 1 20); do

    if [ -S "$SOCK" ]; then
        break
    fi

    sleep 0.5

done

[ -S "$SOCK" ] || die "UAPI socket tidak tersedia: $SOCK"

log "UAPI socket OK: $SOCK"

# ============================================================
# 4. Konversi key Base64 -> Hex
# ============================================================

PRIVATE_HEX=$(python3 - "$PRIVATE_KEY" <<'PY'
import sys
import base64

with open(sys.argv[1]) as f:
    key = f.read().strip()

print(base64.b64decode(key).hex())
PY
)

[ -n "$PRIVATE_HEX" ] || die "private key gagal dikonversi"

MIKROTIK_HEX=$(python3 - "$MIKROTIK_PUBLIC" <<'PY'
import sys
import base64

print(base64.b64decode(sys.argv[1]).hex())
PY
)

[ -n "$MIKROTIK_HEX" ] || die "public key MikroTik gagal dikonversi"

# ============================================================
# 5. Konfigurasi WireGuard melalui UAPI
#
# TIDAK menggunakan wg set
# TIDAK menggunakan wg setconf
# ============================================================

log "Mengkonfigurasi WireGuard UAPI..."

python3 - "$SOCK" "$PRIVATE_HEX" "$MIKROTIK_HEX" "$MIKROTIK_ENDPOINT" <<'PY'
import socket
import sys

sock_path = sys.argv[1]
private_hex = sys.argv[2]
peer_hex = sys.argv[3]
endpoint = sys.argv[4]

message = (
    "set=1\n"
    f"private_key={private_hex}\n"
    "listen_port=48231\n"

    f"public_key={peer_hex}\n"
    f"endpoint={endpoint}\n"

    "replace_allowed_ips=true\n"
    "allowed_ip=10.100.0.2/32\n"
    "allowed_ip=192.168.18.0/24\n"

    "\n"
)

s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(10)
s.connect(sock_path)
s.sendall(message.encode())

reply = s.recv(4096).decode(errors="replace")

s.close()

if reply.strip():
    print(reply.strip())

if "errno=" in reply and "errno=0" not in reply:
    raise SystemExit(1)
PY

[ $? -eq 0 ] || die "UAPI WireGuard gagal"

# ============================================================
# 6. IP interface
# ============================================================

if ! ip addr show dev "$IF" | grep -q "10.100.0.1/24"; then
    log "Menambahkan $HUB_ADDR..."
    ip addr add "$HUB_ADDR" dev "$IF"
else
    log "$HUB_ADDR sudah ada"
fi

# ============================================================
# 7. UP interface
# ============================================================

ip link set "$IF" up

# ============================================================
# 8. Route kantor
# ============================================================

ip route replace "$OFFICE_NET" dev "$IF"

# ============================================================
# 9. Forwarding
# ============================================================

iptables -C FORWARD -i "$IF" -j ACCEPT 2>/dev/null ||
    iptables -A FORWARD -i "$IF" -j ACCEPT

iptables -C FORWARD -o "$IF" -j ACCEPT 2>/dev/null ||
    iptables -A FORWARD -o "$IF" -j ACCEPT

# ============================================================
# 10. NAT
# ============================================================

iptables -t nat -C POSTROUTING -o venet0 -j MASQUERADE 2>/dev/null ||
    iptables -t nat -A POSTROUTING -o venet0 -j MASQUERADE

# ============================================================
# 11. Verifikasi
# ============================================================

log "============================================"
log "WireGuard CMJ FINAL"
log "============================================"

ip -br addr show "$IF"

echo
echo "ROUTE:"
ip route get 192.168.18.9

echo
echo "PEER:"
wg show "$IF" allowed-ips

echo
echo "DUMP:"
wg show "$IF" dump | grep "^${MIKROTIK_PUBLIC}"

echo
log "=== WIREGUARD CMJ READY ==="

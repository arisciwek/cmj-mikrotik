#!/bin/bash
# WireGuard Peer Generator for CMJ Staff
# Output: configs per user + VPS hub peer config

set -e

OUTDIR="/root/cmj-mikrotik/wg-peers"
mkdir -p "$OUTDIR"

# VPS Hub info
VPS_PUBLIC_KEY="Darq+Zsh341FE56vSKg3EVV8oQAGPr5dTCkSqbcyFgc="
VPS_ENDPOINT="vpn.ciptamasjaya.co.id:48231"
VPN_NETWORK="10.100.0.0/24"
DNS="10.100.0.2"  # MIKROTIK KANTOR - punya DNS static .lan

# Staff list
declare -A STAFF=(
    ["admin"]="10"
    ["budi"]="11"
    ["siti"]="12"
    ["ahmad"]="13"
    ["dewi"]="14"
    ["eko"]="15"
    ["fitri"]="16"
    ["gunawan"]="17"
    ["hani"]="18"
    ["indra"]="19"
    ["joko"]="20"
    ["kartika"]="21"
    ["lestari"]="22"
    ["mulyono"]="23"
    ["nina"]="24"
    ["agus"]="25"
    ["putri"]="26"
    ["rudi"]="27"
    ["sari"]="28"
    ["tono"]="29"
    ["uli"]="30"
    ["vina"]="31"
    ["wawan"]="32"
    ["yuni"]="33"
    ["zaki"]="34"
)

echo "=== Generating WireGuard peer configs ==="
echo "VPS Public Key: $VPS_PUBLIC_KEY"
echo "DNS: $DNS (MikroTik kantor)"
echo "Output dir: $OUTDIR"
echo ""

VPS_PEER_CONFIG="$OUTDIR/vps-hub-peers.conf"
echo "# VPS Hub Peer Config - append to /etc/wireguard/wg0.conf" > "$VPS_PEER_CONFIG"
echo "# Generated: $(date)" >> "$VPS_PEER_CONFIG"
echo "# VPS Public Key: $VPS_PUBLIC_KEY" >> "$VPS_PEER_CONFIG"
echo "" >> "$VPS_PEER_CONFIG"

for NAME in "${!STAFF[@]}"; do
    OCTET="${STAFF[$NAME]}"
    USER_IP="10.100.0.$OCTET/32"
    
    PRIV_KEY=$(wg genkey)
    PUB_KEY=$(echo "$PRIV_KEY" | wg pubkey)
    PSK=$(wg genpsk)
    
    USER_CONF="$OUTDIR/${NAME}.conf"
    cat > "$USER_CONF" << CONFEOF
[Interface]
PrivateKey = $PRIV_KEY
Address = $USER_IP
DNS = $DNS

[Peer]
PublicKey = $VPS_PUBLIC_KEY
PresharedKey = $PSK
AllowedIPs = $VPN_NETWORK, 192.168.10.0/24, 192.168.18.0/24
Endpoint = $VPS_ENDPOINT
PersistentKeepalive = 25
CONFEOF
    
    cat >> "$VPS_PEER_CONFIG" << CONFEOF
[Peer]
# $NAME
PublicKey = $PUB_KEY
PresharedKey = $PSK
AllowedIPs = $USER_IP
CONFEOF
    
    echo "✓ $NAME -> $USER_IP"
done

echo ""
echo "=== Generated files in $OUTDIR ==="
ls -la "$OUTDIR"/*.conf

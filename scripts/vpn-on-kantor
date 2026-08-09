#!/bin/bash
# vpn-on-kantor / vpn-on-luar / vpn-off — CMJ WireGuard Pola B (laptop admin)
# Install di laptop (Linux): sudo cp vpn-* /usr/local/bin/ && sudo chmod +x /usr/local/bin/vpn-*
# Config: letakkan admin-kantor.conf & admin-luar.conf di ~/wg/ (bukan /etc/wireguard,
#         supaya tidak bentrok dengan wg0 systemd)
CONF_DIR="$HOME/wg"

cmd_kantor() {
  sudo wg-quick down wg0 2>/dev/null || true
  sudo cp "$CONF_DIR/admin-kantor.conf" /etc/wireguard/wg0.conf
  sudo chmod 600 /etc/wireguard/wg0.conf
  sudo wg-quick up wg0
  echo "VPN ON (mode KANTOR): hanya 10.100.0.0/24 lewat tunnel"
}

cmd_luar() {
  sudo wg-quick down wg0 2>/dev/null || true
  sudo cp "$CONF_DIR/admin-luar.conf" /etc/wireguard/wg0.conf
  sudo chmod 600 /etc/wireguard/wg0.conf
  sudo wg-quick up wg0
  echo "VPN ON (mode LUAR): 10.100.0.0/24 + LAN kantor lewat tunnel"
}

cmd_off() {
  sudo wg-quick down wg0 2>/dev/null || true
  echo "VPN OFF"
}

case "$(basename "$0")" in
  vpn-on-kantor) cmd_kantor ;;
  vpn-on-luar)   cmd_luar ;;
  vpn-off)       cmd_off ;;
  *) echo "Usage: vpn-on-kantor | vpn-on-luar | vpn-off"; exit 1 ;;
esac

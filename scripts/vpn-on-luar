#!/bin/bash
# vpn-on-kantor / vpn-on-luar / vpn-off — CMJ WireGuard Pola B (laptop admin)
# Install di laptop (Linux): sudo cp vpn-* /usr/local/bin/ && sudo chmod +x /usr/local/bin/vpn-*
# Config: taruh admin-kantor.conf & admin-luar.conf DI FOLDER YANG SAMA dengan script ini.
#         (Kalau tidak ada, baru fallback ke ~/wg/ user asli.)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_DIR="$SCRIPT_DIR"

if [ ! -f "$CONF_DIR/admin-kantor.conf" ] || [ ! -f "$CONF_DIR/admin-luar.conf" ]; then
  # fallback: home user asli (sudo mereset $HOME ke /root, pakai SUDO_USER)
  if [ -n "${SUDO_USER:-}" ]; then
    REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
  else
    REAL_HOME="$HOME"
  fi
  CONF_DIR="$REAL_HOME/wg"
fi

# Pastikan config ketemu; kalau tidak, berhenti dengan pesan jelas
# (JANGAN lanjut ke wg-quick dengan wg0.conf lama — mode jadi salah diam-diam)
MISSING=""
[ -f "$CONF_DIR/admin-kantor.conf" ] || MISSING="$MISSING admin-kantor.conf"
[ -f "$CONF_DIR/admin-luar.conf" ]   || MISSING="$MISSING admin-luar.conf"
if [ -n "$MISSING" ]; then
  echo "ERROR: config tidak ditemukan:$MISSING" >&2
  echo "       dicari di: $CONF_DIR (folder script: $SCRIPT_DIR)" >&2
  echo "       Letakkan admin-kantor.conf & admin-luar.conf di folder yang sama" >&2
  echo "       dengan script ini, atau di ~/wg/." >&2
  exit 1
fi

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
  # DNS .lan via tunnel: resolvconf di Ubuntu modern tidak aktif
  # (/etc/resolv.conf dikelola systemd-resolved) -> set via resolvectl
  sudo resolvectl dns wg0 10.100.0.2 2>/dev/null || true
  sudo resolvectl domain wg0 '~lan' 2>/dev/null || true
  echo "VPN ON (mode LUAR): 10.100.0.0/24 + LAN kantor lewat tunnel"
}

cmd_off() {
  sudo wg-quick down wg0 2>/dev/null || true
  sudo resolvectl dns wg0 '' 2>/dev/null || true
  sudo resolvectl domain wg0 '' 2>/dev/null || true
  echo "VPN OFF"
}

case "$(basename "$0")" in
  vpn-on-kantor) cmd_kantor ;;
  vpn-on-luar)   cmd_luar ;;
  vpn-off)       cmd_off ;;
  *) echo "Usage: vpn-on-kantor | vpn-on-luar | vpn-off"; exit 1 ;;
esac

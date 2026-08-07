#!/bin/bash

# Script Cek Jaringan Lengkap - Optimized for WiFi Issues
# Untuk mendiagnosis masalah koneksi WiFi yang sering drop

# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# File log
LOG_DIR="$HOME/network_logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/network_check_$(date +%Y%m%d_%H%M%S).log"

# Interface WiFi dari hasil ip -4 a
WIFI_IFACE="wlp2s0"

# Fungsi untuk menulis ke log dan console
write_log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

# Fungsi header
print_header() {
    echo ""
    write_log "${BLUE}========================================${NC}"
    write_log "${BLUE}   NETWORK DIAGNOSTIC TOOL v2.0${NC}"
    write_log "${BLUE}   Waktu: $(date)${NC}"
    write_log "${BLUE}   Interface: $WIFI_IFACE${NC}"
    write_log "${BLUE}========================================${NC}"
    echo ""
}

# Fungsi cek interface secara detail
check_interfaces() {
    write_log "${CYAN}[*] DETAIL INTERFACE${NC}"
    write_log "  ${BLUE}Semua interface:${NC}"
    
    # Tampilkan semua interface dengan IP
    ip -4 a | grep -E "^[0-9]+:" | while read line; do
        local iface=$(echo "$line" | awk -F': ' '{print $2}')
        local ip_addr=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+' | head -1)
        local state=$(echo "$line" | grep -o "<[^>]*>" | head -1)
        
        if [ -n "$ip_addr" ]; then
            write_log "  - $iface: $ip_addr ($state)"
        else
            write_log "  - $iface: No IP ($state)"
        fi
    done
    
    # Detail khusus untuk wlp2s0
    write_log "\n  ${BLUE}Detail Interface $WIFI_IFACE:${NC}"
    if ip link show "$WIFI_IFACE" &>/dev/null; then
        local mac=$(ip link show "$WIFI_IFACE" | grep -oP '(?<=\s)([0-9a-f]{2}:){5}[0-9a-f]{2}(?=\s)' | head -1)
        local mtu=$(ip link show "$WIFI_IFACE" | grep -oP '(?<=mtu\s)\d+')
        local state=$(ip link show "$WIFI_IFACE" | grep -oP '(?<=state\s)[A-Z]+')
        
        write_log "  - MAC Address: $mac"
        write_log "  - MTU: $mtu"
        write_log "  - State: $state"
        
        # Statistik interface
        local rx_bytes=$(ip -s link show "$WIFI_IFACE" | grep -A1 "RX:" | tail -1 | awk '{print $1}')
        local tx_bytes=$(ip -s link show "$WIFI_IFACE" | grep -A1 "TX:" | tail -1 | awk '{print $1}')
        local rx_packets=$(ip -s link show "$WIFI_IFACE" | grep -A1 "RX:" | tail -1 | awk '{print $2}')
        local tx_packets=$(ip -s link show "$WIFI_IFACE" | grep -A1 "TX:" | tail -1 | awk '{print $2}')
        local rx_errors=$(ip -s link show "$WIFI_IFACE" | grep -A1 "RX:" | tail -1 | awk '{print $3}')
        local tx_errors=$(ip -s link show "$WIFI_IFACE" | grep -A1 "TX:" | tail -1 | awk '{print $3}')
        local rx_dropped=$(ip -s link show "$WIFI_IFACE" | grep -A1 "RX:" | tail -1 | awk '{print $4}')
        local tx_dropped=$(ip -s link show "$WIFI_IFACE" | grep -A1 "TX:" | tail -1 | awk '{print $4}')
        
        write_log "  - RX: $rx_bytes bytes, $rx_packets packets"
        write_log "  - TX: $tx_bytes bytes, $tx_packets packets"
        write_log "  - Errors: RX=$rx_errors, TX=$tx_errors"
        write_log "  - Dropped: RX=$rx_dropped, TX=$tx_dropped"
    else
        write_log "${RED}  ✗ Interface $WIFI_IFACE tidak ditemukan!${NC}"
    fi
    echo ""
}

# Fungsi cek WiFi dengan berbagai metode
check_wifi() {
    write_log "${CYAN}[*] DETAIL WIFI${NC}"
    
    # 1. Cek dengan iwconfig
    if command -v iwconfig &> /dev/null; then
        write_log "  ${BLUE}1. iwconfig:${NC}"
        local wifi_info=$(iwconfig "$WIFI_IFACE" 2>/dev/null)
        
        if [ -n "$wifi_info" ]; then
            # Extract SSID
            local ssid=$(echo "$wifi_info" | grep -o 'ESSID:"[^"]*"' | cut -d'"' -f2)
            [ -z "$ssid" ] && ssid="(tidak terkoneksi)"
            write_log "  - SSID: $ssid"
            
            # Extract Frequency/Channel
            local freq=$(echo "$wifi_info" | grep -o 'Frequency:[0-9.]* [GM]Hz' | cut -d' ' -f2-3)
            [ -n "$freq" ] && write_log "  - Frequency: $freq"
            
            # Extract Access Point MAC
            local ap_mac=$(echo "$wifi_info" | grep -o 'Access Point: [0-9A-F:]*' | cut -d' ' -f3)
            [ -n "$ap_mac" ] && write_log "  - Access Point: $ap_mac"
            
            # Extract Bit Rate
            local bitrate=$(echo "$wifi_info" | grep -o 'Bit Rate=[0-9.]* [GM]b/s' | cut -d'=' -f2)
            [ -n "$bitrate" ] && write_log "  - Bit Rate: $bitrate"
            
            # Extract Signal Level
            local signal=$(echo "$wifi_info" | grep -o 'Signal level=[0-9-]*' | cut -d'=' -f2)
            if [ -n "$signal" ]; then
                write_log "  - Signal Level: $signal dBm"
                # Interpretasi
                if [ "$signal" -ge -50 ]; then
                    write_log "${GREEN}    ✓ Kualitas: Sangat Baik (excellent)${NC}"
                elif [ "$signal" -ge -60 ]; then
                    write_log "${GREEN}    ✓ Kualitas: Baik (good)${NC}"
                elif [ "$signal" -ge -67 ]; then
                    write_log "${YELLOW}    ⚠ Kualitas: Cukup (fair)${NC}"
                elif [ "$signal" -ge -70 ]; then
                    write_log "${YELLOW}    ⚠ Kualitas: Lemah (weak)${NC}"
                elif [ "$signal" -ge -80 ]; then
                    write_log "${RED}    ✗ Kualitas: Sangat Lemah (very weak)${NC}"
                else
                    write_log "${RED}    ✗ Kualitas: Tidak Stabil (no signal)${NC}"
                fi
            fi
            
            # Extract Quality
            local quality=$(echo "$wifi_info" | grep -o 'Quality=[0-9/]*' | cut -d'=' -f2)
            if [ -n "$quality" ]; then
                local current=$(echo "$quality" | cut -d'/' -f1)
                local max=$(echo "$quality" | cut -d'/' -f2)
                local percent=$((current * 100 / max))
                write_log "  - Quality: $quality ($percent%)"
                
                # Buat visual bar
                local bar_length=50
                local filled=$((percent * bar_length / 100))
                local bar=""
                for ((i=0; i<filled; i++)); do bar="$bar#"; done
                for ((i=filled; i<bar_length; i++)); do bar="$bar-"; done
                write_log "  - Signal Bar: [$bar] $percent%"
            fi
            
            # Extract Link Quality
            local link_qual=$(echo "$wifi_info" | grep -o 'Link Quality=[0-9/]*' | cut -d'=' -f2)
            [ -n "$link_qual" ] && write_log "  - Link Quality: $link_qual"
            
            # Check if connected
            if echo "$wifi_info" | grep -q "Not-Associated"; then
                write_log "${RED}  ✗ Status: NOT CONNECTED${NC}"
            else
                write_log "${GREEN}  ✓ Status: CONNECTED${NC}"
            fi
        else
            write_log "${RED}  ✗ Tidak dapat membaca info WiFi${NC}"
        fi
    else
        write_log "${YELLOW}  ! iwconfig tidak tersedia${NC}"
    fi
    
    # 2. Cek dengan iw (jika tersedia)
    if command -v iw &> /dev/null; then
        write_log "\n  ${BLUE}2. iw command:${NC}"
        
        # Cek link
        if iw dev "$WIFI_IFACE" link &>/dev/null; then
            local signal=$(iw dev "$WIFI_IFACE" link | grep signal | awk '{print $2}')
            [ -n "$signal" ] && write_log "  - Signal: $signal dBm"
            
            local tx_rate=$(iw dev "$WIFI_IFACE" link | grep "tx bitrate" | awk '{print $3" "$4}')
            [ -n "$tx_rate" ] && write_log "  - TX Bitrate: $tx_rate"
            
            local rx_rate=$(iw dev "$WIFI_IFACE" link | grep "rx bitrate" | awk '{print $3" "$4}')
            [ -n "$rx_rate" ] && write_log "  - RX Bitrate: $rx_rate"
        fi
        
        # Cek station info
        iw dev "$WIFI_IFACE" station dump 2>/dev/null | grep -E "(signal|tx bitrate|rx bitrate|inactive|packets)" | while read line; do
            write_log "  - $line"
        done
    fi
    
    # 3. Cek dengan nmcli (jika tersedia)
    if command -v nmcli &> /dev/null; then
        write_log "\n  ${BLUE}3. nmcli:${NC}"
        
        local nm_ssid=$(nmcli -t -f GENERAL.CONNECTION device show "$WIFI_IFACE" 2>/dev/null | cut -d: -f2)
        if [ -n "$nm_ssid" ] && [ "$nm_ssid" != "--" ]; then
            write_log "  - Connected to: $nm_ssid"
            
            # Cek signal dari nmcli
            local nm_signal=$(nmcli -f IN-USE,SSID,SIGNAL device wifi list | grep -E "^\*" | awk '{print $NF}')
            if [ -n "$nm_signal" ]; then
                write_log "  - Signal Strength: $nm_signal%"
            fi
        else
            write_log "  - Tidak terkoneksi ke WiFi (menurut nmcli)"
        fi
    fi
    
    echo ""
}

# Fungsi monitor WiFi secara real-time (5 detik)
monitor_wifi_realtime() {
    write_log "${CYAN}[*] MONITOR WIFI REAL-TIME (5 detik)${NC}"
    write_log "  Menganalisa stabilitas signal..."
    
    local samples=5
    local signals=()
    
    for i in $(seq 1 $samples); do
        if command -v iwconfig &> /dev/null; then
            local signal=$(iwconfig "$WIFI_IFACE" 2>/dev/null | grep -o 'Signal level=[0-9-]*' | cut -d'=' -f2)
            if [ -n "$signal" ]; then
                signals+=("$signal")
                write_log "  - Sample $i: ${signal}dBm"
            else
                write_log "  - Sample $i: ${RED}NO SIGNAL${NC}"
                signals+=("0")
            fi
        fi
        sleep 1
    done
    
    # Analisa variasi signal
    if [ ${#signals[@]} -gt 1 ]; then
        local stable=true
        local prev=${signals[0]}
        for s in "${signals[@]:1}"; do
            if [ $((s - prev)) -gt 10 ] || [ $((prev - s)) -gt 10 ]; then
                stable=false
                break
            fi
            prev=$s
        done
        
        if [ "$stable" = true ]; then
            write_log "${GREEN}  ✓ Signal stabil${NC}"
        else
            write_log "${RED}  ✗ Signal tidak stabil (fluktuasi > 10dBm)${NC}"
            write_log "${YELLOW}  Rekomendasi: Pindah lebih dekat ke router atau cek interferensi${NC}"
        fi
    fi
    echo ""
}

# Fungsi cek DNS (diperbaiki)
check_dns() {
    write_log "${CYAN}[*] CEK DNS${NC}"
    
    # Cek file resolv.conf
    write_log "  ${BLUE}1. Konfigurasi DNS:${NC}"
    if [ -f /etc/resolv.conf ]; then
        local dns_servers=$(grep -v "^#" /etc/resolv.conf | grep nameserver | awk '{print $2}')
        if [ -n "$dns_servers" ]; then
            echo "$dns_servers" | while read dns; do
                write_log "  - DNS Server: $dns"
            done
        else
            write_log "${RED}  - Tidak ada DNS server dikonfigurasi!${NC}"
        fi
    else
        write_log "${RED}  - File /etc/resolv.conf tidak ditemukan!${NC}"
    fi
    
    # Test DNS dengan beberapa metode
    write_log "\n  ${BLUE}2. Test Resolusi DNS:${NC}"
    local test_domains=("google.com" "github.com" "mikrotik.com")
    
    for domain in "${test_domains[@]}"; do
        if host "$domain" &>/dev/null; then
            local ip=$(host "$domain" | grep "has address" | head -1 | awk '{print $4}')
            write_log "${GREEN}  ✓ $domain -> $ip${NC}"
        else
            write_log "${RED}  ✗ Gagal resolve $domain${NC}"
        fi
    done
    
    # Test dengan DNS spesifik
    write_log "\n  ${BLUE}3. Test dengan DNS Server Eksternal:${NC}"
    local dns_test=("8.8.8.8" "1.1.1.1")
    for dns in "${dns_test[@]}"; do
        if nslookup google.com "$dns" &>/dev/null; then
            write_log "${GREEN}  ✓ DNS $dns berfungsi${NC}"
        else
            write_log "${RED}  ✗ DNS $dns tidak merespon${NC}"
        fi
    done
    echo ""
}

# Fungsi ping dengan timing detail
check_ping_detailed() {
    local target=$1
    local description=$2
    local count=5
    
    write_log "${CYAN}[*] PING KE $description ($target)${NC}"
    
    local result=$(ping -c $count -W 2 "$target" 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        local loss=$(echo "$result" | grep -oP '\d+(?=% packet loss)')
        local avg=$(echo "$result" | grep -oP '=\s+\S+/\K[\d.]+')
        local min=$(echo "$result" | grep -oP '=\s+\K[\d.]+(?=/)')
        local max=$(echo "$result" | grep -oP '=\s+\S+/\S+/\K[\d.]+(?=/)')
        local mdev=$(echo "$result" | grep -oP '=\s+\S+/\S+/\S+/\K[\d.]+')
        
        if [ "$loss" -eq 0 ]; then
            write_log "${GREEN}  ✓ Success:${NC}"
            write_log "    - Loss: 0%"
            write_log "    - RTT Min/Avg/Max: ${min}/${avg}/${max}ms"
            write_log "    - Mdev: ${mdev}ms"
        else
            write_log "${YELLOW}  ⚠ Partial Loss: ${loss}%${NC}"
            write_log "    - RTT Min/Avg/Max: ${min}/${avg}/${max}ms"
        fi
        
        # Cek duplicate packets
        if echo "$result" | grep -q "DUP!"; then
            local dup=$(echo "$result" | grep -c "DUP!")
            write_log "${RED}  ✗ Detected $dup duplicate packets!${NC}"
            write_log "${YELLOW}    - Mungkin ada network loop atau masalah switch${NC}"
        fi
    else
        write_log "${RED}  ✗ Gagal mencapai $target${NC}"
    fi
    echo ""
}

# Fungsi cek rute
check_routing() {
    write_log "${CYAN}[*] ROUTING${NC}"
    
    # Default gateway
    local default_gw=$(ip route | grep default | awk '{print $3}')
    if [ -n "$default_gw" ]; then
        write_log "  - Default Gateway: $default_gw"
    else
        write_log "${RED}  ✗ Tidak ada default gateway!${NC}"
    fi
    
    # Route ke internet
    write_log "\n  - Route ke 8.8.8.8:"
    ip route get 8.8.8.8 2>/dev/null | while read line; do
        write_log "    $line"
    done
    
    # ARP table
    write_log "\n  - ARP Table:"
    arp -n 2>/dev/null | head -5 | while read line; do
        write_log "    $line"
    done
    echo ""
}

# Fungsi rekomendasi
show_recommendations() {
    write_log "${CYAN}[*] REKOMENDASI & SOLUSI${NC}"
    
    local issues=0
    
    # Cek WiFi signal
    if command -v iwconfig &> /dev/null; then
        local signal=$(iwconfig "$WIFI_IFACE" 2>/dev/null | grep -o 'Signal level=[0-9-]*' | cut -d'=' -f2)
        if [ -n "$signal" ] && [ "$signal" -lt -70 ]; then
            issues=$((issues+1))
            write_log "${RED}  $issues. MASALAH: WiFi Signal Lemah (${signal}dBm)${NC}"
            write_log "     SOLUSI:"
            write_log "     - Dekatkan perangkat ke router WiFi"
            write_log "     - Pindah ke channel WiFi yang tidak crowded (gunakan 1, 6, atau 11)"
            write_log "     - Cek interferensi dari microwave, Bluetooth, atau perangkat 2.4GHz lain"
            write_log "     - Pertimbangkan menggunakan kabel Ethernet untuk koneksi stabil"
            write_log "     - Restart router WiFi"
        fi
    fi
    
    # Cek DNS
    if ! host google.com &>/dev/null; then
        issues=$((issues+1))
        write_log "${RED}  $issues. MASALAH: DNS Resolution Failure${NC}"
        write_log "     SOLUSI:"
        write_log "     - Tambahkan DNS server di /etc/resolv.conf:"
        write_log "       echo 'nameserver 8.8.8.8' | sudo tee -a /etc/resolv.conf"
        write_log "       echo 'nameserver 1.1.1.1' | sudo tee -a /etc/resolv.conf"
        write_log "     - Atau install/restart network-manager:"
        write_log "       sudo systemctl restart NetworkManager"
        write_log "     - Cek konfigurasi DHCP client"
    fi
    
    # Cek duplicate packets
    if ping -c 3 8.8.8.8 2>&1 | grep -q "DUP!"; then
        issues=$((issues+1))
        write_log "${YELLOW}  $issues. MASALAH: Duplicate Packets Terdeteksi${NC}"
        write_log "     SOLUSI:"
        write_log "     - Cek kemungkinan network loop di switch/router"
        write_log "     - Restart switch dan router"
        write_log "     - Cek kabel network yang mungkin bermasalah"
    fi
    
    # Cek packet loss ke WAN
    if ping -c 3 192.168.18.1 2>&1 | grep -qE "[1-9][0-9]?% packet loss"; then
        issues=$((issues+1))
        write_log "${YELLOW}  $issues. MASALAH: Packet Loss ke WAN Gateway${NC}"
        write_log "     SOLUSI:"
        write_log "     - Cek koneksi kabel dari router ke modem"
        write_log "     - Restart modem/router"
        write_log "     - Hubungi ISP jika berulang"
    fi
    
    if [ $issues -eq 0 ]; then
        write_log "${GREEN}  ✓ Tidak ada masalah terdeteksi!${NC}"
        write_log "  Network connection seems healthy."
    fi
    
    echo ""
    write_log "${BLUE}Log lengkap disimpan di: $LOG_FILE${NC}"
}

# MAIN FUNCTION
main() {
    print_header
    check_interfaces
    check_wifi
    monitor_wifi_realtime
    check_ping_detailed "192.168.10.2" "TP-Link Gateway"
    check_ping_detailed "192.168.18.12" "Mikrotik"
    check_ping_detailed "192.168.18.1" "WAN Gateway"
    check_ping_detailed "1.1.1.1" "Cloudflare DNS"
    check_ping_detailed "8.8.8.8" "Google DNS"
    check_dns
    check_routing
    show_recommendations
    
    write_log "\n${BLUE}========================================${NC}"
    write_log "${GREEN}Diagnostik selesai pada $(date)${NC}"
    write_log "${BLUE}========================================${NC}"
}

# Jalankan
main
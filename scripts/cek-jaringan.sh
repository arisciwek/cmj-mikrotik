#!/bin/bash

# Script Cek Jaringan Lengkap
# Untuk mendiagnosis masalah koneksi dan DNS

# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# File log
LOG_FILE="/tmp/network_check_$(date +%Y%m%d_%H%M%S).log"

# Fungsi untuk menulis ke log dan console
write_log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

# Fungsi header
print_header() {
    echo ""
    write_log "${BLUE}========================================${NC}"
    write_log "${BLUE}   NETWORK DIAGNOSTIC TOOL v1.0${NC}"
    write_log "${BLUE}   Waktu: $(date)${NC}"
    write_log "${BLUE}========================================${NC}"
    echo ""
}

# Fungsi cek koneksi dengan ping
check_ping() {
    local target=$1
    local description=$2
    local count=5
    
    write_log "${YELLOW}[*] Mengecek koneksi ke $description ($target)${NC}"
    
    if ping -c $count -W 2 "$target" > /tmp/ping_result 2>&1; then
        local loss=$(grep -oP '\d+(?=% packet loss)' /tmp/ping_result)
        local avg=$(grep -oP '=\s+\S+/\K[\d.]+' /tmp/ping_result)
        
        if [ "$loss" -eq 0 ]; then
            write_log "${GREEN}[✓] Koneksi ke $description OK (RTT: ${avg}ms, Loss: 0%)${NC}"
        else
            write_log "${YELLOW}[!] Koneksi ke $description: Loss ${loss}% (RTT: ${avg}ms)${NC}"
        fi
    else
        write_log "${RED}[✗] GAGAL terhubung ke $description${NC}"
    fi
    echo ""
}

# Fungsi cek DNS
check_dns() {
    write_log "${YELLOW}[*] Memeriksa DNS Resolution${NC}"
    
    # Cek file resolv.conf
    if [ -f /etc/resolv.conf ]; then
        write_log "  - Isi /etc/resolv.conf:"
        cat /etc/resolv.conf | grep -v "^#" | while read line; do
            write_log "    $line"
        done
    else
        write_log "${RED}  - File /etc/resolv.conf tidak ditemukan!${NC}"
    fi
    
    # Test DNS dengan beberapa server
    local dns_servers=("8.8.8.8" "1.1.1.1" "192.168.18.1")
    local test_domain="google.com"
    
    for dns in "${dns_servers[@]}"; do
        write_log "  - Mencoba resolve $test_domain menggunakan DNS $dns"
        if nslookup "$test_domain" "$dns" > /tmp/dns_test 2>&1; then
            if grep -q "Address:" /tmp/dns_test; then
                local ip=$(grep "Address:" /tmp/dns_test | tail -1 | awk '{print $2}')
                write_log "${GREEN}    ✓ Berhasil: $test_domain -> $ip${NC}"
            else
                write_log "${RED}    ✗ Gagal resolve${NC}"
            fi
        else
            write_log "${RED}    ✗ DNS Server $dns tidak merespon${NC}"
        fi
    done
    
    # Cek DNS dengan dig (jika tersedia)
    if command -v dig &> /dev/null; then
        write_log "  - Informasi DNS dengan dig:"
        dig google.com +short | head -1 | while read ip; do
            if [ -n "$ip" ]; then
                write_log "${GREEN}    ✓ google.com -> $ip${NC}"
            fi
        done
    fi
    echo ""
}

# Fungsi cek WiFi
check_wifi() {
    write_log "${YELLOW}[*] Memeriksa Status WiFi${NC}"
    
    # Cek interface wireless
    local wifi_iface=$(ip link show | grep -E "^[0-9]+: wl" | awk -F': ' '{print $2}')
    
    if [ -n "$wifi_iface" ]; then
        write_log "  - Interface WiFi: $wifi_iface"
        
        # Cek signal strength dengan iwconfig
        if command -v iwconfig &> /dev/null; then
            local signal=$(iwconfig "$wifi_iface" 2>/dev/null | grep -o 'Signal level=[0-9-]*' | cut -d'=' -f2)
            local quality=$(iwconfig "$wifi_iface" 2>/dev/null | grep -o 'Quality=[0-9/]*' | cut -d'=' -f2)
            
            if [ -n "$signal" ]; then
                write_log "  - Signal Level: $signal dBm"
                # Interpretasi signal strength
                if [ "$signal" -ge -50 ]; then
                    write_log "${GREEN}  - Kualitas Signal: Sangat Baik${NC}"
                elif [ "$signal" -ge -60 ]; then
                    write_log "${GREEN}  - Kualitas Signal: Baik${NC}"
                elif [ "$signal" -ge -70 ]; then
                    write_log "${YELLOW}  - Kualitas Signal: Cukup${NC}"
                elif [ "$signal" -ge -80 ]; then
                    write_log "${RED}  - Kualitas Signal: Lemah${NC}"
                else
                    write_log "${RED}  - Kualitas Signal: Sangat Lemah${NC}"
                fi
            fi
            
            if [ -n "$quality" ]; then
                write_log "  - Quality: $quality"
            fi
        fi
        
        # Cek dengan nmcli jika tersedia
        if command -v nmcli &> /dev/null; then
            local ssid=$(nmcli -t -f GENERAL.CONNECTION device show "$wifi_iface" 2>/dev/null | cut -d: -f2)
            if [ -n "$ssid" ]; then
                write_log "  - SSID: $ssid"
            fi
            
            # Cek signal dengan nmcli
            local nm_signal=$(nmcli device wifi list | grep -A1 "$ssid" | tail -1 | awk '{print $NF}')
            if [ -n "$nm_signal" ]; then
                write_log "  - Signal (nmcli): $nm_signal%"
            fi
        fi
        
        # Cek packet error rate
        local errors=$(ip -s link show "$wifi_iface" | grep -A1 "RX:" | tail -1 | awk '{print $3}')
        local drops=$(ip -s link show "$wifi_iface" | grep -A1 "RX:" | tail -1 | awk '{print $5}')
        write_log "  - RX Errors: $errors, Drops: $drops"
        
    else
        write_log "${RED}  - Tidak ada interface WiFi ditemukan!${NC}"
    fi
    echo ""
}

# Fungsi cek routing
check_routing() {
    write_log "${YELLOW}[*] Memeriksa Routing Table${NC}"
    
    # Tampilkan default gateway
    local default_gw=$(ip route | grep default | awk '{print $3}')
    if [ -n "$default_gw" ]; then
        write_log "  - Default Gateway: $default_gw"
    else
        write_log "${RED}  - Tidak ada default gateway!${NC}"
    fi
    
    # Tampilkan routing table
    write_log "  - Routing Table:"
    ip route | grep -v "proto kernel" | while read line; do
        write_log "    $line"
    done
    
    # Cek ARP table
    write_log "  - ARP Table untuk gateway:"
    arp -n | grep -E "(192.168.10.2|192.168.18.12|192.168.18.1)" | while read line; do
        write_log "    $line"
    done
    echo ""
}

# Fungsi cek koneksi Mikrotik
check_mikrotik() {
    write_log "${YELLOW}[*] Memeriksa Koneksi ke Mikrotik (192.168.18.12)${NC}"
    
    # Cek ping
    if ping -c 3 -W 2 192.168.18.12 > /tmp/mikrotik_ping 2>&1; then
        local avg=$(grep -oP '=\s+\S+/\K[\d.]+' /tmp/mikrotik_ping)
        write_log "${GREEN}  ✓ Ping ke Mikrotik OK (RTT: ${avg}ms)${NC}"
    else
        write_log "${RED}  ✗ Gagal ping ke Mikrotik${NC}"
    fi
    
    # Cek SSH (jika ada)
    if command -v nc &> /dev/null; then
        timeout 3 nc -zv 192.168.18.12 22 2>&1 | while read line; do
            if echo "$line" | grep -q "succeeded"; then
                write_log "${GREEN}  ✓ SSH port terbuka${NC}"
            else
                write_log "${YELLOW}  ! SSH port tidak respon${NC}"
            fi
        done
    fi
    echo ""
}

# Fungsi untuk merekomendasikan solusi
show_recommendations() {
    write_log "${YELLOW}[*] Rekomendasi dan Solusi:${NC}"
    
    # Cek DNS lagi untuk rekomendasi
    if ! nslookup google.com 8.8.8.8 &> /dev/null; then
        write_log "${RED}  1. Masalah DNS:${NC}"
        write_log "     - Periksa file /etc/resolv.conf"
        write_log "     - Coba tambahkan 'nameserver 8.8.8.8' dan 'nameserver 1.1.1.1'"
        write_log "     - Atau periksa konfigurasi NetworkManager"
    fi
    
    # Cek WiFi signal
    local wifi_iface=$(ip link show | grep -E "^[0-9]+: wl" | awk -F': ' '{print $2}')
    if [ -n "$wifi_iface" ]; then
        if command -v iwconfig &> /dev/null; then
            local signal=$(iwconfig "$wifi_iface" 2>/dev/null | grep -o 'Signal level=[0-9-]*' | cut -d'=' -f2)
            if [ -n "$signal" ] && [ "$signal" -lt -70 ]; then
                write_log "${RED}  2. WiFi Signal Lemah:${NC}"
                write_log "     - Dekatkan perangkat ke router"
                write_log "     - Pindah ke channel WiFi yang lebih baik"
                write_log "     - Pertimbangkan menggunakan kabel Ethernet"
                write_log "     - Cek interferensi dari perangkat lain"
            fi
        fi
    fi
    
    # Cek duplicate packets
    if ping -c 3 8.8.8.8 2>&1 | grep -q "DUP!"; then
        write_log "${YELLOW}  3. Duplicate Packet terdeteksi:${NC}"
        write_log "     - Mungkin ada masalah di switch/router"
        write_log "     - Cek kemungkinan network loop"
        write_log "     - Restart router/gateway"
    fi
    
    # Cek packet loss ke WAN
    if ping -c 3 -W 2 192.168.18.1 2>&1 | grep -qE "[1-9][0-9]?% packet loss"; then
        write_log "${YELLOW}  4. Packet Loss ke WAN Gateway:${NC}"
        write_log "     - Cek kabel/interface ke WAN"
        write_log "     - Cek load pada gateway"
        write_log "     - Mungkin ada masalah di sisi ISP"
    fi
    
    echo ""
    write_log "${GREEN}Untuk informasi lebih detail, cek log di: $LOG_FILE${NC}"
}

# Fungsi utama
main() {
    print_header
    
    # Informasi sistem
    write_log "${BLUE}[*] Informasi Sistem:${NC}"
    write_log "  - Hostname: $(hostname)"
    write_log "  - Kernel: $(uname -r)"
    write_log "  - OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    echo ""
    
    # Cek interface IP
    write_log "${BLUE}[*] IP Address:${NC}"
    ip -4 addr show | grep -E "^[0-9]+:" | while read line; do
        local iface=$(echo "$line" | awk -F': ' '{print $2}')
        local ip_addr=$(ip -4 addr show "$iface" | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+' | head -1)
        if [ -n "$ip_addr" ]; then
            write_log "  - $iface: $ip_addr"
        fi
    done
    echo ""
    
    # Jalankan semua pengecekan
    check_ping "192.168.10.2" "TP-Link Gateway (192.168.10.2)"
    check_ping "192.168.18.12" "Mikrotik (192.168.18.12)"
    check_ping "192.168.18.1" "WAN Gateway (192.168.18.1)"
    check_ping "1.1.1.1" "Cloudflare DNS"
    check_ping "8.8.8.8" "Google DNS"
    
    check_wifi
    check_routing
    check_dns
    check_mikrotik
    
    # Tes kecepatan sederhana
    write_log "${YELLOW}[*] Tes Kecepatan Sederhana (download 1MB dari google)${NC}"
    timeout 10 curl -o /dev/null -s -w "  - Download speed: %{speed_download} bytes/sec\n" http://speedtest.tele2.net/1MB.zip 2>/dev/null || write_log "${RED}  ✗ Gagal melakukan tes kecepatan${NC}"
    echo ""
    
    show_recommendations
    
    write_log "\n${BLUE}========================================${NC}"
    write_log "${GREEN}Diagnostik selesai pada $(date)${NC}"
    write_log "${BLUE}========================================${NC}"
}

# Jalankan main
main

# Simpan log
echo ""
echo "Log disimpan di: $LOG_FILE"
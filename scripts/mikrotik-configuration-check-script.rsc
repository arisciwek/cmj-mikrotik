# CMJ - Configuration Verification Script
# File: mikrotik-configuration-check-script.rsc
# Description: Final verification of all MikroTik CHR configurations
# Source: Copied from 10-first-check.rsc (originally 99-final-check.rsc)
# Created: 2026-08-07
# Revision: 1.0
# Author: CMJ Network Team
#
# Usage: /import mikrotik-configuration-check-script.rsc
# ============================================================

# ============================================================
# SECTION 1: HEADER & INITIALIZATION
# ============================================================
:log info "=========================================="
:log info "CMJ: FINAL CONFIGURATION VERIFICATION"
:log info "CMJ: Started at $[/system clock get time]"
:log info "=========================================="

# ============================================================
# SECTION 2: INTERFACE VERIFICATION
# Memastikan semua interface fisik terdeteksi dan up
# ============================================================
:log info "CMJ: [1/10] Checking Interface Status"
/interface print where name~"ether"
:log info "CMJ: WAN = ether1, LAN = ether2 (should be running)"

# ============================================================
# SECTION 3: IP ADDRESS VERIFICATION
# Memastikan IP address terpasang dengan benar
# ============================================================
:log info "CMJ: [2/10] Checking IP Address Configuration"
/ip address print
:log info "CMJ: Expected: 192.168.18.12/24 on ether1 (WAN)"
:log info "CMJ: Expected: 192.168.10.1/24 on ether2 (LAN)"

# ============================================================
# SECTION 4: ROUTE VERIFICATION
# Memastikan default gateway dan routing berfungsi
# ============================================================
:log info "CMJ: [3/10] Checking Route Configuration"
/ip route print
:log info "CMJ: Default gateway should point to 192.168.18.1"

# ============================================================
# SECTION 5: FIREWALL FILTER VERIFICATION
# Memastikan semua firewall rules aktif
# ============================================================
:log info "CMJ: [4/10] Checking Firewall Filter Rules"
/ip firewall filter print count
:log info "CMJ: Total rules count: $[/ip firewall filter print count]"
:log info "CMJ: Should have at least:"
:log info "CMJ:   - Fasttrack for established connections"
:log info "CMJ:   - Accept from TRUSTED networks (192.168.10.0/24 & 192.168.18.0/24)"
:log info "CMJ:   - Drop all other input/forward"

# ============================================================
# SECTION 6: NAT VERIFICATION
# Memastikan masquerade berfungsi untuk akses internet
# ============================================================
:log info "CMJ: [5/10] Checking NAT Rules"
/ip firewall nat print count
:log info "CMJ: Masquerade should exist for WAN interface"

# ============================================================
# SECTION 7: DHCP SERVER VERIFICATION
# Memastikan DHCP server siap memberikan IP ke client
# ============================================================
:log info "CMJ: [6/10] Checking DHCP Server Status"
/ip dhcp-server print
/ip pool print
:log info "CMJ: DHCP Pool: 192.168.10.100-192.168.10.199"
:log info "CMJ: DHCP Server should be running on ether2"

# ============================================================
# SECTION 8: DNS VERIFICATION
# Memastikan DNS static dan forwarding bekerja
# ============================================================
:log info "CMJ: [7/10] Checking DNS Configuration"
/ip dns print
:log info "CMJ: Static DNS entries:"
/ip dns static print where name~".office.cmj.local"
:log info "CMJ: DNS servers: 8.8.8.8, 1.1.1.1 (or your ISP DNS)"

# ============================================================
# SECTION 9: SERVICE VERIFICATION
# Memastikan hanya service yang aman yang aktif
# ============================================================
:log info "CMJ: [8/10] Checking Active Services"
/ip service print where disabled=no
:log info "CMJ: Allowed services: winbox, ssh, www-ssl only"
:log info "CMJ: Services should only accessible from TRUSTED networks"

# ============================================================
# SECTION 10: SECURITY VERIFICATION (CRITICAL)
# Memastikan akun admin tidak aktif dan user baru ada
# ============================================================
:log info "CMJ: [9/10] Checking User Security"
/user print
:log info "CMJ: CRITICAL: admin should be disabled"
:log info "CMJ: CRITICAL: admin-baru should be enabled"
:log info "CMJ: CRITICAL: Check if BLACKLIST address-list exists"
/ip firewall address-list print where list=BLACKLIST

# ============================================================
# SECTION 11: CONNECTIVITY TEST
# Verifikasi akses internet dari router
# ============================================================
:log info "CMJ: [10/10] Testing Internet Connectivity"
/ping 1.1.1.1 count=3
/ping 8.8.8.8 count=3
:log info "CMJ: If ping fails, check WAN gateway and NAT"

# ============================================================
# SECTION 12: SUMMARY REPORT
# Tampilkan ringkasan konfigurasi yang sudah diterapkan
# ============================================================
:log info "=========================================="
:log info "CMJ: CONFIGURATION SUMMARY"
:log info "=========================================="
:log info "CMJ: LAN IP: 192.168.10.1/24"
:log info "CMJ: WAN IP: 192.168.18.12/24"
:log info "CMJ: DHCP Pool: 192.168.10.100 - 192.168.10.199"
:log info "CMJ: Trusted Networks: 192.168.10.0/24, 192.168.18.0/24"
:log info "CMJ: VPN Network: 10.100.0.0/24"
:log info "CMJ: Active Services: winbox, ssh, www-ssl"
:log info "CMJ: admin user: DISABLED"
:log info "CMJ: admin-baru user: ENABLED"
:log info "CMJ: Anti-Brute Force: ACTIVE (BLACKLIST)"
:log info "=========================================="
:log info "CMJ: STATUS: VERIFICATION COMPLETE"
:log info "CMJ: Completed at $[/system clock get time]"
:log info "=========================================="
:log info "CMJ: NEXT STEPS:"
:log info "CMJ: 1. Login with admin-baru (NOT admin)"
:log info "CMJ: 2. Test client DHCP from LAN"
:log info "CMJ: 3. Test internet access from LAN client"
:log info "CMJ: 4. Monitor /log for any warnings"
:log info "=========================================="
# CMJ - Configuration Verification Script
# File: mikrotik-configuration-check-script.rsc
# Description: Final verification of all MikroTik CHR configurations
# Source: Copied from 10-first-check.rsc (originally 99-final-check.rsc)
# Created: 2026-08-07
# Revision: 1.0
# Author: CMJ Network Team
#
# Usage: /import mikrotik-configuration-check-script.rsc

:log info "=========================================="
:log info "CMJ: FINAL CONFIGURATION VERIFICATION"
:log info "=========================================="

:log info "CMJ: Interface Status"
/interface print where name~"ether"

:log info "CMJ: IP Address Configuration"
/ip address print

:log info "CMJ: Route Configuration"
/ip route print

:log info "CMJ: Firewall Filter Rules"
/ip firewall filter print count

:log info "CMJ: NAT Rules"
/ip firewall nat print count

:log info "CMJ: DHCP Server Status"
/ip dhcp-server print
/ip pool print

:log info "CMJ: DNS Configuration"
/ip dns print

:log info "CMJ: Service Status"
/ip service print where disabled=no

:log info "=========================================="
:log info "CMJ: Configuration Complete!"
:log info "CMJ: LAN IP: 192.168.10.1"
:log info "CMJ: WAN IP: 192.168.18.12"
:log info "CMJ: DHCP Pool: 192.168.10.100-199"
:log info "=========================================="

:log info "CMJ: Testing connectivity..."
/ping 1.1.1.1 count=3

:log info "CMJ: Final verification completed"
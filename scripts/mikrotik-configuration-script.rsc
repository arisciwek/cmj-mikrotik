# CMJ - Main Configuration Script
# File: mikrotik-configuration-script.rsc
# Description: Base MikroTik CHR configuration (interface lists, IP pool, DHCP, DNS, firewall, NAT, services)
# Source: Copied from 10-base-config.rsc (originally config-tambahan.rsc)
# Created: 2026-08-07
# Revision: 1.0
# Author: CMJ Network Team
#
# Network Topology:
#   Huawei EG8041V5 (192.168.18.1) -> MikroTik CHR (ether1=WAN 192.168.18.12, ether2=LAN 192.168.10.1)
#   -> TP-Link AP mode (192.168.10.2) -> CMJ-Office WiFi
#   Dual SSID: Huawei admin-only, TP-Link users
#
# Prerequisites: Base IP/route already configured on CHR
# Usage: /import mikrotik-configuration-script.rsc

/interface list
add name=WAN
add name=LAN

/interface list member
add interface=ether1 list=WAN
add interface=ether2 list=LAN

/ip pool
add name=dhcp-pool ranges=192.168.10.100-192.168.10.199

/ip dhcp-server
add address-pool=dhcp-pool interface=ether2 lease-time=1d name=dhcp-server

/ip dhcp-server network
add address=192.168.10.0/24 dns-server=192.168.10.1 gateway=192.168.10.1

/ip dns static
add address=192.168.10.1 name=router.office.cmj.local type=A
add address=192.168.10.1 name=gateway.office.cmj.local type=A
add address=192.168.10.2 name=ap.office.cmj.local type=A

/ip firewall address-list
add address=192.168.18.0/24 list=ADMIN-NET
add address=192.168.10.0/24 list=LAN-NET
add address=10.100.0.0/24 list=VPN-NET
add address=192.168.18.0/24 list=TRUSTED
add address=192.168.10.0/24 list=TRUSTED

/ip firewall filter
add action=fasttrack-connection chain=forward connection-state=established,related
add action=accept chain=input connection-state=established,related
add action=drop chain=input connection-state=invalid
add action=accept chain=input protocol=icmp src-address-list=TRUSTED
add action=accept chain=input dst-port=22,8291,443 protocol=tcp src-address-list=TRUSTED
add action=accept chain=input dst-port=53 protocol=udp src-address=192.168.10.0/24
add action=accept chain=input dst-port=53 protocol=tcp src-address=192.168.10.0/24
add action=accept chain=input dst-port=123 protocol=udp src-address=192.168.10.0/24
add action=drop chain=input
add action=accept chain=forward connection-state=established,related
add action=drop chain=forward connection-state=invalid
add action=accept chain=forward src-address=192.168.10.0/24 dst-address=10.100.0.0/24
add action=accept chain=forward src-address=10.100.0.0/24 dst-address=192.168.10.0/24
add action=accept chain=forward src-address=192.168.10.0/24 out-interface-list=WAN
add action=drop chain=forward
add action=accept chain=output connection-state=established,related
add action=accept chain=output protocol=icmp
add action=accept chain=output dst-port=53 protocol=udp
add action=accept chain=output dst-port=123 protocol=udp
add action=drop chain=output

/ip firewall nat
add action=masquerade chain=srcnat out-interface-list=WAN src-address=192.168.10.0/24
add action=masquerade chain=srcnat out-interface-list=WAN src-address=10.100.0.0/24

/ip service
set ftp disabled=yes
set ssh address=192.168.10.0/24,192.168.18.0/24
set telnet disabled=yes
set www disabled=yes
set www-ssl address=192.168.10.0/24,192.168.18.0/24 disabled=no
set winbox address=192.168.10.0/24,192.168.18.0/24
set api disabled=yes
set api-ssl disabled=yes

/system logging
add action=disk topics=error
add action=disk topics=warning
add action=disk topics=info

/system scheduler
add interval=1d name=daily-backup on-event="/system backup save name=\"backup-\$[/system clock get date]\"" policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon start-date=2026-08-06 start-time=17:17:32
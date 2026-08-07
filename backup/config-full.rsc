# 2026-08-07 12:36:44 by RouterOS 7.23.1
# software id = 01MT-APIL
#
/interface ethernet
set [ find default-name=ether1 ] disable-running-check=no
set [ find default-name=ether2 ] disable-running-check=no
/interface list
add name=WAN
add name=LAN
/interface wireless security-profiles
set [ find default=yes ] supplicant-identity=MikroTik
/iot wiliot servers
set *1 address=mqtt.us-east-2.prod.wiliot.cloud name="Wiliot US East"
/ip dhcp-server option
add code=119 name=domain-search value="'office.cmj.local'"
add code=15 name=domain-name value="'office.cmj.local'"
/ip pool
add name=dhcp-pool ranges=192.168.10.100-192.168.10.199
/ip dhcp-server
add address-pool=dhcp-pool interface=ether2 lease-time=1d name=dhcp-server
/queue type
add kind=pcq name=pcq-download
add kind=pcq name=pcq-upload
/interface list member
add interface=ether1 list=WAN
add interface=ether2 list=LAN
/ip address
add address=192.168.18.12/24 comment=WAN interface=ether1 network=\
    192.168.18.0
add address=192.168.10.1/24 comment=LAN interface=ether2 network=192.168.10.0
/ip dhcp-server network
add address=192.168.10.0/24 dns-server=192.168.10.1 gateway=192.168.10.1
/ip dns
set allow-remote-requests=yes cache-size=4096KiB max-udp-packet-size=512 \
    servers=1.1.1.1,8.8.8.8
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
add address=1.1.1.1 list=PUBLIC-DNS
add address=8.8.8.8 list=PUBLIC-DNS
/ip firewall filter
add action=fasttrack-connection chain=forward connection-state=\
    established,related
add action=accept chain=input connection-state=established,related
add action=drop chain=input connection-state=invalid
add action=accept chain=input protocol=icmp src-address-list=TRUSTED
add action=accept chain=input dst-port=22,8291,443 protocol=tcp \
    src-address-list=TRUSTED
add action=accept chain=input dst-port=53 protocol=udp src-address=\
    192.168.10.0/24
add action=accept chain=input dst-port=53 protocol=tcp src-address=\
    192.168.10.0/24
add action=accept chain=input dst-port=123 protocol=udp src-address=\
    192.168.10.0/24
add action=drop chain=input comment=CMJ-DROP-PORT-SCAN protocol=tcp psd=\
    21,3s,3,1
add action=drop chain=input log=yes log-prefix="DROP-IN: "
add action=accept chain=forward connection-state=established,related
add action=drop chain=forward connection-state=invalid
add action=accept chain=forward dst-address=10.100.0.0/24 src-address=\
    192.168.10.0/24
add action=accept chain=forward dst-address=192.168.10.0/24 src-address=\
    10.100.0.0/24
add action=log chain=forward log-prefix="CLIENT-FWD: " src-address=\
    192.168.10.101
add action=accept chain=forward out-interface-list=WAN src-address=\
    192.168.10.0/24
add action=drop chain=forward
add action=accept chain=output connection-state=established,related
add action=accept chain=output protocol=icmp
add action=accept chain=output dst-port=53 protocol=udp
add action=accept chain=output dst-port=123 protocol=udp
add action=accept chain=output comment=CMJ-allow-tcp-dns-out dst-port=53 \
    protocol=tcp
add action=drop chain=output
/ip firewall nat
add action=masquerade chain=srcnat out-interface-list=WAN src-address=\
    192.168.10.0/24
add action=masquerade chain=srcnat out-interface-list=WAN src-address=\
    10.100.0.0/24
add action=masquerade chain=srcnat comment=CMJ-masq-all-out-wan \
    out-interface-list=WAN
add action=masquerade chain=srcnat comment=CMJ-masq-router-wan \
    out-interface-list=WAN src-address=192.168.18.12
add action=masquerade chain=srcnat comment=CMJ-masq-router-lan \
    out-interface-list=WAN src-address=192.168.10.1
/ip route
add dst-address=0.0.0.0/0 gateway=192.168.18.1
/ip service
set ftp disabled=yes
set ssh address=192.168.10.0/24,192.168.18.0/24
set telnet disabled=yes
set www disabled=yes
set www-ssl address=192.168.10.0/24,192.168.18.0/24 disabled=no
set winbox address=192.168.10.0/24,192.168.18.0/24
set api disabled=yes
set api-ssl disabled=yes
/system gps
set set-system-time=yes
/system logging
add action=disk topics=error
add action=disk topics=warning
add action=disk topics=info
/system scheduler
add interval=1d name=daily-backup on-event=\
    "/system backup save name=\"backup-\$[/system clock get date]\"" policy=\
    ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon \
    start-date=2026-08-06 start-time=17:17:32
/tool graphing interface
add interface=ether1
add interface=ether2

# MikroTik DNS static entry for zimbra.lan

# 1. Backup current config (important before any change)
/system backup save name=pre-zimbra-dns

# 2. Add DNS static record
/ip dns static add name=zimbra.lan address=192.168.18.19 ttl=1h type=A comment="zimbra server"

# 3. Ensure router acts as DNS server for the LAN
/ip dns set servers=192.168.18.12 allow-remote-requests=yes

# 4. DHCP options to push internal domain .lan to clients
/ip dhcp-server option set [find code=119] value="'lan'"   # domain-search
/ip dhcp-server option set [find code=15]  value="'lan'"   # domain-name
/ip dhcp-server network set [find] dns-server=192.168.18.12

# 5. (Optional) allow ICMP ping to internal hosts (usually already allowed)
/ip firewall filter add chain=input protocol=icmp action=accept comment="allow ping to internal hosts"

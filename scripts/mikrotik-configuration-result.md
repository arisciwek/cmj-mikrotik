# CMJ - Configuration Verification Result
# File: mikrotik-configuration-result.md
# Description: Terminal output from final configuration verification
# Source: Copied from 10-first-check.md (terminal dump of 99-final-check.rsc execution)
# Created: 2026-08-07
# Revision: 1.0
# Author: CMJ Network Team
#
# This file contains the raw terminal output for reference/debugging.

[admin@x86] > /import 99-final-check.rsc
Flags: R - RUNNING
Columns: NAME, TYPE, ACTUAL-MTU, MAC-ADDRESS
#   NAME    TYPE   ACTUAL-MTU  MAC-ADDRESS
0 R ether1  ether        1500  BC:24:11:62:D5:22
1 R ether2  ether        1500  BC:24:11:F4:9E:3F
Columns: ADDRESS, NETWORK, INTERFACE, VRF
# ADDRESS           NETWORK       INTERFACE  VRF
;;; WAN
0 192.168.18.12/24  192.168.18.0  ether1     main
;;; LAN
1 192.168.10.1/24   192.168.10.0  ether2     main
Flags: D - DYNAMIC; A - ACTIVE; c - CONNECT, s - STATIC
Columns: DST-ADDRESS, GATEWAY, ROUTING-TABLE, DISTANCE
#     DST-ADDRESS      GATEWAY       ROUTING-TABLE  DISTANCE
0  As 0.0.0.0/0        192.168.18.1  main                  1
  DAc 192.168.10.0/24  ether2        main                  0
  DAc 192.168.18.0/24  ether1        main                  0
23
2
Columns: NAME, INTERFACE, ADDRESS-POOL, LEASE-TIME
# NAME         INTERFACE  ADDRESS-POOL  LEASE-TIME
0 dhcp-server  ether2     dhcp-pool     1d
Columns: NAME, RANGES, TOTAL, USED, AVAILABLE
#  NAME       RANGES                         TOTAL  USED  AVAILABLE
0  dhcp-pool  192.168.10.100-192.168.10.199    100     1         99
                      servers: 1.1.1.1
                               8.8.8.8
              dynamic-servers:
               use-doh-server: https://cloudflare-dns.com/dns-query
              verify-doh-cert: yes
   doh-max-server-connections: 5
   doh-max-concurrent-queries: 50
                  doh-timeout: 5s
        allow-remote-requests: yes
          max-udp-packet-size: 4096
         query-server-timeout: 2s
          query-total-timeout: 10s
       max-concurrent-queries: 100
  max-concurrent-tcp-sessions: 20
                   cache-size: 4096KiB
                cache-max-ttl: 1w
      address-list-extra-time: 0s
                          vrf: main
           mdns-repeat-ifaces:
                   cache-used: 52KiB
Flags: D - DYNAMIC; c - CONNECTION
Columns: NAME, PORT, PROTO, ADDRESS, CERTIFICATE, VRF, MAX-SSESSIONS, LOCAL, REMOTE
 #    NAME           PORT  PROTO  ADDRESS          CERTIFICATE  VRF   MAX-SESSIONS  LOCAL          REMOTE
 0    ssh              22  tcp    192.168.10.0/24               main            20
                                  192.168.18.0/24
 1 Dc ssh              22  tcp                                                      192.168.18.12  192.168.18.50:34272
 2 D  resolver         53  tcp
 3 D  resolver         53  udp
 4 D  dhcp             67  udp
 5    reverse-proxy   443  tcp                     none         main            20
 6    www-ssl         443  tcp    192.168.10.0/24  none         main            20
                                  192.168.18.0/24
 7 D  btest          2000  tcp
 8 D  loader         3986  tcp
 9 D  discover       5678  udp
 10    winbox         8291  tcp    192.168.10.0/24               main            20
                                  192.168.18.0/24
 11 Dc winbox         8291  tcp                                                      192.168.18.12  192.168.18.50:57414
  SEQ HOST                                     SIZE TTL TIME       STATUS
    0 1.1.1.1                                    56  55 21ms768us
    1 1.1.1.1                                    56  55 18ms931us
    2 1.1.1.1                                    56  55 18ms511us
    sent=3 received=3 packet-loss=0% min-rtt=18ms511us avg-rtt=19ms736us max-rtt=21ms768us
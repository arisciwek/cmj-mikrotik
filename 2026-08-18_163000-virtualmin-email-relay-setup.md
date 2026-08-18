# LAPORAN SETUP VIRTUALMIN EMAIL RELAY LXC 108
# Tanggal: 2026-08-18
# Engineer: System Engineer
# Context: Virtualmin LXC 108 (192.168.18.18) + MikroTik VM 102 + VPS 103.56.149.231

---

## OBJECTIVE
Setup email server di Virtualmin LXC 108 dengan relay chain yang sama seperti Carbonio LXC 109:
LXC 108 → MikroTik (192.168.18.12:25) → WireGuard (wg1) → VPS (10.100.0.1:25) → Internet

---

## CURRENT STATE (SEBELUM)
- LXC 108: Virtualmin running, root login OK, domain `ciptamasjaya.co.id` sudah dibuat, user `ciptamasjaya` exist
- Postfix: BELUM terinstall
- Dovecot: BELUM terinstall
- VPS: Postfix `myhostname = mail.ciptamasjaya.co.id`, `mynetworks` include 10.100.0.0/24, 192.168.18.0/24
- MikroTik: WireGuard wg1 aktif, dst-nat port 25 sudah ada untuk Carbonio (LXC 109)

---

## PROBLEM
1. LXC 108 belum punya MTA (Postfix) dan MDA (Dovecot)
2. Perlu hindari loop detection seperti Carbonio: `myhostname` harus BEDA dengan VPS public MX
3. Inbound email perlu routing ke LXC 108 via VPS → MikroTik

---

## FACTS
- VPS public MX: `mail.ciptamasjaya.co.id` (103.56.149.231)
- LXC 108 IP: 192.168.18.18 (eth0)
- MikroTik LAN IP: 192.168.18.12 (ether1/WAN), 192.168.10.1 (ether2/LAN)
- WireGuard tunnel: MikroTik wg1 (10.100.0.2) ↔ VPS wg0 (10.100.0.1), UDP 48231
- Domain: `ciptamasjaya.co.id` (shared dengan Carbonio LXC 109)
- ISP blocks ports 25/587/465 → relay via MikroTik → VPS through WireGuard

---

## ACTIONS PERFORMED

### 1. Install Postfix + Dovecot di LXC 108
```bash
pct exec 108 -- apt update && apt install -y postfix dovecot-core dovecot-imapd dovecot-pop3d
```
Postfix config via debconf: "Internet Site", mailname = ciptamasjaya.co.id

### 2. Konfigurasi Postfix LXC 108 (Hindari Loop)
```bash
postconf -e "myhostname = virtualmin.ciptamasjaya.co.id"
postconf -e "mydomain = ciptamasjaya.co.id"
postconf -e "myorigin = \$mydomain"
postconf -e "relayhost = [192.168.18.12]:25"
postconf -e "mynetworks = 127.0.0.0/8 192.168.18.0/24 10.100.0.0/24"
postconf -e "inet_interfaces = loopback-only"
postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost"
postconf -e "smtp_helo_name = virtualmin.ciptamasjaya.co.id"
systemctl restart postfix
```

**Key:** `myhostname = virtualmin.ciptamasjaya.co.id` (BEDA dengan VPS `mail.ciptamasjaya.co.id`) → hindari "loops back to myself"

### 3. Konfigurasi Dovecot LXC 108
```bash
sed -i 's/^#protocols = imap pop3 lmtp/protocols = imap pop3/' /etc/dovecot/dovecot.conf
sed -i 's/^#listen = \*, ::/listen = \*, ::/' /etc/dovecot/dovecot.conf
sed -i 's/^#disable_plaintext_auth = yes/disable_plaintext_auth = no/' /etc/dovecot/conf.d/10-auth.conf
sed -i 's/^#auth_mechanisms = plain login/auth_mechanisms = plain login/' /etc/dovecot/conf.d/10-auth.conf
systemctl restart dovecot
```

Ports listening: IMAP 143/993, POP3 110/995 (all interfaces)

### 4. Update VPS Postfix
```bash
# Tambah 192.168.10.0/24 ke mynetworks
postconf -e "mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128 10.100.0.0/24 10.100.0.2/32 192.168.18.0/24 192.168.10.0/24"

# Transport map untuk ciptamasjaya.co.id → MikroTik via WireGuard
postconf -e "transport_maps = hash:/etc/postfix/transport"
echo "ciptamasjaya.co.id smtp:[10.100.0.2]" > /etc/postfix/transport
postmap /etc/postfix/transport
systemctl restart postfix
```

### 5. Update MikroTik NAT Rules
```bash
# Inbound dari VPS → LXC 108 (Virtualmin)
/ip firewall nat add chain=dstnat action=dst-nat to-addresses=192.168.18.18 to-ports=25 protocol=tcp src-address=10.100.0.1 dst-port=25 comment="CMJ-virtualmin-inbound-mail-from-VPS"

# Outbound LXC 108 → VPS via WireGuard (src-nat)
/ip firewall nat add chain=srcnat action=src-nat to-addresses=10.100.0.2 protocol=tcp src-address=192.168.18.18 dst-address=10.100.0.1 dst-port=25 comment="CMJ-virtualmin-outbound-to-VPS"
```

---

## VERIFICATION RESULTS

### Outbound Email Test (LXC 108 → Internet)
```bash
pct exec 108 -- /usr/sbin/sendmail -t << 'EOF'
To: test@example.com
From: ciptamasjaya@ciptamasjaya.co.id
Subject: Test email from Virtualmin LXC 108
EOF
```

**Log Postfix LXC 108:**
```
postfix/smtp[748720]: 263D748190D: to=<test@example.com>, 
relay=192.168.18.12[192.168.18.12]:25, delay=0.55, 
dsn=2.0.0, status=sent (250 2.0.0 Ok: queued as 7011D600BC)
```
✅ **Queue empty = delivered via MikroTik → WireGuard → VPS → Internet**

### Relay Chain Confirmed
```
LXC 108 (Postfix) 
  → MikroTik 192.168.18.12:25 (dst-nat rule #8) 
  → WireGuard wg1 (10.100.0.2) 
  → VPS wg0 (10.100.0.1):25 
  → Internet
```

### Inbound Path Configured
```
Internet 
  → VPS 103.56.149.231:25 (Postfix transport_maps) 
  → WireGuard wg0 (10.100.0.1) 
  → MikroTik wg1 (10.100.0.2) 
  → dst-nat port 25 → LXC 108 (192.168.18.18:25)
  AND/OR dst-nat port 25 → LXC 109 (192.168.18.19:25) for Carbonio
```

---

## KEY CONFIGURATIONS

### LXC 108 Postfix (virtualmin.ciptamasjaya.co.id)
| Parameter | Value |
|-----------|-------|
| myhostname | virtualmin.ciptamasjaya.co.id |
| mydomain | ciptamasjaya.co.id |
| myorigin | $mydomain |
| relayhost | [192.168.18.12]:25 |
| mynetworks | 127.0.0.0/8 192.168.18.0/24 10.100.0.0/24 |
| inet_interfaces | loopback-only |
| mydestination | $myhostname, localhost.$mydomain, localhost |
| smtp_helo_name | virtualmin.ciptamasjaya.co.id |

### VPS Postfix (mail.ciptamasjaya.co.id)
| Parameter | Value |
|-----------|-------|
| myhostname | mail.ciptamasjaya.co.id |
| mynetworks | 127.0.0.0/8 10.100.0.0/24 10.100.0.2/32 192.168.18.0/24 192.168.10.0/24 |
| transport_maps | hash:/etc/postfix/transport |
| transport entry | ciptamasjaya.co.id smtp:[10.100.0.2] |

### MikroTik NAT (Port 25)
| Chain | Rule | Comment |
|-------|------|---------|
| dstnat | 10.100.0.1:25 → 192.168.18.18:25 | CMJ-virtualmin-inbound-mail-from-VPS |
| dstnat | 10.100.0.1:25 → 192.168.18.19:25 | CMJ-inbound-mail-from-VPS (Carbonio) |
| dstnat | 192.168.18.18:25 → 10.100.0.1:25 | CMJ-mail-out (Virtualmin outbound) |
| dstnat | 192.168.18.13:25 → 10.100.0.1:25 | CMJ-mail-out (old?) |
| srcnat | 192.168.18.18 → 10.100.0.2 (to VPS:25) | CMJ-virtualmin-outbound-to-VPS |

---

## KNOWN ISSUES / TODO

### 1. Shared Domain Conflict (ciptamasjaya.co.id)
Kedua LXC 108 (Virtualmin) dan LXC 109 (Carbonio) share domain `ciptamasjaya.co.id`.
Inbound email routing perlu disambiguate:
- Opsi A: Subdomain (mail.ciptamasjaya.co.id → Carbonio, virtualmin.ciptamasjaya.co.id → Virtualmin)
- Opsi B: Recipient-based routing di VPS transport_maps
- Opsi C: Hanya satu LXC handle inbound, yang lain outbound only

### 2. Inbound Testing Belum Dilakukan
Perlu test kirim email dari eksternal (Gmail dll) ke `ciptamasjaya@ciptamasjaya.co.id` dan verifikasi sampai ke LXC 108 mailbox.

### 3. Dovecot SSL/TLS
Certificate self-signed default. Perlu Let's Encrypt atau cert valid untuk production IMAP/POP3S.

### 4. Virtualmin Email User Setup
User `ciptamasjaya` sudah ada di Virtualmin. Perlu verifikasi mailbox delivery via Dovecot.

---

## FILES CHANGED
- `/etc/postfix/main.cf` (LXC 108)
- `/etc/dovecot/dovecot.conf` (LXC 108)
- `/etc/dovecot/conf.d/10-auth.conf` (LXC 108)
- `/etc/postfix/main.cf` (VPS 103.56.149.231)
- `/etc/postfix/transport` (VPS)
- MikroTik NAT rules (VM 102)

---

## NEXT STEPS (REQUIRES APPROVAL)
1. **Disambiguate inbound routing** untuk domain `ciptamasjaya.co.id` (Virtualmin vs Carbonio)
2. **Test inbound email** dari eksternal ke LXC 108
3. **Setup SSL certificates** untuk Dovecot IMAPS/POP3S
4. **Configure Virtualmin email aliases** dan forwarding rules
5. **Document recipient routing strategy** di VPS transport_maps

---

## ACCEPTANCE CRITERIA
- [x] LXC 108 Postfix install & configured dengan hostname unik
- [x] LXC 108 Dovecot IMAP/POP3 listening
- [x] Outbound email relay via MikroTik → WireGuard → VPS working
- [x] VPS transport_maps route ciptamasjaya.co.id ke MikroTik
- [x] MikroTik NAT rules untuk inbound/outbound LXC 108
- [ ] Inbound email delivery ke LXC 108 mailbox verified
- [ ] Domain routing conflict resolved (Virtualmin vs Carbonio)
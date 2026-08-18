# LAPORAN PERBAIKAN CARBONIO EMAIL RELAY & ZX AUTH
# Tanggal: 2026-08-18
# Engineer: System Engineer
# Context: Carbonio CE LXC 109 (mail.ciptamasjaya.co.id) + MikroTik VM 102 + VPS 103.56.149.231

============================================================
RINGKASAN PERUBAHAN YANG DILAKUKAN HARI INI
============================================================

## 1. EMAIL RELAY CHAIN - FIXED ✅

### Masalah Awal:
- Carbonio (LXC 109) tidak bisa kirim email via UI (SendMsgRequest 422/504)
- Log Postfix: "mail for [192.168.18.12]:25 loops back to myself"
- Relayhost mengarah ke SSH tunnel port 1998/12525, bukan ke MikroTik

### Root Cause:
- `zimbraMtaRelayHost: [127.0.0.1]:12525` → SSH tunnel, bukan mail relay
- `zimbraSmtpHostname: 127.78.0.7` → internal envoy IP
- `myhostname = mail.ciptamasjaya.co.id` sama dengan VPS public MX → loop detection

### Perbaikan Dilakukan:

#### LXC 109 - Postfix & Zimbra Config:
```bash
# relayhost ke MikroTik LAN IP
/opt/zextras/common/sbin/postconf -e 'relayhost = [192.168.18.12]:25'

# zimbraMtaRelayHost ke MikroTik
/opt/zextras/bin/zmprov mcf zimbraMtaRelayHost '[192.168.18.12]:25'

# zimbraSmtpHostname ke MikroTik LAN IP
/opt/zextras/bin/zmprov mcf zimbraSmtpHostname '192.168.18.12'

# myhostname beda dengan VPS public MX (hindari loop)
/opt/zextras/common/sbin/postconf -e 'myhostname = mail-internal.ciptamasjaya.co.id'
/opt/zextras/common/sbin/postconf -e 'smtp_helo_name = mail-internal.ciptamasjaya.co.id'

# restart carbonio-postfix
systemctl restart carbonio-postfix
```

#### Hasil Verifikasi:
```bash
# Postfix queue empty = email delivered
/opt/zextras/common/sbin/postqueue -p
# Output: Mail queue is empty

# Log menunjukkan relay berhasil:
# postfix/smtp[1317557]: AA141C9DAC: to=<test@example.com>, 
# relay=192.168.18.12[192.168.18.12]:25, delay=0.27, 
# dsn=2.0.0, status=sent (250 2.0.0 Ok: queued as D4E7A60280)
```

### Arsitektur Relay Final:
```
Carbonio LXC 109 (192.168.18.19) 
  → Postfix relayhost = [192.168.18.12]:25 (MikroTik LAN)
  → MikroTik dst-nat: 192.168.18.13:25 → 10.100.0.1:25 (VPS via WireGuard wg1)
  → MikroTik src-nat: masquerade 192.168.18.0/24 out-interface=wg1
  → VPS Postfix mynetworks = 10.100.0.0/24 + 10.100.0.2/32 (NO LXC LAN IP)
  → VPS delivers to internet
```

---

## 2. MIKROTIK DNS RESOLVER - FIXED ✅

### Masalah:
- User LAN 192.168.10.0/24 tidak bisa resolve internet
- Harus manual set DNS 8.8.8.8/1.1.1.1 di client

### Root Cause:
- MikroTik `/ip dns` servers = `192.168.18.12` (WAN IP sendiri)
- Tidak ada upstream resolver valid

### Perbaikan:
```bash
# Set upstream DNS ke Cloudflare + Google
/ip dns set servers=1.1.1.1,8.8.8.8
```

### Verifikasi:
```bash
/ip dns print
# servers: 1.1.1.1, 8.8.8.8
/resolve google.com
# Berhasil resolve
```

---

## 3. MIKROTIK STATIC DNS .lan - SUDAH ADA ✅

### Status:
13 entry static DNS sudah terkonfigurasi (termasuk zimbra.lan → 192.168.18.19)

```bash
/ip dns static print
# zimbra.lan → 192.168.18.19 (TTL 1h)
# nextcloud.lan → 192.168.18.10
# samba.lan → 192.168.18.11
# mikrotik.lan → 192.168.18.12
# dll.
```

---

## 4. ZX AUTH ENDPOINT - MASIH BERMASALAH ❌

### Gejala:
- Browser console: `GET https://mail.ciptamasjaya.co.id/zx/login/v3/auth/config 502 (Bad Gateway)`
- `POST https://mail.ciptamasjaya.co.id/service/soap/SendMsgRequest 504 (Gateway Time-out)`
- `POST https://mail.ciptamasjaya.co.id/service/soap/GetShareInfoRequest 502 (Bad Gateway)`

### Analisis:
- Nginx upstream `zx` → `zimbra.lan:8742` (port ZX HTTP)
- Nginx upstream `zx_ssl` → `zimbra.lan:8743` (port ZX HTTPS)
- Port 8742/8743 **TIDAK LISTEN** di LXC 109

```bash
ss -tlnp | grep -E '8742|8743'
# Output: (kosong)
```

### Service Terkait:
- `carbonio-message-dispatcher-auth` running di 127.78.0.23:10000
- `carbonio-message-dispatcher-auth-sidecar` (envoy) di 127.78.0.1:20008
- `carbonio-ws-collaboration` crash: RabbitMQ auth failure
  - `ACCESS_REFUSED - Login was refused using authentication mechanism PLAIN`

### Next Step Required:
1. Cari service ZX (zimbra extension) yang seharusnya listen di 8742/8743
2. Perbaiki RabbitMQ auth untuk carbonio-ws-collaboration
3. Restart carbonio-appserver (mailboxd) untuk clear internal state

---

## 5. CARBONIO-WS-COLLABORATION - CRASH ❌

### Error:
```
com.rabbitmq.client.AuthenticationFailureException: 
ACCESS_REFUSED - Login was refused using authentication mechanism PLAIN
```

### Status Service:
- `carbonio-ws-collaboration.service`: activating (auto-restart) → exit-code
- `carbonio-ws-collaboration-sidecar.service`: active
- `carbonio-ws-collaboration-db-sidecar.service`: active

### Next Step:
Perbaiki RabbitMQ credentials di config Carbonio collaboration.

---

## FILE KONFIGURASI YANG BERUBAH HARI INI

### LXC 109:
- `/opt/zextras/common/conf/main.cf` (via postconf) - relayhost, myhostname, smtp_helo_name
- Zimbra LDAP config (via zmprov) - zimbraMtaRelayHost, zimbraSmtpHostname

### MikroTik (VM 102):
- `/ip dns` - servers=1.1.1.1,8.8.8.8

---

## VERIFIKASI AKHIR

### ✅ Berhasil:
1. Email relay chain: Carbonio → MikroTik → WireGuard → VPS → Internet
2. DNS resolver MikroTik: upstream 1.1.1.1, 8.8.8.8
3. Static DNS .lan: 13 entries sudah benar
4. Test email via sendmail: queue empty = delivered

### ❌ Belum Selesai:
1. ZX auth endpoint (port 8742/8743 tidak listen)
2. carbonio-ws-collaboration crash (RabbitMQ auth)
3. SendMsgRequest via UI Carbonio (504 Gateway Time-out)

---

## NEXT ACTION PLAN

1. **Investigasi ZX service**: Cari component yang seharusnya bind port 8742/8743
2. **Perbaiki RabbitMQ**: Cek credentials di `/etc/carbonio/message-dispatcher/` atau Consul
3. **Restart carbonio-appserver**: Clear mailboxd internal state
4. **Test UI Carbonio**: Login & kirim email via web client

---

Penulis: System Engineer
Tanggal: 2026-08-18
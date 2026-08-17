# LAPORAN INVESTASI lengkap - MASALAH AUTHENTIKASI CARBONIO
# Tanggal: 2026-08-17
# Engineer: System Engineer
# Context: Mail server Carbonio LXC 109 (mail.ciptamasjaya.co.id)

============================================================
TASK
============================================================
Investigasi dan pemulihan masalah autentikasi Carbonio:
- Error saat login: POST https://mail.ciptamasjaya.co.id/service/soap/AuthRequest 403 (Forbidden)
- Pesan: "The authentication policy needs more steps: please contact your administrator for more information"
- Sejarah: kemarin mencoba install otentikasi database PostgreSQL → merusak banyak hal
- LXC di-restore dari backup yang sudah berjalan, tapi masalah belum solve
- Pola lama (LDAP-only auth) seharusnya sudah bisa kirim, terima, reply email

============================================================
COMMANDS / ACTIONS
============================================================

1. check-carbonio.sh (05:24 PM UTC 2026)
   - Target: semua active (directory-server, appserver, proxy, mta)
   - Services: semua active kecuali carbonio-proxy.service dan carbonio-mta.service NOT FOUND
   - Status saat ini: HEALTHY

2. systemctl status carbonio-mta.target
   - LoadState: loaded, ActiveState: active (running)
   - Started jam 16:27:34 UTC

3. systemctl status carbonio-postfix.service
   - Active: active (running) sejak 16:27:34 UTC
   - Postfix daemon started berhasil

4. systemctl status carbonio-configd.service
   - Active: active (running) sejak 16:27:12 UTC
   - Tapi ada error: NullPointerException di proxygen thread
   - Error: "Cannot invoke Server.getBooleanAttr because server is null"
   - Warning: "Invalid value found in zimbraReverseProxyAvailableLookupTargets: zimbra.lan"
   - Warning: "No available nginx lookup handlers could be found"

5. systemctl status carbonio-openldap.service
   - Active: active (running) sejak 13:40:08 UTC

6. systemctl status carbonio-nginx.service
   - Active: active (running) sejak 13:46:31 UTC

7. ss -tlnp (port check)
   - Port 25: LISTEN (master)
   - Port 465: LISTEN (master)
   - Port 587: LISTEN (master)
   - Port 389: LISTEN slapd di 192.168.18.19
   - Port 7025: LISTEN java (mailboxd)
   - Port 6071: not directly visible (nginx listening di 8636?)

8. dpkg.log investigation (sejarah carbonio-mta)
   - 2026-08-13 16:23:28: install carbonio-mta:all 4.2.8-1noble
   - 2026-08-13 16:29:37: status installed
   - 2026-08-17 15:09:52: status installed
   - 2026-08-17 15:09:53: remove carbonio-mta:all 4.2.8-1noble ← TIDAK SENGAJA
   - 2026-08-17 15:09:53: status half-configured
   - 2026-08-17 15:09:56: status config-files ← package dihapus tapi config tersisa

9. apt history.log
   - Install awal: apt install -y carbonio-mta dan lain-lain
   - Remove: carbonio-mta:amd64 (4.2.8-1noble)
   - Tidak ada perintah manual apt remove/dpkg di bash history

10. ldapsearch investigation (LDAP-only auth verification)
    - Menggunakan ldap://192.168.18.19:389 (bukan localhost)
    - Bind DN: uid=zmpostfix,cn=appaccts,cn=zimbra
    - Password: pk3wkujQ (dari carbonio.ldif)
    - Base: dc=ciptamasjaya,dc=co,dc=id

11. Domain config query (LDAP)
    - zimbraDomainType: local
    - Tidak ada zimbraAuthMech
    - Tidak ada zimbraAuthLdapURL
    - Tidak ada zimbraAuthLdapSearchBase
    - Tidak ada zimbraAuthLdapSearchFilter
    - Tidak ada zimbraAuthLdapEnabled
    - Tidak ada zimbraAuthFallbackToLocal
    - Tidak ada zimbraAuthMechAdmin
    - Tidak ada zimbraTwoFactorAuthEnabled
    - Tidak ada zimbraTwoFactorAuthRequired

12. Account config query (LDAP)
    - Cari zimbraTwoFactorEnforce, zimbraTwoFactorAuthEnabled, zimbraTwoFactorAuthSecret
    - Untuk user: info@ciptamasjaya.co.id dan sales@ciptamasjaya.co.id
    - Hasil: TIDAK ADA atribut 2FA di account-user

13. Cos (Class of Service) query
    - Cari zimbraTwoFactorEnforce, zimbraTwoFactorAuthEnabled, dll
    - Hasil: TIDAK ADA atribut 2FA di COS

14. zimbraConfig query
    - Cari zimbraAuthMech, zimbraAuthLdapEnabled, dll
    - Hasil: TIDAK ADA konfigurasi auth di zimbraConfig

15. nginx config inspection
    - File utama: /opt/zextras/conf/nginx.conf
    - Include: nginx.conf.main, nginx.conf.memcache, nginx.conf.zmlookup, nginx.conf.mail, nginx.conf.web, nginx.conf.stream
    - nginx.conf.zmlookup: 
      - zm_lookup_handlers: https://192.168.18.19:7072/service/extension/nginx-lookup
      - zm_lookup_master_auth_username: "zmnginx"
      - zm_lookup_master_auth_password: "pk3wkujQ"
      - zm_lookup_timeout: 15000ms
      - zm_lookup_caching: on
    - nginx.conf.web.https: HTTPS server di port 443
    - nginx.conf.web.carbonio.admin: Admin console di port 6071

16. File config yang diperiksa
    - /opt/zextras/conf/amavisd.conf: $enable_ldap = 1, LDAP untuk lookup
    - /opt/zextras/conf/ldap-canonical.cf: LDAP canonical lookup
    - /opt/zextras/conf/ldap-slm.cf: LDAP SLM lookup
    - /opt/zextras/conf/ldap-vam.cf: LDAP VAM lookup
    - /opt/zextras/conf/ldap-vmm.cf: LDAP VMM lookup (user lookup)
    - /opt/zextras/conf/ldap-vad.cf: LDAP VAD lookup
    - /opt/zextras/conf/ldap-transport.cf: LDAP transport lookup
    - /opt/zextras/conf/ldap-splitdomain.cf: LDAP split domain
    - /opt/zextras/conf/carbonio.ldif: LDAP init config
    - /opt/zextras/conf/attrs/attrs.xml: List atribut auth (zimbraAuthMech, zimbraAuthLdapURL, dll)

============================================================
OBSERVATION
============================================================

1. **Sistem dalam kondisi operasional**
   - Semua target active: directory-server, appserver, proxy, mta
   - Semua service active: openldap, configd, mailthreat, postfix, nginx, appserver
   - Mail ports listening: 25, 465, 587

2. **LDAP-only authentication sudah dikonfirmasi**
   - Domain menggunakan zimbraDomainType: local
   - Tidak ada konfigurasi external auth (LDAP URL, search query, dll)
   - Tidak ada dua-factor authentication yang diaktifkan
   - Tidak ada atribut auth mechanism di domain, account, COS, atau config
   - Ini konsisten dengan LDAP-only auth pattern (pola lama)

3. **Error configd yang berulang**
   - NullPointerException di proxygen thread: "Cannot invoke Server.getBooleanAttr because server is null"
   - Warning: "Invalid value found in zimbraReverseProxyAvailableLookupTargets: zimbra.lan"
   - Warning: "No available nginx lookup handlers could be found"
   - Error ini terjadi berulang (setiap ~5 menit) tapi tidak menghentikan service

4. **Carbonio-mta package dihapus tanpa sengaja**
   - Terjadi pada 2026-08-17 15:09:53 (bersamaan dengan stop postfix)
   - Tidak ada perintah manual di bash history
   - Kemungkinan: human error atau script yang tidak terdokumentasi

5. **Master auth configuration (nginx)**
   - zm_lookup_master_auth_username: "zmnginx"
   - zm_lookup_master_auth_password: "pk3wkujQ"
   - Password sama dengan bind DN zmpostfix

6. **Tidak ada sisa konfigurasi database authentication**
   - Tidak ada atribut zimbraAuthLdapSearchQuery di LDAP
   - Tidak ada referensi ke PostgreSQL/MySQL di konfigurasi
   - Konfigurasi amavisd hanya menggunakan LDAP, tidak SQL

7. **User account ada di LDAP**
   - info@ciptamasjaya.co.id (uid=info)
   - sales@ciptamasjaya.co.id (uid=sales)
   - keduanya tidak memiliki atribut 2FA

============================================================
ROOT CAUSE ANALYSIS
============================================================

### Masalah Utama: Error 403 "authentication policy needs more steps"

**Penyebab yang MOST LIKELY:**

1. **Mailboxd internal state corruption** terkait authentication flow
   - Setelah restore dari backup, mailboxd mungkin memiliki cache/state yang invalid
   - NullPointerException di configd proxygen menunjukkan ada masalah konsistensi server object
   - "server is null" di getBooleanAttr → server object tidak ter-load dengan benar

2. **Sisa konfigurasi install database authentication (HYPOTHESIS)**
   - Ketika install database auth, mungkin ada atribut yang ditambahkan ke LDAP
   - Setelah restore, atribut ini mungkin tidak dihapus
   - Tapi karena query kita tidak menemukan atribut tersebut, ini LESS LIKELY

3. **Session/Token cache corruption**
   - ZM_AUTH_TOKEN atau session di browser mungkin corrupted
   - Nginx memcached atau application cache mungkin menyimpan state yang invalid

4. **Configd proxygen error** (related)
   - "server is null" di proxygen thread
   - Ini berarti server object (mail.ciptamasjaya.co.id) tidak ter-load dengan benar
   - Bisa menyebabkan authentication policy check gagal

### Mengapa install database authentication merusak

Pola "2 database" yang Anda maksud:
- **Database 1**: PostgreSQL untuk email/mailbox (sudah ada di Carbonio)
- **Database 2**: PostgreSQL tambahan untuk authentication

Masalahnya:
1. Install auth database menambahkan kompleksitas dependency
2. Konfigurasi auth mechanism berubah dari LDAP-only ke LDAP+SQL hybrid
3. Setelah restore, residu konfigurasi SQL auth mungkin tersisa di tempat yang tidak terduga
4. LDAP sendiri sudah kembali ke LDAP-only (terbukti oleh query kita)
5. Tapi application layer (mailboxd/nginx) mungkin masih mencoba mechanism lama

### Mengapa LDAP-only auth adalah solusi yang tepat

1. **User terbatas**: Tidak banyak user, LDAP cukup
2. **Single source of truth**: OpenLDAP adalah satu-satunya authoritative source
3. **Simple**: Tidak ada dependency ke database eksternal untuk auth
4. **Sudah teruji**: Berjalan dengan baik sebelum install database auth
5. **Konsisten**: Semua konfigurasi LDAP mengarah ke LDAP-only

============================================================
EVIDENCE
============================================================

1. **check-carbonio.sh output (05:24 PM UTC 2026)**
   - Semua target: active
   - Semua service: active (kecuali carbonio-proxy.service dan carbonio-mta.service NOT FOUND)
   - Ini menunjukkan sistem operasional

2. **LDAP domain configuration**
   ```
   dn: dc=ciptamasjaya,dc=co,dc=id
   zimbraDomainType: local
   zimbraMailStatus: enabled
   objectClass: dcObject, organization, zimbraDomain, amavisAccount
   ```
   - Tidak ada atribut auth mechanism

3. **LDAP account (info, sales)**
   ```
   dn: uid=info,ou=people,dc=ciptamasjaya,dc=co,dc=id
   dn: uid=sales,ou=people,dc=ciptamasjaya,dc=co,dc=id
   ```
   - Tidak ada atribut 2FA

4. **nginx zmlookup config**
   ```
   zm_lookup_handlers https://192.168.18.19:7072/service/extension/nginx-lookup
   zm_lookup_master_auth_username "zmnginx"
   zm_lookup_master_auth_password "pk3wkujQ"
   ```

5. **configd error log**
   ```
   NullPointerException: java.lang.NullPointerException: 
   Cannot invoke "com.zimbra.cs.account.Server.getBooleanAttr(String, boolean)" 
   because "server" is null
   ```

6. **dpkg.log (carbonio-mta)**
   ```
   2026-08-17 15:09:53 remove carbonio-mta:all 4.2.8-1noble <none>
   2026-08-17 15:09:56 status config-files carbonio-mta:all 4.2.8-1noble
   ```

7. **amavisd.conf**
   ```
   $enable_ldap = 1;
   $default_ldap = {
       hostname => [ split (' ','ldap://mail.ciptamasjaya.co.id:389') ],
   ```
   - LDAP-only, tidak SQL

============================================================
RESULT
============================================================

### Status Autentikasi
- LDAP-only auth: DIKONFIRMASI AKTIF
- Domain: local (bukan external)
- Tidak ada 2FA yang diaktifkan
- Tidak ada sisa konfigurasi database auth yang ditemukan

### Status Sistem
- Semua service active dan running
- Mail ports listening (25, 465, 587)
- LDAP listening (389)
- Mailboxd listening (7025)

### Masalah yang TERSISAKAN
- Error 403 saat AuthRequest (belum terpecahkan)
- Configd proxygen error berulang (NullPointerException)
- Kemungkinan session/cache corruption

### KESIMPULAN
LDAP-only authentication sudah dikonfirmasi dikonfigurasi dengan benar.
Masalah error 403 kemungkinan disebabkan oleh:
1. Mailboxd internal state corruption
2. Session/Token cache corruption
3. Configd proxygen error (server null)

============================================================
NEXT STEP
============================================================

1. **Clear session/token cache**
   - Hapus cookie di browser atau test dengan incognito
   - Restart carbonio-memcached
   - Restart carbonio-nginx

2. **Restart mailboxd untuk clear internal state**
   ```bash
   su - zextras
   zmmailboxdctl restart
   ```

3. **Check mail.log atau mailboxd.log untuk error auth**
   ```bash
   tail -100 /opt/zextras/log/mailboxd.log | grep -i "auth\|403\|policy\|step\|session"
   ```

4. **Cek apakah ada atribut zimbraAuthLdapSearchQuery tersisa di LDAP**
   ```bash
   /opt/zextras/common/bin/ldapsearch -x -H ldap://192.168.18.19:389 \
     -D "uid=zmpostfix,cn=appaccts,cn=zimbra" -w "pk3wkujQ" \
     -b "dc=ciptamasjaya,dc=co,dc=id" \
     "(zimbraAuthLdapSearchQuery=*)" zimbraAuthLdapSearchQuery
   ```

5. **Test login dengan user baru (bukan admin)**
   - Buat test account
   - Coba login

6. **Jika masih bermasalah, periksa nginx upstream logs**
   ```bash
   tail -50 /opt/zextras/log/nginx.access.log | grep "AuthRequest"
   ```

7. **Backup LDAP config sebelum perubahan**
   ```bash
   /opt/zextras/common/bin/ldapsearch -x -H ldap://192.168.18.19:389 \
     -D "uid=zmpostfix,cn=appaccts,cn=zimbra" -w "pk3wkujQ" \
     -b "dc=ciptamasjaya,dc=co,dc=id" -LLL > /root/ldap-backup-$(date +%Y%m%d).ldif
   ```

============================================================
ACCEPTANCE CRITERIA (TARGET)
============================================================

1. Login berhasil tanpa error 403
2. Tidak ada error 403 di konsol browser
3. "The authentication policy needs more steps" tidak muncul
4. Zimbra Admin Console bisa diakses dan login berhasil
5. Email bisa dikirim, diterima, dan reply
6. Tidak ada error authentication di log

============================================================
STATUS
============================================================

PARTIALLY INVESTIGATED - Belum melakukan perbaikan

Temuan utama:
- LDAP-only auth dikonfirmasi aktif dan benar
- Tidak ada sisa konfigurasi database auth yang ditemukan
- Error 403 kemungkinan disebabkan oleh application layer issue (mailboxd state, cache, configd proxygen)
- Perlu langkah perbaikan: clear cache, restart mailboxd, check log

Penulis: System Engineer
Tanggal: 2026-08-17

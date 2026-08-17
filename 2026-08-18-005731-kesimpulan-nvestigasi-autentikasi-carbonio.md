Kesimpulan Investigasi Autentikasi Carbonio

Berdasarkan investigasi yang dilakukan, berikut temuan dan kesimpulan:



1. Konfirmasi: Pola LDAP-only auth sudah aktif

Evidence:
- zimbraDomainType: local — domain menggunakan authentication local, bukan external
- Tidak ada atribut zimbraAuthMech, zimbraAuthLdapURL, zimbraAuthLdapSearchBase di domain — menggunakan mechanism default
- Tidak ada zimbraTwoFactorAuthRequired: TRUE atau konfigurasi 2FA yang diaktifkan
- LDAP bind dengan uid=zmpostfix,cn=appaccts,cn=zimbra berhasil (password: pk3wkujQ)

Kesimpulan: LDAP-only authentication properly dikonfigurasi dan aktif di LDAP layer.



2. Root cause error 403 "authentication policy needs more steps"

Error ini terjadi di aplikasi layer (HTTP 403 dari /service/soap/AuthRequest), bukan di LDAP configuration. Kemungkinan penyebab:

Kemungkinan A: Sisa konfigurasi install database authentication
Ketika Anda install otentikasi database PostgreSQL sebelumnya, mungkin ada:
--atribut zimbraAuthLdapSearchQuery atau attribute yang merujuk ke SQL database yang masih tersisa di LDAP schema (meskipun tidak muncul di query kita karena mungkin tidak di-domain level)
- Konfigurasi di zimbraConfig level yang tersisa
- File config di /opt/zextras/conf/ yang mengarah ke database eksternal

Kemungkinan B: Session/Token Cache corruption
- ZM_AUTH_TOKEN atau session cookie yang corrupted
- Cache di memcached atau nginx yang menyimpan state auth yang invalid

Kemungkinan C: Nginx proxy configuration inconsistency
- Konfigurasi nginx lookup (nginx.conf.zmlookup) mungkin memiliki cache yang expired atau inconsistent
- Master auth user zmnginx dengan password pk3wkujQ mungkin memiliki masalah

Kemungkinan D: Mailboxd authentication module state
- Mailboxd (Java application) mungkin memiliki internal state yang rusak terkait authentication flow
- Terutama jika mailboxd di-restart tapi session state tidak di-clear

2. Root cause error 403 "authentication policy needs more steps"

Error ini terjadi di aplikasi layer (HTTP 403 dari /service/soap/AuthRequest), bukan di LDAP configuration. Kemungkinan penyebab:

Kemungkinan A: Sisa konfigurasi install database authentication
Ketika Anda install otentikasi database PostgreSQL sebelumnya, mungkin ada:
--atribut zimbraAuthLdapSearchQuery atau attribute yang merujuk ke SQL database yang masih tersisa di LDAP schema (meskipun tidak muncul di query kita karena mungkin tidak di-domain level)
- Konfigurasi di zimbraConfig level yang tersisa
- File config di /opt/zextras/conf/ yang mengarah ke database eksternal

Kemungkinan B: Session/Token Cache corruption
- ZM_AUTH_TOKEN atau session cookie yang corrupted
- Cache di memcached atau nginx yang menyimpan state auth yang invalid

Kemungkinan C: Nginx proxy configuration inconsistency
- Konfigurasi nginx lookup (nginx.conf.zmlookup) mungkin memiliki cache yang expired atau inconsistent
- Master auth user zmnginx dengan password pk3wkujQ mungkin memiliki masalah

Kemungkinan D: Mailboxd authentication module state
- Mailboxd (Java application) mungkin memiliki internal state yang rusak terkait authentication flow
- Terutama jika mailboxd di-restart tapi session state tidak di-clear



3. Mengapa install database authentication sebelumnya merusak

Pola yang Anda sebut "2 database":
- Database 1: PostgreSQL untuk email/mailbox (sudah ada sebagai bagian dari Carbonio)
- Database 2: PostgreSQL tambahan untuk authentication (yang Anda install)

Masalahnya:
1. Install database authentication baru menambahkan kompleksitas
2. Konfigurasi auth mechanism berubah dari LDAP-only ke LDAP+SQL
3. Setelah restore dari backup, residu konfigurasi SQL auth masih tersisa
4. LDAP sudah kembali ke LDAP-only, tapi aplikasi layer mungkin masih mencoba menggunakan mechanism lama



4. Rekomendasi Perbaikan

Langkah 1: Clear session/token cache
bash
Restart layanan yang berkaitan dengan session
systemctl restart carbonio-memcached
systemctl restart carbonio-nginx
Atau secara manual clear cookie/token di browser
Langkah 2: Cek apakah ada sisa konfigurasi SQL auth
bash
Cari atribut yang merujuk ke database eksternal
/opt/zextras/common/bin/ldapsearch -x -H ldap://192.168.18.19:389 \
  -D "uid=zmpostfix,cn=appaccts,cn=zimbra" -w "pk3wkujQ" \
  -b "dc=ciptamasjaya,dc=co,dc=id" \
  "(zimbraAuthLdapSearchQuery=*)" zimbraAuthLdapSearchQuery


Langkah 3: Restart mailboxd untuk clear internal state
bash
su - zextras
zmmailboxdctl restart


Langkah 4: Jika masih bermasalah, cek log aplikasi
bash
tail -100 /opt/zextras/log/mailboxd.log | grep -i "auth\|403\|policy\|step"


Langkah 5: Test dengan user baru (bukan admin)
Buat test account dan coba login untuk memastikan bukan masalah specific account.



Kesimpulan Akhir

LDAP-only authentication sudah dikonfirmasi aktif dan benar. Masalah error 403 "authentication policy needs more steps" kemungkinan disebabkan oleh:

1. Residu konfigurasi install database authentication yang tersisa di application layer
2. Session/token cache corruption yang perlu di-clear
3. Mailboxd internal state yang perlu di-restart

Saran utama: Jangan install database authentication tambahan. Pola LDAP-only sudah cukup untuk skalabilitas user Anda yang terbatas. Fokus perbaikan adalah clear cache/state application layer, bukan ubah LDAP configuration


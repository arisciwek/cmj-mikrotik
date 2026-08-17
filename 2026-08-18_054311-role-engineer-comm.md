# ENGINEER — REPOSITORY COMMUNICATION & REPORTING PROTOCOL

## 1. REPOSITORY ADALAH MEDIA KOMUNIKASI RESMI

Komunikasi antara ENGINEER dan SYSTEM ANALYST dilakukan melalui repository.

Repository adalah:

> SINGLE SOURCE OF TRUTH

Jangan mengandalkan percakapan langsung, memory agent, atau asumsi mengenai keputusan SYSTEM ANALYST.

Setiap pekerjaan penting harus menghasilkan artefak yang tersimpan di repository.

---

## 2. SIKLUS KERJA ENGINEER

Setiap pekerjaan mengikuti siklus:

```text
PULL
  ↓
READ CURRENT STATE
  ↓
READ SYSTEM ANALYST REVIEW
  ↓
INVESTIGATE
  ↓
IMPLEMENT
  ↓
TEST
  ↓
VERIFY
  ↓
WRITE REPORT
  ↓
COMMIT
  ↓
PUSH
  ↓
WAIT FOR REVIEW
```

---

## 3. SEBELUM BEKERJA

ENGINEER wajib melakukan:

```bash
git pull origin <branch>
```

Kemudian membaca:

* laporan sebelumnya;
* review SYSTEM ANALYST;
* keputusan terakhir;
* task yang masih OPEN;
* constraint;
* acceptance criteria.

Jangan mengerjakan task berdasarkan laporan lama tanpa memeriksa perubahan terbaru di repository.

---

## 4. LAPORAN ENGINEER

Setiap task harus menghasilkan laporan.

Format minimal:

```text
# ENGINEER REPORT

## Task
Apa yang dikerjakan.

## Objective
Tujuan pekerjaan.

## Current State
Kondisi sebelum perubahan.

## Investigation
Pemeriksaan yang dilakukan.

## Evidence
Output command, log, konfigurasi, atau bukti teknis.

## Hypothesis
Hipotesis teknis.

## Actions
Perubahan yang dilakukan.

## Result
Hasil setelah perubahan.

## Verification
Pengujian yang dilakukan.

## Root Cause
Root cause jika sudah diketahui.

## Remaining Issues
Masalah yang masih tersisa.

## Risk
Risiko yang masih ada.

## Recommendation
Rekomendasi teknis.

## Status
OPEN / PARTIAL / RESOLVED / BLOCKED

## Acceptance Criteria
PASS / FAIL untuk setiap kriteria.
```

---

## 5. JANGAN MENULIS LAPORAN YANG TIDAK TERBUKTI

Laporan harus berdasarkan evidence.

Jangan menulis:

> "Kemungkinan sudah normal."

Gunakan:

> "Service active, tetapi functional test belum dilakukan."

Bedakan:

* CONFIRMED
* OBSERVED
* SUSPECTED
* UNKNOWN

---

## 6. COMMIT LAPORAN

Setelah laporan selesai:

```bash
git status
git diff
git add <report-files>
git commit -m "engineer: report <task-name>"
git push origin <branch>
```

Commit message harus menjelaskan jenis perubahan.

Contoh:

```text
engineer: report wireguard connectivity investigation
engineer: report carbonio nginx recovery
engineer: verify proxmox termproxy
engineer: update network diagnostics
```

---

## 7. JANGAN MENIMPA HASIL ANALYST

ENGINEER tidak boleh mengedit atau menghapus review SYSTEM ANALYST.

Jika tidak setuju dengan review:

buat laporan baru yang menjelaskan:

```text
TECHNICAL RESPONSE

Analyst Review:
...

Engineer Position:
...

Evidence:
...

Technical Conflict:
...

Recommendation:
...
```

Kemudian commit dan push.

---

## 8. SETELAH PUSH

Setelah push berhasil:

```text
STATUS: WAITING_FOR_ANALYST_REVIEW
```

ENGINEER tidak boleh menganggap pekerjaan selesai hanya karena command berhasil.

Pekerjaan dianggap selesai setelah:

1. technical verification PASS;
2. report committed;
3. report pushed;
4. SYSTEM ANALYST melakukan review;
5. jika ada corrective action, ENGINEER mengerjakannya.

---

## 9. MEMBACA REVIEW SYSTEM ANALYST

Sebelum memulai pekerjaan berikutnya:

```bash
git pull origin <branch>
```

Baca review terbaru.

Perhatikan:

* APPROVED
* CHANGES_REQUIRED
* REJECTED
* BLOCKED
* NEW_TASK

Jika:

### APPROVED

Task dapat ditutup.

### CHANGES_REQUIRED

ENGINEER melakukan perubahan yang diminta.

### REJECTED

ENGINEER berhenti menggunakan pendekatan tersebut dan membaca alasan rejection.

### BLOCKED

ENGINEER tidak melakukan perubahan spekulatif. Cari evidence yang diminta.

### NEW_TASK

ENGINEER mengerjakan task baru sesuai scope.

---

## 10. ATURAN BRANCH

Gunakan branch sesuai workflow yang ditentukan project.

Jika hanya terdapat satu branch utama, ENGINEER tetap wajib melakukan:

```text
pull → work → report → commit → push
```

Jangan melakukan force push.

Jangan melakukan:

```bash
git push --force
```

kecuali secara eksplisit diperintahkan.

---

## 11. PRINSIP UTAMA

ENGINEER bertanggung jawab atas:

> EXECUTION + EVIDENCE + REPORT

SYSTEM ANALYST bertanggung jawab atas:

> ANALYSIS + DECISION + REVIEW

Repository menjadi penghubung keduanya.

Tidak ada keputusan penting yang hanya berada di memory agent.

Jika keputusan tidak tercatat di repository, anggap keputusan tersebut BELUM RESMI.

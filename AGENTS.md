# AGENTS.md — Aplikasi Pendaftaran Beasiswa Pelatihan

> Letakkan file ini di **root workspace**. Codex membacanya otomatis setiap sesi,
> sehingga prompt per fase bisa pendek tanpa kehilangan konteks.

---

## 1. Tentang Proyek

Aplikasi pendaftaran beasiswa pelatihan berbasis **microservices**. Empat peran pengguna:
Calon Peserta, Verifikator, Lembaga Seleksi, Admin.

Dokumen sumber ada di `docs/`:
- `docs/PETUNJUK_TESTING.pdf` — arsitektur, deployment, dan persyaratan keamanan
- `docs/PETUNJUK_TESTING__1_.pdf` — flow proses 4 aktor
- `docs/mockup/*.html` — 10 mockup Bootstrap 5.3 yang menjadi **acuan UI dan acuan field**

**Mockup adalah sumber kebenaran untuk field, kolom tabel, dan alur layar.** Kalau ada
konflik antara asumsi dan mockup, menangkan mockup.

---

## 2. Keputusan Teknis (sudah final, jangan ditawar ulang)

| # | Keputusan | Alasan |
|---|---|---|
| ADR-001 | **Node.js + TypeScript untuk SEMUA service**, termasuk Service Transaksi | Dokumen menulis "Laravel/Node.js". Dipilih Node agar satu toolchain, satu standar test, satu shared library. Menambah PHP ke tim kecil dengan tenggat 2 hari tidak sepadan. |
| ADR-002 | MySQL untuk RBAC, Master, Transaksi. **PostgreSQL untuk Dokumen** | Mengikuti diagram arsitektur. PostgreSQL dipakai untuk `JSONB` metadata file dan `UUID` native. |
| ADR-003 | **Snapshot data beasiswa** ke dalam record pendaftaran, plus validasi sinkron sekali saat pendaftaran dibuat | Tidak ada FK lintas service. Snapshot mencegah pendaftaran yang sudah submit jadi tidak valid ketika admin mengubah persyaratan di tengah periode. |
| ADR-004 | State machine 7 status, ditegakkan di satu fungsi | Cegah transisi ilegal dan edit setelah submit. |
| ADR-005 | JWT **RS256**. Private key hanya di RBAC, Gateway hanya pegang public key | Dengan HS256, Gateway ikut mampu menerbitkan token palsu, bukan sekadar memverifikasi. |
| ADR-006 | Email dikirim asinkron, kegagalan email tidak menggagalkan transaksi | SMTP mati tidak boleh membuat pendaftaran gagal. |
| ADR-007 | ORM **Prisma** untuk semua service | Prepared statement otomatis, memenuhi syarat anti SQL injection. |

**Stack per service:** Node 20 + TypeScript + Express + Prisma + Zod.
**Frontend:** React 18 + TypeScript + Vite + React Router + TanStack Query + Axios + **Bootstrap 5.3**
(bukan Tailwind — mockup sudah memakai Bootstrap, ikuti agar hemat waktu).

---

## 3. Struktur Workspace

```
beasiswa/
├── AGENTS.md
├── docs/                      # dokumen sumber + ERD + OpenAPI + ADR
├── infra/
│   ├── docker-compose.yml
│   └── .env.example
├── service-rbac/              # git repo sendiri
├── service-master/            # git repo sendiri
├── service-transaksi/         # git repo sendiri
├── service-dokumen/           # git repo sendiri
├── api-gateway/               # git repo sendiri
└── frontend/                  # git repo sendiri
```

**Persyaratan dokumen: setiap service adalah repo Git tersendiri.** Jalankan `git init`
di dalam masing-masing folder, bukan satu repo untuk keseluruhan.

Struktur internal tiap service:
```
src/
├── config/       env loader (Zod-validated), koneksi db
├── modules/      <fitur>/{controller,service,repository,schema}.ts
├── middlewares/  auth, error handler, request-id, validate
├── routes/
├── utils/
├── app.ts
└── server.ts
prisma/schema.prisma
prisma/seed.ts
Dockerfile  .dockerignore  .env.example  README.md
```

---

## 4. Model Data

### Service RBAC (MySQL `db_rbac`)
- `users` — id, nama, username, email, password_hash (**argon2id**), role_id, is_email_verified, is_active, last_login_at
- `roles` — id, kode (`CALON_PESERTA`|`VERIFIKATOR`|`LEMBAGA_SELEKSI`|`ADMIN`), nama
- `menus` — id, parent_id, nama, path, icon, urutan, is_active
- `role_menu_access` — role_id, menu_id, can_view, can_create, can_update, can_delete
- `refresh_tokens` — id, user_id, token_hash, expires_at, revoked_at
- `email_verifications` — id, user_id, token_hash, expires_at, used_at

### Service Master (MySQL `db_master`)
- `beasiswa` — id, kode, nama, deskripsi, persyaratan_khusus, kuota, metode, tanggal_buka, tanggal_tutup, status (`AKTIF`|`NONAKTIF`|`DITUTUP`), deleted_at
- `persyaratan` — id, beasiswa_id, nama_dokumen, format_allowed (csv: `pdf,jpg,png`), max_size_kb, is_mandatory, urutan

### Service Transaksi (MySQL `db_transaksi`)
- `pendaftaran` — id, kode_pendaftaran (`REG-2026-0001`), user_id, beasiswa_id, **beasiswa_snapshot (JSON)**, status, section_terakhir, jumlah_revisi, submitted_at, created_at
- `pendaftaran_data_diri` — pendaftaran_id, nik, nama_lengkap, tempat_lahir, tanggal_lahir, jenis_kelamin, alamat_domisili, provinsi, kabupaten_kota, kecamatan, kelurahan, no_hp, email
- `pendaftaran_pendidikan` — pendaftaran_id, pendidikan_terakhir, nama_instansi, jurusan, pekerjaan
- `pendaftaran_dokumen` — pendaftaran_id, persyaratan_id, dokumen_uuid (referensi ke Service Dokumen), nama_dokumen
- `pendaftaran_persetujuan` — pendaftaran_id, setuju_keabsahan, setuju_ketentuan, disetujui_at
- `verifikasi` — id, pendaftaran_id, verifikator_id, keputusan (`DISETUJUI`|`DITOLAK`|`REVISI`), catatan_umum, created_at
- `verifikasi_checklist` — verifikasi_id, persyaratan_id, is_sesuai, catatan_perbaikan
- `wawancara` — id, pendaftaran_id, penilai_id, nilai_komunikasi, nilai_teknis, nilai_komitmen, nilai_akhir, status (`LULUS`|`TIDAK_LULUS`), catatan_evaluasi
- `audit_status` — id, pendaftaran_id, status_lama, status_baru, actor_id, actor_role, catatan, created_at

**Nilai akhir wawancara dihitung server-side, bukan dipercaya dari frontend:**
`nilai_akhir = (komunikasi * 0.3) + (teknis * 0.4) + (komitmen * 0.3)`

### Service Dokumen (PostgreSQL `db_dokumen`)
- `dokumen` — id (UUID), kode_pendaftaran, persyaratan_id, nama_file_asli, nama_file_simpan, path, mime_terdeteksi, ukuran_byte, sha256, status_scan, uploaded_by, created_at, metadata (JSONB)

---

## 5. State Machine Status (WAJIB)

```
DRAFT → DIAJUKAN → {LOLOS_ADMIN | DITOLAK_ADMIN | REVISI}
REVISI → DIAJUKAN
LOLOS_ADMIN → {LULUS_WAWANCARA | TIDAK_LULUS_WAWANCARA}
```

| Dari | Ke | Role yang boleh | Syarat |
|---|---|---|---|
| DRAFT | DIAJUKAN | pemilik | semua section lengkap + dokumen wajib terunggah + persetujuan dicentang |
| DIAJUKAN | LOLOS_ADMIN | VERIFIKATOR | semua checklist dokumen `is_sesuai = true` |
| DIAJUKAN | DITOLAK_ADMIN | VERIFIKATOR | catatan wajib diisi |
| DIAJUKAN | REVISI | VERIFIKATOR | minimal 1 catatan perbaikan |
| REVISI | DIAJUKAN | pemilik | validasi lengkap diulang |
| LOLOS_ADMIN | LULUS_WAWANCARA | LEMBAGA_SELEKSI | 3 komponen nilai terisi |
| LOLOS_ADMIN | TIDAK_LULUS_WAWANCARA | LEMBAGA_SELEKSI | 3 komponen nilai terisi |

Status final (`DITOLAK_ADMIN`, `LULUS_WAWANCARA`, `TIDAK_LULUS_WAWANCARA`) tidak bisa diubah.

Implementasi: **satu file** `src/domain/status-machine.ts` dengan fungsi
`assertTransition(from, to, role)`. Semua perubahan status wajib melewatinya.
Setiap transisi menulis satu baris ke `audit_status`.

**Aturan kunci edit:** peserta hanya boleh mengubah data saat status `DRAFT` atau `REVISI`.
Percobaan edit saat status lain → HTTP 403, bukan sekadar tombol disembunyikan di UI.

**Aturan 1 pendaftaran:** satu user hanya boleh punya **satu pendaftaran aktif**
(status apa pun selain `DITOLAK_ADMIN` / `TIDAK_LULUS_WAWANCARA`). Ini terlihat di mockup
`4_index_revisi.html`, di mana program lain terkunci saat sudah mendaftar satu program.
Tegakkan dengan unique constraint parsial + pengecekan di service.

---

## 6. Aturan Keamanan (NON-NEGOTIABLE)

Ini persyaratan eksplisit dokumen. Jangan disederhanakan dengan alasan hemat waktu.

1. **JWT RS256.** Access token ~15 menit. Refresh token di **HttpOnly + Secure + SameSite=Strict cookie**, disimpan hashed di DB, **dirotasi setiap kali dipakai** (token lama langsung dibatalkan).
2. **Password argon2id.** Tidak pernah plaintext, tidak pernah MD5/SHA1.
3. **Role TIDAK PERNAH diambil dari input pengguna.** Mockup login internal punya dropdown "Masuk Sebagai" — dropdown itu **hanya kosmetik**. Server menentukan role dari database. Kalau role dari dropdown dipercaya, siapa pun bisa login sebagai Admin.
4. **Login internal vs publik.** Endpoint login sama, tapi login internal menolak `CALON_PESERTA` dan login publik menolak role internal.
5. **Anti SQL Injection.** Semua query lewat Prisma. Dilarang string concatenation dan `$queryRawUnsafe`.
6. **Anti XSS.** Sanitasi input string di backend. Dilarang `dangerouslySetInnerHTML` di frontend.
7. **Anti CSRF.** JWT di header Authorization + cookie `SameSite=Strict`.
8. **Anti IDOR.** Kepemilikan dicek **di dalam query**, bukan setelahnya:
   `WHERE id = ? AND user_id = ?`, bukan ambil dulu lalu bandingkan.
9. **Isolasi jaringan.** Hanya `frontend` dan `api-gateway` yang publish port ke host. Service backend dan database **tidak boleh punya `ports:` di docker-compose sama sekali** — cukup `expose`. Ini yang mewujudkan persyaratan private VPC. Service backend mempercayai header identitas dari Gateway, jadi kalau mereka bisa dihubungi langsung dari luar, seluruh model keamanan runtuh.
10. **Rate limit.** Umum 100 req/menit. Login/register 10 req/menit per IP. Upload 20 req/menit.
11. **CORS** whitelist origin frontend saja, dengan `credentials: true`. Dilarang `origin: "*"`.
12. **Upload dokumen** — urutan pemeriksaan wajib, jangan diubah dan jangan ada yang dilewati:
    1. cek auth + kepemilikan permohonan
    2. cek ukuran (max 2MB sesuai mockup)
    3. **cek magic bytes**, bukan ekstensi (`%PDF`, `\xFF\xD8\xFF` JPEG, `\x89PNG`)
    4. (opsional bila waktu cukup) scan ClamAV
    5. rename ke UUID, simpan ke `/storage/permohonan/{kode_pendaftaran}/{uuid}_{jenis}.ext`
    6. simpan metadata + SHA-256
    Kalau langkah 3 atau 4 gagal, tolak dan **hapus file sementara**.
13. **File tidak boleh punya URL statis.** Akses hanya via `GET /api/dokumen/:uuid` yang mengecek autentikasi dan otorisasi, lalu stream file. Folder storage tidak boleh dilayani sebagai static.
14. **Persistent volume** untuk MySQL, PostgreSQL, dan **storage dokumen**. Tanpa volume dokumen, semua berkas peserta hilang pada redeploy pertama.
15. **Secrets lewat environment variable.** Tidak ada kredensial di dalam repo. Sediakan `.env.example` tanpa nilai asli.
16. Error response tidak boleh membocorkan stack trace atau versi framework.

---

## 7. Konvensi

**Response envelope seragam di semua service:**
```json
{ "success": true, "data": {}, "message": "", "errors": [] }
```
Error: `{ "success": false, "message": "...", "errors": [{"field":"nik","message":"..."}] }`

- Tabel & kolom: `snake_case`. Endpoint: `kebab-case`, berbasis resource.
- Timestamp disimpan **UTC**, dikonversi ke WIB di frontend.
- Istilah domain boleh bahasa Indonesia (`pendaftaran`, `beasiswa`), tapi konsisten —
  jangan campur `registration` dan `pendaftaran` untuk hal yang sama.
- Logging JSON terstruktur dengan `request_id` yang diteruskan Gateway ke semua service.
- Setiap service wajib punya `GET /health`.
- Validasi input pakai **Zod** di setiap endpoint.

**Header internal dari Gateway ke service:** `X-User-Id`, `X-User-Role`, `X-Request-Id`.

---

## 8. Peta Endpoint

```
PUBLIK (tanpa token)
POST /api/auth/register            registrasi calon peserta (role dipaksa CALON_PESERTA)
GET  /api/auth/verify-email
POST /api/auth/login
POST /api/auth/refresh
GET  /api/beasiswa/aktif           daftar program untuk landing page

RBAC
GET/POST/PUT/DELETE /api/users            ADMIN
GET/POST/PUT/DELETE /api/roles            ADMIN
GET/POST/PUT/DELETE /api/menus            ADMIN
GET  /api/auth/me
GET  /api/auth/my-menus                   menu dinamis sesuai role

MASTER
GET/POST/PUT/DELETE /api/beasiswa         ADMIN (delete = soft delete)
GET/POST/PUT/DELETE /api/persyaratan      ADMIN

TRANSAKSI
POST /api/pendaftaran                     buat draft (cek aturan 1 pendaftaran)
GET  /api/pendaftaran/saya
PUT  /api/pendaftaran/:id/section/:n      simpan per section
POST /api/pendaftaran/:id/submit
GET  /api/verifikasi/antrian              VERIFIKATOR
GET  /api/verifikasi/:id
POST /api/verifikasi/:id/keputusan        VERIFIKATOR
GET  /api/wawancara/antrian               LEMBAGA_SELEKSI
POST /api/wawancara/:id/penilaian         LEMBAGA_SELEKSI
GET  /api/dashboard/statistik             ADMIN (satu query GROUP BY status)
GET  /api/hasil-seleksi/export            ADMIN, Excel

DOKUMEN
POST   /api/dokumen/upload
GET    /api/dokumen/:uuid                 stream, dengan cek otorisasi
DELETE /api/dokumen/:uuid                 hanya saat DRAFT/REVISI
```

**Counter dashboard (definisi query):**
Pendaftar = status ≠ DRAFT · Dalam Proses Admin = DIAJUKAN + REVISI ·
Lulus Admin = LOLOS_ADMIN + LULUS_WAWANCARA + TIDAK_LULUS_WAWANCARA (kumulatif) ·
Tidak Lulus Admin = DITOLAK_ADMIN · Dalam Proses Wawancara = LOLOS_ADMIN ·
Lulus Wawancara = LULUS_WAWANCARA · Tidak Lulus Wawancara = TIDAK_LULUS_WAWANCARA

---

## 9. Peta Layar Frontend ↔ Mockup

| Route | Mockup | Role |
|---|---|---|
| `/` | `1_index.html` | publik |
| `/login-internal` | `1_index_login.html` | internal |
| `/pendaftaran` (wizard 4 step) | `2_index_awal.html` | peserta |
| `/dashboard` status terkunci | `3_index_terkirim.html` | peserta |
| `/dashboard` mode revisi | `4_index_revisi.html` | peserta |
| `/dashboard` pengumuman lulus | `6_index_lulus.html` | peserta |
| `/` saat tidak ada gelombang aktif | `5_index_ditutup.html` | publik/peserta |
| `/verifikasi` | `2_index_verifikator.html` | verifikator |
| `/wawancara` | `3_index_wawancara.html` | lembaga seleksi |
| `/admin` | `4_index_admin.html` | admin |

Sidebar/menu dirender dari `GET /api/auth/my-menus`, **bukan array hardcoded**.
Kalau menu di-hardcode, seluruh modul RBAC jadi hiasan.

---

## 10. Aturan Kerja untuk Codex

- **Jangan bertanya di tengah pengerjaan.** Semua keputusan sudah ada di file ini. Kalau benar-benar ambigu, ambil opsi paling sederhana yang memenuhi persyaratan keamanan, lalu catat di `docs/ASUMSI.md`.
- **Jangan menambah fitur di luar cakupan.** Tidak ada penjadwalan wawancara (dilakukan di luar sistem), tidak ada chat, tidak ada pembayaran.
- **Selesaikan satu fase sampai bisa dijalankan** sebelum pindah fase. Lebih baik 4 service yang jalan daripada 6 service setengah jadi.
- **Verifikasi sendiri.** Setelah menulis kode, jalankan `npx tsc --noEmit`, jalankan service, dan uji endpoint dengan curl. Jangan melapor selesai tanpa membuktikan.
- **Setiap akhir fase**, tulis ringkasan singkat di `docs/PROGRESS.md`: apa yang jadi, apa yang belum, cara menjalankannya.
- Gunakan `.env.example`, jangan pernah commit `.env`.
- Kalau menemukan konflik antara mockup dan dokumen PDF, ikuti mockup dan catat konfliknya.

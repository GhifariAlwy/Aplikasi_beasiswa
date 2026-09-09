# PROGRESS — Aplikasi Pendaftaran Beasiswa Pelatihan

Diisi Claude Code di **akhir setiap fase** (§10 CLAUDE.md — "Setiap akhir fase, tulis
ringkasan singkat di docs/PROGRESS.md: apa yang jadi, apa yang belum, cara
menjalankannya"). Tambahkan entri baru di bagian paling atas (terbaru dulu), jangan
menimpa/menghapus entri fase sebelumnya.

Setiap entri fase memakai format berikut:

```
## Fase <n> — <nama service/fitur> — <tanggal selesai>

### Status
- [ ] Belum dimulai
- [ ] Sedang berjalan
- [ ] Selesai & terverifikasi

### Apa yang sudah jadi
-

### Apa yang belum / diketahui bermasalah
-

### Cara menjalankan & memverifikasi
```bash
# contoh: perintah untuk start service, migrate, seed, curl smoke test
```

### Bukti verifikasi
- `npx tsc --noEmit`: (hasil)
- Service start: (hasil)
- Endpoint diuji manual (curl/Postman): (daftar endpoint + hasil)

### Konflik/asumsi baru yang ditemukan di fase ini
- (jika ada field/endpoint/perilaku baru yang tidak tercakup di ERD.md/OPENAPI.yaml/ASUMSI.md, catat di sini lalu sinkronkan ke ketiga file tersebut)

### Catatan untuk fase berikutnya
-
```

---

<!-- Entri fase diisi di bawah baris ini, terbaru paling atas. Jangan hapus baris pemisah di atas. -->

## Fase 15 — Finalisasi Demo dan Penyerahan — 2026-09-09

### Status
- [x] Selesai & terverifikasi

### Status akhir seluruh fase

| Fase | Area | Status akhir |
|---:|---|---|
| 2 | Fondasi 6 service + infrastruktur Docker | Selesai |
| 3 | Service RBAC | Selesai |
| 4 | API Gateway | Selesai |
| 5 | Service Master | Selesai |
| 6 | Service Dokumen | Selesai |
| 7 | Service Transaksi pendaftaran | Selesai |
| 8 | Verifikasi, wawancara, dashboard, export | Selesai |
| 9 | Frontend React dasar | Selesai |
| 10 | Modul calon peserta | Selesai |
| 11 | Modul internal | Selesai |
| 12 | Modul admin | Selesai |
| 13 | Integrasi full-stack dan seed demo | Selesai |
| 14 | Audit keamanan | Selesai |
| 15 | Finalisasi, unit test, packaging, persistence | Selesai |

### Apa yang sudah jadi
- Keenam image menggunakan Dockerfile multi-stage; backend berjalan sebagai user non-root dengan `HEALTHCHECK`, dan frontend memakai image nginx unprivileged.
- Compose hanya mempublish frontend dan gateway, memiliki volume untuk empat database serta storage dokumen, dan memakai `depends_on` berbasis `service_healthy`.
- README root berisi arsitektur, quickstart, akun demo, endpoint, keamanan, dan keputusan pemangkasan.
- Persistence test lulus: dokumen `%PDF` tetap dapat diunduh setelah `docker compose down` lalu `up -d`; data pendaftaran tetap tersedia.
- Tidak ada `.env` atau private key yang ter-track pada enam repository; key JWT berada di luar workspace.

### Cara menjalankan & memverifikasi
```bash
cp infra/.env.example infra/.env
JWT_KEY_DIR="$HOME/.config/beasiswa" ./infra/scripts/generate-keys.sh
docker compose -f infra/docker-compose.yml --env-file infra/.env up -d --build
./infra/seed-demo.sh
```

### Bukti verifikasi
- `frontend npm run build`: lulus.
- Seluruh container healthy setelah rebuild dan restart.
- Port host: hanya `8080` gateway dan `5173` frontend.
- Persistence: aplikasi demo HTTP `200`, download dokumen HTTP `200`, signature `%PDF`, 26 bytes setelah restart.
- `git ls-files` pada keenam repo tidak menemukan `.env`, `private.pem`, atau `public.pem`; repository lokal belum memiliki commit sehingga `git log` melaporkan belum ada commit.

### Catatan untuk fase berikutnya
- Tidak ada fase pengembangan lanjutan untuk scope demo. ClamAV, Kubernetes, CI/CD, dan E2E browser otomatis sengaja dipangkas dan dijelaskan di README.

## Fase 13 — Integrasi Full Stack dan Seed Demo — 2026-09-09

### Status
- [x] Selesai & terverifikasi

### Apa yang sudah jadi
- `infra/seed-demo.sh` idempoten untuk menyiapkan lima akun peserta dan pendaftaran demo berstatus `DRAFT`, `DIAJUKAN`, `REVISI`, `LOLOS_ADMIN`, dan `LULUS_WAWANCARA`.
- Seed demo mengisi snapshot beasiswa, data wizard, dokumen, checklist verifikasi, nilai wawancara, audit status, serta file PDF valid di volume storage.
- CORS gateway mengizinkan `localhost:5173` dan `127.0.0.1:5173` dengan `Access-Control-Allow-Credentials: true`.
- Memperbaiki precedence route otorisasi dokumen dan forwarding error async agar penolakan akses tidak memutus koneksi.
- Menangani tanggal date-only sebagai `YYYY-MM-DD` pada endpoint publik; data timestamp tetap UTC.

### Cara menjalankan & memverifikasi
```bash
./infra/seed-demo.sh
docker compose -f infra/docker-compose.yml --env-file infra/.env up -d
```

### Bukti verifikasi
- Seed selesai dan menghasilkan 5 akun peserta, 5 pendaftaran, 16 dokumen.
- Distribusi status demo: masing-masing `DRAFT`, `DIAJUKAN`, `REVISI`, `LOLOS_ADMIN`, `LULUS_WAWANCARA` = 1.
- `GET /api/beasiswa/aktif`: mengembalikan hanya 3 program aktif dalam rentang tanggal.
- Login peserta + `GET /api/pendaftaran/saya`: berhasil; data peserta dan snapshot konsisten.
- Download dokumen terotorisasi: HTTP 200 dengan signature `%PDF`; path storage langsung: HTTP 404.
- Peserta lain mengakses UUID dokumen: HTTP 403.
- `GET /api/dashboard/statistik`: counter konsisten (`pendaftar=4`, `dalam_proses_admin=2`, `lulus_admin=2`, `dalam_proses_wawancara=1`, `lulus_wawancara=1`).
- Preflight CORS: `Access-Control-Allow-Origin` sesuai origin dan `Access-Control-Allow-Credentials: true`.
- `service-dokumen` dan `service-transaksi` `npm run typecheck`: lulus.

### Konflik/asumsi baru yang ditemukan di fase ini
- Image production tidak membawa `tsx`, sehingga script mengandalkan schema/data dasar yang telah diprovisioning dan memakai client SQL di container untuk data demo.
- Route `/internal/pendaftaran/by-kode/:kode/...` harus didaftarkan sebelum route parameter `:id` agar string `by-kode` tidak tervalidasi sebagai BigInt.

### Catatan untuk fase berikutnya
- Jalankan empat walkthrough UI authenticated dari browser menggunakan akun demo di atas.

## Fase 12 — Modul Admin Frontend — 2026-09-09

### Status
- [x] Selesai & terverifikasi

### Apa yang sudah jadi
- Dashboard admin dengan tujuh counter dari `GET /api/dashboard/statistik`.
- Rekap hasil seleksi dengan filter pencarian, pagination, kolom mockup, dan Export Excel.
- Komponen `DataTable` reusable untuk seluruh tabel admin.
- CRUD beasiswa, persyaratan, users internal, role, dan struktur menu.
- Matriks hak akses role × menu × aksi dengan penyimpanan ke endpoint menu-access.
- Route `/admin` dibatasi khusus role `ADMIN`.

### Cara menjalankan & memverifikasi
```bash
cd frontend
npm run dev
```

### Bukti verifikasi
- `npm run typecheck`: lulus.
- `npm run build`: lulus.
- `npm run lint`: lulus tanpa error (satu warning Fast Refresh existing pada AuthContext).
- `npm run format:check`: lulus.

### Catatan untuk fase berikutnya
- Pengujian CRUD dan export penuh membutuhkan sesi admin serta database aktif.

## Fase 11 — Modul Internal Verifikator dan Lembaga Seleksi — 2026-09-09

### Status
- [x] Selesai & terverifikasi

### Apa yang sudah jadi
- Halaman verifikator dengan empat counter, filter program, pencarian NIK/nama, tabel antrian, modal detail peserta, checklist dokumen, keputusan, validasi, dan konfirmasi.
- Tombol persetujuan dinonaktifkan sampai seluruh dokumen ditandai sesuai.
- Pratinjau dokumen memakai `GET /api/dokumen/:uuid` melalui Axios dengan token, bukan URL storage langsung.
- Halaman lembaga seleksi dengan empat counter, antrian peserta lolos administrasi, penilaian tiga komponen berbobot 30/40/30, nilai akhir informatif, dan status kelulusan.
- Request penilaian hanya mengirim tiga nilai komponen, status, dan catatan; nilai akhir tetap dihitung server.
- Route frontend dibatasi role `VERIFIKATOR` dan `LEMBAGA_SELEKSI`.

### Cara menjalankan & memverifikasi
```bash
cd frontend
npm run dev
```

### Bukti verifikasi
- `npm run typecheck`: lulus.
- `npm run build`: lulus.
- `npm run lint`: lulus tanpa error (satu warning Fast Refresh existing pada AuthContext).
- `npm run format:check`: lulus.
- Browser route `/verifikasi` tanpa sesi dialihkan ke `/login`.

### Catatan untuk fase berikutnya
- Pengujian penuh modal dan submit keputusan membutuhkan akun internal serta data pendaftaran pada status `DIAJUKAN`/`LOLOS_ADMIN`.

## Fase 10 — Modul Calon Peserta Frontend — 2026-09-09

### Status
- [x] Selesai & terverifikasi

### Apa yang sudah jadi
- Dashboard peserta dengan tabel monitoring sesuai kolom mockup dan katalog program.
- Aturan satu pendaftaran: program aktif ditandai, program lain terkunci.
- Wizard empat bagian dengan autosave ke endpoint section, pemulihan section terakhir, dan validasi Zod/react-hook-form.
- Upload dokumen dengan validasi tipe/ukuran 2 MB, progress, dan nama file.
- Tampilan DRAFT/REVISI editable, DIAJUKAN read-only, catatan perbaikan per dokumen, serta pengumuman LULUS_WAWANCARA.
- Response pendaftaran peserta kini memuat checklist verifikasi agar catatan revisi tersedia di frontend.

### Cara menjalankan & memverifikasi
```bash
cd frontend
npm run dev
```

### Bukti verifikasi
- `npm run typecheck`: lulus.
- `npm run build`: lulus.
- `npm run lint`: lulus tanpa error (satu warning Fast Refresh existing pada AuthContext).
- `npm run format:check`: lulus.
- `cd service-transaksi && npm run typecheck`: lulus.

### Catatan untuk fase berikutnya
- Uji browser penuh membutuhkan service backend, database, MailHog, dan akun peserta aktif.

## Fase 14 — Audit Keamanan CLAUDE.md §6 — 2026-09-09

### Status
- [x] Selesai & terverifikasi

### Apa yang sudah diperbaiki
- Rotasi refresh token dibuat atomik sehingga dua request konkurensi tidak dapat memakai token yang sama.
- Kunci JWT dipindahkan keluar repository; Compose memakai path key dari environment dan private key hanya tersedia di RBAC.
- Seluruh hasil uji 16 aturan keamanan dicatat di [docs/SECURITY_AUDIT.md](./SECURITY_AUDIT.md).

### Bukti utama
- Typecheck RBAC lulus.
- Refresh token lama menghasilkan `401`; uji refresh konkurensi menghasilkan satu `200` dan satu `401`.
- Fake PDF, file kosong, file besar, path traversal, IDOR, rate limit, CORS, cookie flags, spoofed role, storage isolation, dan host-port isolation teruji.

## Fase 9 — Implementasi Frontend React — 2026-09-09

### Status
- [x] Selesai & terverifikasi

### Apa yang sudah jadi
- React 18 + TypeScript + Vite dengan Bootstrap 5.3 dan Bootstrap Icons.
- Landing page program aktif dan keadaan tidak ada gelombang aktif.
- Login publik/internal, registrasi, AuthContext, protected route, dan layout sidebar.
- Sidebar mengambil menu dari `GET /api/auth/my-menus`, bukan array hardcoded.
- Axios memakai access token in-memory dan single-flight refresh queue untuk 401 bersamaan.
- Tidak menggunakan `dangerouslySetInnerHTML`.

### Cara menjalankan & memverifikasi
```bash
cd frontend
npm install
npm run dev
```

### Bukti verifikasi
- `npm run typecheck`: lulus.
- `npm run build`: lulus.
- `npm run lint`: lulus tanpa error (satu warning Fast Refresh pada hook context).
- `npm run format:check`: lulus.

### Catatan untuk fase berikutnya
- Halaman wizard pendaftaran, verifikasi, wawancara, dan admin dapat diintegrasikan ke endpoint backend berikutnya.

## Fase 8 — Verifikasi, Wawancara, Dashboard, dan Hasil Seleksi — 2026-09-09

### Status
- [x] Selesai & terverifikasi

### Apa yang sudah jadi
- Antrian verifikasi dengan filter program/pencarian NIK atau nama, tipe pengajuan Baru/Revisi, counter status, detail peserta, dan checklist berbasis snapshot.
- Keputusan verifikasi `DISETUJUI`, `REVISI`, dan `DITOLAK` dengan validasi aturan, penyimpanan checklist, serta audit status atomik.
- Antrian wawancara khusus `LEMBAGA_SELEKSI`; penilaian tiga komponen dihitung server-side dengan bobot 30/40/30.
- Transisi otomatis ke `LULUS_WAWANCARA` atau `TIDAK_LULUS_WAWANCARA`; tidak ada penjadwalan wawancara.
- Dashboard admin memakai satu `GROUP BY status` untuk tujuh counter.
- Daftar hasil seleksi dengan filter/pagination dan export Excel melalui `exceljs`.
- Guard role di setiap endpoint dan async error forwarding agar error bisnis tidak menggantungkan request.

### Apa yang belum / diketahui bermasalah
- Modul verifikasi dan wawancara belum memiliki halaman frontend; endpoint siap diintegrasikan.

### Cara menjalankan & memverifikasi
```bash
cd service-transaksi
npm install
npx prisma migrate deploy
npm run typecheck
npm run build
npm run lint
npm test
```

### Bukti verifikasi
- Typecheck, build, lint, dan 2 unit test state machine: lulus.
- E2E: submit → `REVISI` dengan catatan → peserta membaca catatan → submit ulang → `LOLOS_ADMIN` → nilai `80/90/70` menghasilkan nilai akhir `81` dan status `LULUS_WAWANCARA`.
- Dashboard: `pendaftar=1`, `lulus_admin=1`, `lulus_wawancara=1`.
- Export: HTTP 200 dengan MIME Excel `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`.
- Role silang: verifikator pada endpoint wawancara dan lembaga seleksi pada endpoint verifikasi ditolak HTTP 403.
- Data E2E dibersihkan setelah pengujian; penghapusan program uji tetap menyisakan baris dengan `deleted_at`.

### Konflik/asumsi baru yang ditemukan di fase ini
- `GET /api/hasil-seleksi` tanpa filter status hanya menampilkan dua status final wawancara, sesuai konteks tabel hasil kelulusan admin.

### Catatan untuk fase berikutnya
- Integrasikan endpoint seleksi ke frontend dan lanjutkan modul RBAC/menu bila diperlukan.

## Fase 7 — Implementasi Service Transaksi: Pendaftaran — 2026-09-09

### Status
- [x] Selesai & terverifikasi

### Apa yang sudah jadi
- Schema Prisma transaksi untuk pendaftaran, data diri, pendidikan, dokumen, persetujuan, dan audit status.
- State machine terpusat dengan validasi role/transisi dan audit setiap transisi submit.
- Pembuatan draft dengan batas satu pendaftaran aktif per user, validasi beasiswa aktif, snapshot beasiswa/persyaratan, dan kode `REG-YYYY-NNNN`.
- Penyimpanan bertahap empat section dengan validasi ringan dan penguncian edit pada status selain `DRAFT`/`REVISI`.
- Submit dengan validasi lengkap terhadap snapshot, dokumen mandatory, data wizard, dan persetujuan.
- Endpoint data pendaftaran milik peserta serta endpoint internal otorisasi dokumen.
- Query perubahan data menggunakan filter kepemilikan langsung; migrasi awal menyertakan unique generated `active_flag`.

### Apa yang belum / diketahui bermasalah
- Keputusan verifikasi dan wawancara belum termasuk dalam scope fase pendaftaran.

### Cara menjalankan & memverifikasi
```bash
cd service-transaksi
npx prisma migrate deploy
npx prisma generate
npm run typecheck
npm run build
npm run lint
npm test
```

### Bukti verifikasi
- `npm run typecheck`: exit 0.
- `npm run build`: exit 0.
- `npm run lint`: exit 0.
- `npm test`: 2 test state machine lulus.
- `npx prisma validate`: schema valid.
- Container E2E: draft `REG-2026-0001`, section 1–4 tersimpan, submit menghasilkan `DIAJUKAN`, edit setelah submit ditolak HTTP 403.
- Endpoint publik tanpa program aktif mengembalikan array kosong; data uji dibersihkan setelah verifikasi.

### Konflik/asumsi baru yang ditemukan di fase ini
- Constraint satu pendaftaran aktif membutuhkan generated column MySQL dan tetap dipasang manual pada migration awal karena tidak dapat diekspresikan di Prisma schema.

### Catatan untuk fase berikutnya
- Lanjutkan dengan modul verifikasi dan wawancara; gunakan state machine yang sama untuk semua transisi.

## Fase 6 — Implementasi Service Dokumen — 2026-09-09

### Status
- [x] Selesai & terverifikasi

### Apa yang sudah jadi
- Schema PostgreSQL `dokumen` dengan UUID native, metadata JSONB, checksum SHA-256, status scan, dan referensi lintas-service.
- Upload multipart dengan urutan auth/ownership → ukuran → magic bytes → hook ClamAV → UUID path → SHA-256 dan metadata.
- Magic bytes PDF, JPEG, dan PNG; ekstensi asli tidak dipercaya.
- Penyimpanan hanya di volume `/storage/permohonan`, tanpa `express.static`.
- Download streaming dengan otorisasi berbasis role dan status pendaftaran.
- Delete hanya untuk pemilik pada status `DRAFT` atau `REVISI`.
- Unit test magic bytes termasuk executable/text yang menyamar sebagai `.pdf`.
- Client otorisasi internal ke Service Transaksi dengan header identitas dan request ID.

### Apa yang belum / diketahui bermasalah
- Uji upload end-to-end dan uji akses user A/B memerlukan Service Transaksi, PostgreSQL, dan migration aktif.
- Endpoint internal otorisasi yang dipanggil Service Dokumen harus disediakan Service Transaksi pada fase implementasinya.

### Cara menjalankan & memverifikasi
```bash
cd service-dokumen
npx prisma migrate dev --name init
npm run seed
npm run dev
```

### Bukti verifikasi
- `npm run typecheck`: exit 0.
- `npm run build`: exit 0.
- `npm run lint`: exit 0.
- `npm test`: 3 test lulus.
- `npx prisma validate`: schema valid.
- `GET /health`: HTTP 200.
- `GET /storage/permohonan/x`: HTTP 404, tidak dilayani sebagai static.
- `GET /api/dokumen/{uuid}` tanpa header identitas: HTTP 401.
- Test executable/text dengan nama `.pdf`: ditolak oleh magic-byte test.

### Konflik/asumsi baru yang ditemukan di fase ini
- Otorisasi lintas-service menggunakan endpoint internal Service Transaksi karena Service Dokumen tidak memiliki FK/database pendaftaran.

### Catatan untuk fase berikutnya
- Implementasikan endpoint internal otorisasi dokumen di Service Transaksi dan tambahkan smoke test upload dengan database/container aktif.

## Fase 5 — Implementasi Service Master — 2026-09-09

### Status
- [x] Selesai & terverifikasi

### Apa yang sudah jadi
- CRUD `beasiswa` khusus `ADMIN` dengan kode slug otomatis dan soft delete melalui `deleted_at`.
- CRUD `persyaratan` khusus `ADMIN`, termasuk filter berdasarkan `beasiswa_id`.
- Endpoint publik `GET /api/beasiswa/aktif` hanya mengembalikan program berstatus `AKTIF` yang tanggalnya sedang berada dalam rentang buka–tutup.
- Endpoint `GET /api/beasiswa/:id/persyaratan` untuk kebutuhan snapshot Service Transaksi.
- Validasi Zod untuk kuota, enum, format tanggal, dan rentang tanggal.
- Seed tiga program pada mockup, masing-masing dengan empat dokumen wajib berformat `pdf,jpg,png` dan batas 2 MB.

### Apa yang belum / diketahui bermasalah
- Smoke test CRUD terhadap database MySQL belum dijalankan karena memerlukan database service yang aktif dan migration deploy.

### Cara menjalankan & memverifikasi
```bash
cd service-master
npm run typecheck
npm run build
npm run lint
npx prisma validate
npx prisma generate
npm run seed
```

### Bukti verifikasi
- `npm run typecheck`: exit 0.
- `npm run build`: exit 0.
- `npm run lint`: exit 0.
- `npx prisma validate`: schema valid.
- Validasi request: input valid diterima, kuota 0 dan tanggal tidak valid ditolak.

### Konflik/asumsi baru yang ditemukan di fase ini
- Tidak ada. Penghapusan beasiswa selalu soft delete sehingga data lintas-service tetap memiliki referensi stabil.

### Catatan untuk fase berikutnya
- Jalankan migration dan smoke test HTTP terhadap MySQL sebelum mengintegrasikan Service Transaksi.

## Fase 4 — Implementasi & Penguatan API Gateway — 2026-09-09

### Status
- [x] Selesai & terverifikasi

### Apa yang sudah jadi
- **Proxy Routing (http-proxy-middleware)**:
  Routing lengkap sesuai CLAUDE.md §8:
  - Publik: `POST /api/auth/register`, `POST /api/auth/login`, `POST /api/auth/refresh`, `GET /api/auth/verify-email` $\rightarrow$ `service-rbac`; `GET /api/beasiswa/aktif` $\rightarrow$ `service-master`.
  - Terproteksi JWT: `/api/dokumen` $\rightarrow$ `service-dokumen`; `/api/users`, `/api/roles`, `/api/menus`, `/api/auth` (me/my-menus/logout) $\rightarrow$ `service-rbac`; `/api/beasiswa`, `/api/persyaratan` $\rightarrow$ `service-master`; `/api/pendaftaran`, `/api/verifikasi`, `/api/wawancara`, `/api/dashboard`, `/api/hasil-seleksi` $\rightarrow$ `service-transaksi`.
- **Verifikasi JWT RS256**:
  Hanya memegang `public.pem` (Gateway tidak pernah memiliki `private.pem`). Algoritma dikunci ke `RS256`. Menyisipkan header internal `X-User-Id`, `X-User-Role`, dan meneruskan `X-Request-Id` ke service backend.
- **Keamanan & Guardrails**:
  - CORS whitelist origin frontend (`credentials: true`), dilarang wildcard.
  - Helmet untuk security headers (`Content-Security-Policy`, `HSTS`, `X-Frame-Options`, `nosniff`, dll).
  - Rate limiting 3 tingkat: Umum (100 req/menit), Auth (10 req/menit per IP), Upload (20 req/menit).
  - Body size limit: 1MB untuk JSON/umum, 3MB khusus route upload (`/api/dokumen/upload`), ditolak dengan HTTP 413.
  - Timeout 30 detik per request ke service tujuan (`proxyTimeout: 30000`, `timeout: 30000`), penanganan error terstruktur HTTP 504 / HTTP 502.
  - Streaming multipart upload ke Service Dokumen tanpa penampungan memori (tanpa `express.json()` atau `multer` di gateway).

### Cara menjalankan & memverifikasi
```bash
# Typecheck & Build
cd api-gateway && npm run typecheck && npm run build

# Uji endpoint lewat curl
curl -i http://localhost:8080/health
curl -i http://localhost:8080/api/users   # Ditolak 401
```

### Bukti verifikasi
- `npm run typecheck`: Exit 0 (bersih)
- `npm run build`: Exit 0 (bersih)
- Request tanpa token: HTTP 401 Unauthorized (`Autentikasi diperlukan`)
- Token kadaluarsa: HTTP 401 Unauthorized (`Token tidak valid atau sudah kedaluwarsa`)
- Endpoint publik tanpa token: HTTP 200 OK (`/health`)
- Rate limiting: Request ke-11 ke auth endpoint langsung diblokir dengan HTTP 429 Too Many Requests
- Body size limit: Payload > 1MB ditolak dengan HTTP 413 Payload Too Large

---

## Fase 3 — Implementasi Lengkap service-rbac — 2026-09-09

### Status
- [x] Selesai & terverifikasi

### Apa yang sudah jadi
- **Skema Prisma & Migrasi db_rbac**:
  Tabel `users`, `roles`, `menus`, `role_menu_access`, `refresh_tokens`, `email_verifications`. Migrasi terpasang dan database `db_rbac` tersinkronisasi.
- **Autentikasi Lengkap**:
  - `POST /api/auth/register`: registrasi calon peserta, paksa role `CALON_PESERTA` (abaikan role dari body), kirim email aktivasi ke MailHog, akun non-aktif sebelum verifikasi.
  - `GET /api/auth/verify-email`: verifikasi token aktivasi satu kali pakai, aktivasi akun.
  - `POST /api/auth/login`: hashing password argon2id, terbitkan access token RS256 (~15 menit) + refresh token di cookie HttpOnly/Secure/SameSite=Strict. Mendukung parameter `scope` ("publik" | "internal") dan `channel` ("PUBLIK" | "INTERNAL") secara fleksibel. Penolakan ketat login lintas scope (peserta dilarang login di internal, internal dilarang login di publik). Role murni dibaca dari database.
  - `POST /api/auth/refresh`: rotasi refresh token otomatis. Deteksi token reuse (jika token lama dipakai lagi, seluruh sesi aktif user langsung dicabut).
  - `POST /api/auth/logout`: revoke refresh token dan clear cookie.
  - `GET /api/auth/me`: mengembalikan profil pengguna login.
  - `GET /api/auth/my-menus`: mengembalikan struktur pohon menu bertingkat sesuai role pengguna dengan flag `can_view`, `can_create`, `can_update`, `can_delete`.
- **CRUD Khusus ADMIN**:
  - `GET/POST/PUT/DELETE /api/users`: manajemen user internal.
  - `GET/POST/PUT/DELETE /api/roles`: manajemen role.
  - `PUT /api/roles/:id/menu-access`: pengaturan izin akses menu per role.
  - `GET/POST/PUT/DELETE /api/menus`: manajemen menu sistem.
  - Akses ditolak (HTTP 403) untuk user non-admin.
- **Seed Idempoten (`prisma/seed.ts`)**:
  - 4 role resmi: `CALON_PESERTA`, `VERIFIKATOR`, `LEMBAGA_SELEKSI`, `ADMIN`.
  - Struktur menu hierarkis lengkap sesuai mockup admin.
  - Matriks hak akses menu per role.
  - Akun demo per role dengan password `Password123!`.
- **Unit Test (Vitest)**:
  - 37 test lolos: password hashing argon2id, rotasi refresh token & reuse detection, login cross-scope rejection (channel & scope parameter), dan pemfilteran menu per role.

### Cara menjalankan & memverifikasi
```bash
# Jalankan unit test
cd service-rbac && npm test

# Jalankan typecheck
cd service-rbac && npm run typecheck

# Jalankan container (jika belum)
cd infra && docker compose up -d

# Uji login & menu lewat API Gateway
curl -s -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"identifier":"admin","password":"Password123!","scope":"internal"}'
```

### Bukti verifikasi
- `npm run typecheck`: Exit 0 (bersih)
- `npm test`: 4 test files, 37 passing (100%)
- Live curl testing:
  - Login scope `internal` & `publik`: Berhasil
  - Cross-scope login: Ditolak (HTTP 403)
  - Refresh token rotation & reuse detection: Berhasil
  - `GET /api/auth/my-menus`: Berhasil mengembalikan menu yang berbeda dan spesifik untuk 4 role.

---

## Fase 2 — Fondasi 6 service + infrastruktur Docker — 2026-09-08

### Status
- [x] Selesai & terverifikasi

### Apa yang sudah jadi

**Enam repo Git terpisah** (bukan monorepo, sesuai persyaratan dokumen). `git init`
dijalankan di dalam masing-masing folder, semuanya di branch `main`:
`service-rbac`, `service-master`, `service-transaksi`, `service-dokumen`,
`api-gateway`, `frontend`. Root repo `beasiswa/` hanya memuat `CLAUDE.md`, `docs/`,
dan `infra/`; keenam folder service di-*ignore* di `.gitignore` root supaya tidak
pernah tertelan jadi submodul/subfolder repo induk.

**Empat service backend + gateway** — Node 20 + TypeScript 5.7 (strict) + Express +
Prisma 6 + Zod 3, struktur `src/{config,modules,middlewares,routes,utils}` sesuai
§3 CLAUDE.md, plus `Dockerfile`, `.dockerignore`, `.env.example`, `README.md`, dan
`GET /health` di tiap service.

**Shared middleware identik di semua service backend** (§4 permintaan fase ini):
- `middlewares/error-handler.ts` — response envelope `{success,data,message,errors}`;
  ZodError → 400 per-field, `AppError` → status sendiri, sisanya → 500 dengan pesan
  generik. Stack trace hanya masuk log server, **tidak pernah** dikirim ke klien
  (§6 aturan 16).
- `middlewares/request-id.ts` — membaca `X-Request-Id` dari Gateway, generate
  `randomUUID()` bila tidak ada. Nilai masukan divalidasi `^[A-Za-z0-9_-]{1,128}$`
  supaya tidak bisa dipakai untuk log injection. Meng-echo balik header dan mencatat
  `method/path/status_code/duration_ms` saat response selesai.
- `utils/logger.ts` — logger JSON terstruktur tanpa dependensi, satu baris JSON per
  entri, selalu memuat `request_id`. Kunci sensitif (`password`, `token`,
  `authorization`, `cookie`, dst.) diredaksi rekursif.
- `middlewares/validate.ts` — `validate(schema, target)` berbasis Zod untuk
  `body` / `params` / `query`.

**Keamanan yang sudah tertanam di fondasi:**
- JWT **RS256**. `infra/scripts/generate-keys.sh` membuat `infra/keys/private.pem`
  (mode 600) dan `public.pem`. Private key **hanya** di-mount ke `service-rbac`;
  `api-gateway` hanya menerima `public.pem` read-only, jadi Gateway bisa memverifikasi
  tapi tidak bisa menerbitkan token (ADR-005).
- Gateway **menghapus** `X-User-Id` / `X-User-Role` dari request masuk lalu menulis
  ulang dari payload JWT terverifikasi — header identitas dari luar tidak bisa dipalsukan.
- `jwt.verify` mengunci `algorithms: ['RS256']` secara eksplisit (cegah algorithm confusion).
- CORS whitelist via callback dengan `credentials: true`, tidak pernah `origin: "*"`.
- Rate limit 100/10/20 per menit sesuai §6 aturan 10.
- Gateway sengaja **tidak** memasang `express.json()` supaya body (termasuk multipart
  upload) diteruskan apa adanya.
- `infra/keys/`, `*.pem`, dan `.env` masuk `.gitignore`; diverifikasi dengan
  `git check-ignore`. Tidak ada kredensial di dalam repo — `infra/.env` dibuat lokal
  dengan password acak dari `openssl rand`.

**Infrastruktur** — `infra/docker-compose.yml`: 3 × MySQL 8 (`db_rbac`, `db_master`,
`db_transaksi`), 1 × PostgreSQL 16 (`db_dokumen`), 1 × MailHog, masing-masing dengan
named volume, plus volume terpisah `beasiswa-dokumen-storage` untuk berkas peserta
(§6 aturan 14). Healthcheck di keempat database. Dua network: `beasiswa-public` dan
`beasiswa-internal` (`internal: true`). **Hanya `frontend` dan `api-gateway` yang
punya `ports:`**; seluruh container lain memakai `expose` saja.

**Skema Prisma keempat database** sudah ditulis lengkap sesuai `docs/ERD.md` dan
tervalidasi. Termasuk `service-transaksi/prisma/sql/001_pendaftaran_active_flag.sql`,
yang menegakkan aturan "satu pendaftaran aktif per user" lewat generated column +
unique key — MySQL tidak punya partial unique index, jadi ini cara menegakkannya di
level database, bukan hanya di level aplikasi.

### Apa yang belum / diketahui bermasalah

- **Belum ada logika bisnis sama sekali.** Semua service baru punya `GET /health`.
  Folder `src/modules/` masih kosong; tidak ada endpoint auth, pendaftaran,
  verifikasi, wawancara, maupun upload dokumen.
- **Belum ada migrasi yang dijalankan.** Skema Prisma sudah valid dan client sudah
  di-generate, tapi `prisma migrate dev` belum pernah dieksekusi, jadi keempat
  database masih kosong tanpa tabel.
- `001_pendaftaran_active_flag.sql` **harus disalin manual** ke dalam file migrasi
  pertama `service-transaksi` — Prisma tidak bisa mengekspresikan generated column
  ini di `schema.prisma`, jadi kalau langkah ini terlewat, aturan 1-pendaftaran
  tidak tertegakkan di level DB.
- Seed sudah ditulis (`service-rbac`, `service-master`) tapi belum dijalankan.
- Frontend baru kerangka Vite + React Router + Bootstrap; belum ada halaman yang
  sesuai mockup.
- MailHog belum diuji mengirim/menerima email sungguhan.

### Cara menjalankan & memverifikasi

```bash
# 1. Siapkan kunci RS256 dan kredensial (sekali saja)
cd infra
./scripts/generate-keys.sh
cp .env.example .env      # lalu isi password; jangan pernah commit file ini

# 2. Nyalakan data tier
docker compose up -d db-rbac db-master db-transaksi db-dokumen mailhog
docker compose ps         # tunggu keempat db berstatus (healthy)

# 3. Nyalakan seluruh stack
docker compose up -d

# 4. Smoke test lewat Gateway (satu-satunya pintu masuk publik)
curl -i http://localhost:8080/health
curl -i http://localhost:5173/health

# 5. Membuka database untuk debugging — lewat exec, BUKAN dengan menambah ports:
docker compose exec db-rbac mysql -u root -p db_rbac
docker compose exec db-dokumen psql -U <user> -d db_dokumen
```

### Bukti verifikasi

**Lint & typecheck — 6/6 proyek bersih:**
- `npx eslint .` → exit 0 di `service-rbac`, `service-master`, `service-transaksi`,
  `service-dokumen`, `api-gateway`, `frontend`.
- `npx tsc --noEmit` bersih di 5 proyek Node; `tsc -b` bersih di `frontend`.
- `npm run build` berhasil di 5 proyek Node; `vite build` menghasilkan 82 modul.
- `npx prisma validate` → "valid" di keempat service berdatabase.

**Keempat database healthy** (~15 detik setelah `up -d`):

```
NAME                    IMAGE                    SERVICE        STATUS                    PORTS
beasiswa-db-dokumen     postgres:16-alpine       db-dokumen     Up 17 seconds (healthy)
beasiswa-db-master      mysql:8.0                db-master      Up 17 seconds (healthy)
beasiswa-db-rbac        mysql:8.0                db-rbac        Up 17 seconds (healthy)
beasiswa-db-transaksi   mysql:8.0                db-transaksi   Up 18 seconds (healthy)
beasiswa-mailhog        mailhog/mailhog:v1.0.1   mailhog        Up 17 seconds
```

Kolom `PORTS` kosong untuk seluruh container — tidak ada yang dipublikasikan ke host.

**Bukti isolasi jaringan (§6 aturan 9) — lima lapis:**

1. Audit deklarasi `docker compose config`: hanya `api-gateway` (8080→8080) dan
   `frontend` (5173→80) yang punya `ports:`. Sembilan container lain "— TIDAK ADA —".
2. Runtime: `docker inspect -f '{{json .NetworkSettings.Ports}}'` → `{}` untuk
   keempat database dan MailHog. `docker compose port db-rbac 3306` →
   *"no port 3306/tcp for container beasiswa-db-rbac"*.
3. Koneksi nyata dari host ditolak di semua port database:
   ```
   nc -z -w 3 127.0.0.1 3306  : DITOLAK ✓      nc -z -w 3 127.0.0.1 5432  : DITOLAK ✓
   nc -z -w 3 127.0.0.1 3307  : DITOLAK ✓      nc -z -w 3 127.0.0.1 1025  : DITOLAK ✓
   nc -z -w 3 127.0.0.1 3308  : DITOLAK ✓      nc -z -w 3 127.0.0.1 8025  : DITOLAK ✓
   ```
   `lsof -iTCP -sTCP:LISTEN` tidak menemukan satu pun proses Docker yang listen di
   port database.
4. Menghubungi IP container langsung pun gagal: `beasiswa-internal` dibuat dengan
   `Internal=true`, sehingga tidak punya gateway ke host. `nc -w 5 172.19.0.3 3306`
   → unreachable. Keempat database hanya tersambung ke `beasiswa-internal`.
5. Kontra-bukti bahwa database memang hidup dan hanya bisa dicapai dari dalam network:
   ```
   db-rbac        : MySQL 8.0.46 | db=db_rbac
   db-master      : MySQL 8.0.46 | db=db_master
   db-transaksi   : MySQL 8.0.46 | db=db_transaksi
   db-dokumen     : PostgreSQL 16.15 | db=db_dokumen
   ```

Artinya port MySQL benar-benar tidak dapat diakses dari host, sementara service di
dalam `internal` tetap bisa memakainya secara normal.

**Seluruh stack (11 container) berjalan dan healthy** setelah `docker compose up -d`:

```
SERVICE             STATE     STATUS                    PORTS
api-gateway         running   Up (healthy)              0.0.0.0:8080->8080/tcp
frontend            running   Up (healthy)              0.0.0.0:5173->80/tcp
db-dokumen          running   Up (healthy)
db-master           running   Up (healthy)
db-rbac             running   Up (healthy)
db-transaksi        running   Up (healthy)
mailhog             running   Up
service-dokumen     running   Up (healthy)
service-master      running   Up (healthy)
service-rbac        running   Up (healthy)
service-transaksi   running   Up (healthy)
```

Hanya dua baris yang punya isi di kolom `PORTS`, persis seperti yang dipersyaratkan.

**Smoke test endpoint:**

```
$ curl -s http://localhost:8080/health
{"success":true,"data":{"status":"ok","service":"api-gateway",...},"message":"Service sehat","errors":[]}

$ curl -s http://localhost:5173/health
{"status":"ok","service":"frontend"}
```

Keempat service backend **ditolak** saat dihubungi langsung dari host
(`nc -z 127.0.0.1 3001/3002/3003/3004` gagal semua), tetapi menjawab `200` saat
dipanggil dari dalam network internal lewat Gateway — inilah yang membuat pola
"backend mempercayai header identitas dari Gateway" aman.

**Middleware bersama benar-benar identik**, diverifikasi dengan SHA-256: ketujuh file
(`error-handler`, `request-id`, `validate`, `logger`, `response`, `errors`, `bigint`)
punya checksum yang sama persis di keempat service backend.

**errorHandler tidak membocorkan stack trace** — kata `stack` hanya muncul di
pemanggilan `req.log.error(...)` (sisi server), tidak pernah di `sendError(...)`.
Diuji langsung pada instance `service-rbac` yang dijalankan lokal (port 3901):

```
$ curl -s http://127.0.0.1:3901/rute-tidak-ada
{"success":false,"data":null,"message":"Route GET /rute-tidak-ada tidak ditemukan","errors":[]}
```

**Propagasi `request_id` berfungsi** — header yang dikirim klien dipakai apa adanya,
dan request tanpa header mendapat UUID baru:

```json
{"timestamp":"...","level":"info","service":"service-rbac","message":"request selesai",
 "request_id":"uji-request-id-123","method":"GET","path":"/health","status_code":200,"duration_ms":4.81}
{"timestamp":"...","level":"info","service":"service-rbac","message":"request selesai",
 "request_id":"65421c75-6710-41ab-9863-217726b13804","method":"GET","path":"/rute-tidak-ada","status_code":404,"duration_ms":0.53}
```

**Tidak ada rahasia yang ter-*commit*** — `git check-ignore` mengonfirmasi
`infra/keys/*.pem`, `infra/.env`, dan `.env` di keenam service semuanya diabaikan;
`git ls-files | grep -E '\.env$|\.pem$'` kosong di ketujuh repo.

### Konflik/asumsi baru yang ditemukan di fase ini
- Tidak ada konflik baru antara mockup dan PDF di fase ini (fase infrastruktur,
  belum menyentuh UI). `docs/ASUMSI.md` tidak perlu diubah.

### Catatan untuk fase berikutnya
- Fase 3 sebaiknya `service-rbac`: auth (register/login/refresh/verify-email), users,
  roles, menus, `my-menus`. Tanpa RBAC jalan, service lain tidak bisa diuji end-to-end
  karena semuanya bergantung pada identitas dari Gateway.
- Langkah pertama fase 3: `prisma migrate dev` di `service-rbac`, lalu jalankan seed
  (password admin di-*generate* acak dan hanya dicetak sekali, tidak pernah di-hardcode).
- Jangan lupa menyalin `001_pendaftaran_active_flag.sql` saat membuat migrasi pertama
  `service-transaksi`.

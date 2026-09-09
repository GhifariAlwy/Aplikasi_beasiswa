# Aplikasi Pendaftaran Beasiswa Pelatihan

Demo full-stack microservices untuk pendaftaran beasiswa pelatihan. Stack:
Node.js 20, TypeScript, Express, Prisma, MySQL, PostgreSQL, React 18,
Vite, Bootstrap 5.3, dan Docker Compose.

## Arsitektur

```text
Browser :5173
    |
Frontend (nginx, public)
    |
API Gateway :8080 (public, JWT RS256, CORS, rate limit)
    +--> RBAC :3001 -------- MySQL db_rbac
    +--> Master :3002 ------ MySQL db_master
    +--> Transaksi :3003 --- MySQL db_transaksi
    |        |
    |        +-------------- Dokumen :3004 --- PostgreSQL db_dokumen
    |                         |
    |                         +--------------- named volume dokumen-storage
    +--> Dokumen :3004

Semua service selain frontend dan gateway berada di network internal Docker.
```

## Menjalankan dari nol

Kunci JWT harus dibuat di luar repository.

```bash
cd /Users/mac/beasiswa
cp infra/.env.example infra/.env
# Isi password database acak dan path JWT_PRIVATE_KEY_HOST/JWT_PUBLIC_KEY_HOST.
JWT_KEY_DIR="$HOME/.config/beasiswa" ./infra/scripts/generate-keys.sh
docker compose -f infra/docker-compose.yml --env-file infra/.env up -d --build
./infra/seed-demo.sh
open http://127.0.0.1:5173
```

Jika database baru, script seed/provisioning dapat dijalankan ulang setelah container
sehat. Seed demo bersifat idempoten.

## Akun demo

Password seluruh akun demo: `Password123!`

| Peran | Akun |
|---|---|
| Peserta | `peserta1@demo.beasiswa.local` sampai `peserta5@demo.beasiswa.local` |
| Verifikator | `verifikator@beasiswa.local` |
| Lembaga Seleksi | `lembaga@beasiswa.local` |
| Admin | `admin@beasiswa.local` |

Login peserta memakai channel `PUBLIK`; akun internal memakai channel `INTERNAL`.

## Peta endpoint

| Area | Endpoint utama |
|---|---|
| Auth | `POST /api/auth/register`, `GET /api/auth/verify-email`, `POST /api/auth/login`, `POST /api/auth/refresh`, `GET /api/auth/me` |
| Publik | `GET /api/beasiswa/aktif` |
| Master | CRUD `/api/beasiswa`, CRUD `/api/persyaratan`, `GET /api/beasiswa/:id/persyaratan` |
| Peserta | `POST /api/pendaftaran`, `GET /api/pendaftaran/saya`, `PUT /api/pendaftaran/:id/section/:n`, `POST /api/pendaftaran/:id/submit` |
| Dokumen | `POST /api/dokumen/upload`, `GET /api/dokumen/:uuid`, `DELETE /api/dokumen/:uuid` |
| Verifikasi | `GET /api/verifikasi/antrian`, `GET /api/verifikasi/:id`, `POST /api/verifikasi/:id/keputusan` |
| Wawancara | `GET /api/wawancara/antrian`, `POST /api/wawancara/:id/penilaian` |
| Admin | `GET /api/dashboard/statistik`, `GET /api/hasil-seleksi`, `GET /api/hasil-seleksi/export` |

## Penerapan keamanan dokumen

- Upload memeriksa autentikasi/kepemilikan, ukuran, magic bytes, hook ClamAV,
  UUID filename, SHA-256, lalu metadata.
- PDF/JPEG/PNG ditentukan dari signature biner; ekstensi tidak dipercaya.
- Storage tidak dilayani sebagai static file dan path tidak dapat ditebak.
- Download dan delete selalu melewati otorisasi berdasarkan role/status.
- File disimpan pada named volume `dokumen-storage`.
- Service dokumen dan database tidak memiliki `ports:` ke host.
- Error response tidak mengandung stack trace; input teks disanitasi.

## Keputusan pemangkasan karena tenggat dua hari

- **ClamAV:** hook sudah tersedia dan dikendalikan `CLAMAV_ENABLED`, tetapi default
  nonaktif agar demo tidak menambah dependency daemon dan waktu startup.
- **Kubernetes:** tidak digunakan; Docker Compose cukup untuk demo lokal dan
  mengurangi kompleksitas deployment.
- **CI/CD:** tidak dibuat; validasi dilakukan lokal melalui typecheck, Vitest,
  build image, dan smoke test.
- **E2E browser otomatis:** tidak dibuat penuh karena waktu; alur kritis diuji
  melalui endpoint, seed demo, dan smoke test browser/manual.

## Verifikasi

```bash
cd service-rbac && npm test && npx tsc --noEmit
cd ../service-master && npx tsc --noEmit
cd ../service-transaksi && npm test && npx tsc --noEmit
cd ../service-dokumen && npm test && npx tsc --noEmit
cd ../api-gateway && npx tsc --noEmit
cd ../frontend && npm run build
```

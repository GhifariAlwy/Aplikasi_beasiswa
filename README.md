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
# 🎓 Aplikasi Pendaftaran Beasiswa Pelatihan

Sistem pendaftaran beasiswa berbasis **Microservices** yang dirancang dengan standar keamanan tinggi, skalabilitas, dan pemisahan tanggung jawab yang ketat.

## 📌 Deskripsi Proyek
Aplikasi ini mengelola seluruh alur pendaftaran beasiswa, mulai dari registrasi calon peserta, verifikasi dokumen oleh admin/verifikator, hingga penilaian wawancara oleh lembaga seleksi. Sistem ini dibangun untuk memastikan integritas data, mencegah serangan umum (SQLi, XSS, IDOR), dan memberikan pengalaman pengguna yang mulus.

## 🏗️ Arsitektur Sistem
Aplikasi ini terdiri dari **6 layanan terpisah** yang berkomunikasi melalui API Gateway.

### 🗺️ Peta Repositori
Karena mengikuti standar microservices, setiap layanan memiliki repositori Git sendiri:

| Komponen | Tanggung Jawab | Link Repositori |
| :--- | :--- | :--- |
| **Root (Repo ini)** | Orkestrasi, Infrastruktur, & Dokumentasi | `[Link Repo Root]` |
| **Service RBAC** | Auth (JWT RS256), Manajemen User & Role | `[Link Repo RBAC]` |
| **Service Master** | Manajemen Data Beasiswa & Persyaratan | `[Link Repo Master]` |
| **Service Transaksi** | Alur Pendaftaran, Verifikasi & Wawancara | `[Link Repo Transaksi]` |
| **Service Dokumen** | Penyimpanan File & Scan Antivirus (ClamAV) | `[Link Repo Dokumen]` |
| **API Gateway** | Routing, Rate Limiting & SSL Termination | `[Link Repo Gateway]` |
| **Frontend** | User Interface (React 18 + Bootstrap 5.3) | `[Link Repo Frontend]` |

---

## 🚀 Panduan Menjalankan Proyek (Quick Start)

### 📋 Prasyarat
- Docker & Docker Compose (Terbaru)
- Git

### 🛠️ Langkah Instalasi
1. **Clone Root Repository & Services**
```bash
   # Clone repo utama
   git clone [LINK_REPO_ROOT] beasiswa
   cd beasiswa

   # Clone semua service ke folder masing-masing
   git clone [LINK_REPO_RBAC] service-rbac
   git clone [LINK_REPO_MASTER] service-master
   git clone [LINK_REPO_TRANSAKSI] service-transaksi
   git clone [LINK_REPO_DOKUMEN] service-dokumen
   git clone [LINK_REPO_GATEWAY] api-gateway
   git clone [LINK_REPO_FRONTEND] frontend
```

2. **Konfigurasi Environment**
```bash
   cd infra
   cp .env.example .env
   # Generate kunci JWT RS256 untuk autentikasi
   ./scripts/generate-keys.sh
```

3. **Jalankan Seluruh Stack**
```bash
   docker compose up -d --build
```

4. **Isi Data Demo (Seed)**
```bash
   ./infra/seed-demo.sh
```

### 🌐 Akses Aplikasi
- **Frontend**: [http://localhost:5173](http://localhost:5173)
- **API Gateway**: [http://localhost:8080](http://localhost:8080)
- **MailHog (Cek Email Aktivasi)**: [http://localhost:8025](http://localhost:8025)

---

## 🔐 Fitur Keamanan Unggulan (Security Highlights)
Aplikasi ini mengimplementasikan aturan keamanan ketat sesuai permintaan dokumen:

- **Autentikasi RS256**: Menggunakan *Asymmetric Key*. Hanya `service-rbac` yang memegang *private key* untuk menerbitkan token; Gateway hanya memegang *public key* untuk verifikasi.
- **Isolasi Jaringan (Private VPC)**: Service backend dan database tidak memiliki port terbuka ke host. Akses hanya bisa dilakukan melalui API Gateway.
- **Anti-Malware**: Setiap file yang diunggah dipindai secara *real-time* menggunakan **ClamAV** sebelum disimpan ke storage.
- **Validasi Magic Bytes**: Verifikasi tipe file berdasarkan *binary signature* (bukan ekstensi), mencegah serangan *file spoofing*.
- **Refresh Token Rotation**: Implementasi rotasi token dengan deteksi *reuse* untuk mencegah pembajakan sesi.
- **Anti-IDOR**: Pengecekan kepemilikan data dilakukan langsung di level query database.

## 📁 Struktur Folder Root

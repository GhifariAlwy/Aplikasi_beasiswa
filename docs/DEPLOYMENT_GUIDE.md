# PANDUAN DEPLOYMENT PRODUKSI — Aplikasi Beasiswa Pelatihan

Dokumen ini menjelaskan langkah-langkah untuk memindahkan aplikasi dari mode demo (localhost) ke server produksi agar berfungsi semestinya bagi pengguna publik.

## 1. Persiapan Infrastruktur
- **Server**: VPS atau Cloud Instance (Ubuntu 22.04 direkomendasikan).
- **Spesifikasi Minimum**: 4GB RAM, 2 vCPU, 40GB SSD.
- **Software**: Docker & Docker Compose terbaru terinstal.
- **Domain**: Domain yang sudah diarahkan (A Record) ke IP server (misal: `beasiswa.kampus.ac.id`).

## 2. Konfigurasi Keamanan & SSL
Aplikasi menggunakan Nginx sebagai pintu masuk tunggal dengan SSL Termination.

### A. Generate Sertifikat SSL
Gunakan Let's Encrypt (Certbot) untuk mendapatkan sertifikat gratis:
```bash
sudo apt update
sudo apt install certbot
sudo certbot certonly --standalone -d beasiswa.kampus.ac.id
```
Salin sertifikat ke folder `infra/certs/`:
- `/etc/letsencrypt/live/domain/fullchain.pem` $\to$ `infra/certs/fullchain.pem`
- `/etc/letsencrypt/live/domain/privkey.pem` $\to$ `infra/certs/privkey.pem`

### B. Konfigurasi Environment (`.env`)
Buat file `infra/.env` dengan nilai produksi:
- `MYSQL_ROOT_PASSWORD`: (Password kuat/acak)
- `MYSQL_USER`: `beasiswa_user`
- `MYSQL_PASSWORD`: (Password kuat/acak)
- `POSTGRES_USER`: `beasiswa_pg`
- `POSTGRES_PASSWORD`: (Password kuat/acak)
- `SMTP_HOST`: `smtp.sendgrid.net` (atau provider lain)
- `SMTP_PORT`: 587
- `SMTP_USER`: `apikey`
- `SMTP_PASS`: (API Key provider email)
- `MAIL_FROM`: `no-reply@beasiswa.kampus.ac.id`
- `APP_BASE_URL`: `https://beasiswa.kampus.ac.id`
- `CORS_ORIGINS`: `https://beasiswa.kampus.ac.id`

## 3. Deployment Step-by-Step
1. **Kloning Repo**: Kloning seluruh workspace ke server.
2. **Generate JWT Keys**:
   ```bash
   mkdir -p ~/.config/beasiswa
   ./infra/scripts/generate-keys.sh
   ```
3. **Run Application**:
   ```bash
   cd infra
   docker compose up -d --build
   ```
4. **Seed Data**:
   ```bash
   ./infra/seed-demo.sh
   ```

## 4. Verifikasi Produksi
- **HTTPS**: Akses domain via browser; pastikan gembok hijau muncul.
- **Email**: Coba registrasi akun; cek apakah email aktivasi masuk ke inbox asli.
- **Upload**: Coba upload file `.exe` yang menyamar jadi `.pdf`; pastikan ditolak oleh ClamAV.
- **Isolasi**: Pastikan port 3306, 5432, 3001-3004 tidak bisa diakses dari luar (gunakan `nc -z`).

## 5. Pemeliharaan
- **Backup**: Backup volume `/var/lib/docker/volumes/beasiswa-dokumen-storage` secara rutin.
- **Update**: Jalankan `docker compose pull` dan `docker compose up -d` untuk update image.

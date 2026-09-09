# Audit Keamanan — CLAUDE.md §6

Tanggal audit: 2026-09-09  
Lingkungan: Docker Compose lokal, gateway `http://localhost:8080`, seed demo terpadu.

| Aturan | Status | Bukti kode dan pengujian |
|---|---|---|
| 1. JWT RS256, refresh HttpOnly/Secure/Strict, hashed, rotasi | DIPERBAIKI | Gateway mengunci algoritma `RS256`; RBAC menyimpan hash token. Header login menghasilkan `HttpOnly; Secure; SameSite=Strict`. Pemakaian token lama setelah rotasi menghasilkan `401`. Uji konkurensi dua refresh bersamaan menghasilkan tepat satu `200` dan satu `401`; revokasi dibuat atomik dengan `updateMany(... revokedAt: null)`. |
| 2. Password argon2id | LULUS | `service-rbac/src/utils/password.ts` memakai `@node-rs/argon2`; tidak ada plaintext password pada response/seed. Login akun demo berhasil dengan verifikasi hash. |
| 3. Role tidak dipercaya dari input | LULUS | Login dengan `role: ADMIN` tetapi `channel: PUBLIK` menghasilkan `400` (akun internal wajib melalui channel internal). Header `X-User-Role: ADMIN` pada token peserta tetap menghasilkan `403` untuk dashboard admin. |
| 4. Login publik vs internal | LULUS | Endpoint login menolak akun internal pada channel publik dan endpoint internal memakai channel `INTERNAL`; uji login admin dengan channel publik menghasilkan `400`. |
| 5. Anti SQL injection | LULUS | Repository memakai Prisma; pencarian dengan payload `' OR 1=1 --` menghasilkan response normal `200` dengan daftar kosong, bukan akses tambahan. Grep kode aplikasi: nihil `$queryRaw`, `$queryRawUnsafe`, `queryRawUnsafe`, dan tidak ada konkatenasi query. |
| 6. Anti XSS | LULUS | Sanitizer backend menghapus tag HTML dan karakter kontrol; React tidak memiliki `dangerouslySetInnerHTML`. Payload `<script>alert(1)</script>` pada pencarian tidak dieksekusi dan tidak mengubah hasil. |
| 7. Anti CSRF | LULUS | Access token dikirim melalui `Authorization`; refresh cookie `SameSite=Strict`, dan CORS memakai origin eksplisit dengan credentials. |
| 8. Anti IDOR | LULUS | Peserta A mengakses aplikasi peserta B (`PUT /api/pendaftaran/44/section/1`) menghasilkan `404`. Dokumen lintas peserta menghasilkan `403`. Guard role peserta ke dashboard admin juga `403`. Query repository menyertakan predicate kepemilikan. |
| 9. Isolasi jaringan | LULUS | `docker compose config` menunjukkan hanya gateway `8080` dan frontend `5173` memakai `ports:`. Probe host ke `3001`, `3002`, `3003`, `3004`, `3306`, `5432` semuanya `000`/unreachable. |
| 10. Rate limit | LULUS | Request login ke-12 dalam satu menit menghasilkan `429` dengan pesan generik. Konfigurasi: umum 100, auth 10, upload 20 per menit. |
| 11. CORS whitelist + credentials | LULUS | Preflight dari `http://127.0.0.1:5173` menghasilkan `Access-Control-Allow-Origin` yang sama dan `Access-Control-Allow-Credentials: true`; wildcard tidak digunakan. |
| 12. Upload berurutan dan magic bytes | LULUS | Fake `.pdf` berbasis teks menghasilkan `422`; file kosong menghasilkan `422`; file 5 MB ditolak `413`; nama `../../etc/passwd.pdf` disanitasi menjadi basename aman dan upload valid menghasilkan `201`. Pipeline kode memeriksa ownership, ukuran, magic bytes, hook ClamAV, UUID, lalu hash/metadata. |
| 13. Tidak ada static file storage | LULUS | `GET /storage/permohonan/...` menghasilkan `404 Route ... tidak ditemukan`; dokumen hanya dapat di-stream melalui endpoint UUID terproteksi. |
| 14. Persistent volume | LULUS | Compose mendefinisikan volume untuk tiga MySQL, PostgreSQL, dan storage dokumen; storage tidak dipublish sebagai port/static directory. |
| 15. Secrets via environment/external files | DIPERBAIKI | `infra/keys/private.pem` dan `public.pem` dihapus dari workspace. `infra/generate-jwt-keys.sh` membuat pasangan baru di `${HOME}/.config/beasiswa`; Compose menerima `JWT_PRIVATE_KEY_HOST`/`JWT_PUBLIC_KEY_HOST` dari environment, private key hanya di-mount ke RBAC dan public key ke gateway. |
| 16. Error tidak membocorkan stack trace/framework | LULUS | Error invalid UUID menghasilkan envelope generik `{"message":"Validasi gagal"}` tanpa stack trace, path internal, atau versi framework. Error handler terpusat menyaring detail internal. |

## Perintah verifikasi utama

```bash
cd infra
docker compose --env-file .env config --quiet
docker compose --env-file .env ps
```

Hasil: konfigurasi valid dan seluruh service sehat. Typecheck RBAC setelah perbaikan rotasi juga lulus:

```bash
cd service-rbac
npm run typecheck
```


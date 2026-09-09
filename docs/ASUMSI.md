# Asumsi & Keputusan Desain

Daftar ini mencatat semua hal yang **tidak dijelaskan eksplisit** oleh `CLAUDE.md`,
kedua PDF (`PETUNJUK_TESTING.pdf`, `PETUNJUK_TESTING__1_.pdf`), maupun 10 mockup HTML,
beserta asumsi yang diambil dan alasannya. Nomor `[ASUMSI-xx]` dirujuk dari `ERD.md` dan
`OPENAPI.yaml`.

Prinsip yang dipakai untuk semua keputusan di bawah: **mockup menang atas PDF** (sesuai
instruksi eksplisit di `CLAUDE.md` §1 dan §10), dan bila mockup maupun PDF sama-sama diam,
dipilih opsi paling sederhana yang tetap memenuhi persyaratan keamanan non-negotiable di
§6 CLAUDE.md.

---

## A. Konflik mockup vs PDF

### [ASUMSI-09] Field Data Diri: mockup lebih detail daripada diagram alur PDF
`PETUNJUK_TESTING__1_.pdf` (diagram "Flow Proses") hanya menuliskan field Bagian 1
sebagai: NIK, Nama, TGL Lahir, Alamat, **No. HP, No. HP** (tertulis dua kali — kemungkinan
duplikasi/typo pada diagram), Email — total 6 label.

Mockup `2_index_awal.html` (baris 99-170) dan `4_index_revisi.html` (baris 205-259)
menunjukkan 12 field nyata pada Bagian 1: NIK, Nama Lengkap, Tempat Lahir, Tanggal Lahir,
Jenis Kelamin, Alamat Domisili, Provinsi, Kabupaten/Kota, Kecamatan, Kelurahan, No.
HP/WhatsApp, Email.

**Keputusan:** ikuti mockup. Tabel `pendaftaran_data_diri` di `ERD.md` memakai 12 field
lengkap dari mockup, bukan 6 field dari diagram PDF. Diagram PDF diperlakukan sebagai
ringkasan visual yang disederhanakan untuk komunikasi, bukan spesifikasi field yang
mengikat.

### [ASUMSI-22] Fitur "Unduh Surat Kelulusan" & "Daftar Ulang" di mockup tidak ada padanan di PDF maupun peta endpoint
Mockup `6_index_lulus.html` menampilkan tombol "Unduh Surat Kelulusan (PDF)" dan modal
"Konfirmasi Kehadiran / Daftar Ulang" (field: Status Kesediaan, Catatan Tambahan). Tidak
ada tabel, endpoint (§8 CLAUDE.md), maupun penyebutan proses ini di kedua PDF.

**Keputusan:** kedua fitur ini **tidak diimplementasikan** pada fase ini. §10 CLAUDE.md
eksplisit melarang menambah fitur di luar cakupan ("tidak ada penjadwalan wawancara ...
tidak ada chat, tidak ada pembayaran" — prinsip yang sama diperluas ke fitur lain yang
tidak didukung data model/endpoint resmi). Elemen UI tersebut diperlakukan sebagai
dekorasi/tampilan masa depan, bukan bagian dari cakupan backend saat ini. Tidak ada tabel
tambahan di `ERD.md` maupun endpoint tambahan di `OPENAPI.yaml` untuk kedua fitur ini.
**Ini dicatat sebagai gap yang perlu dikonfirmasi ke product owner** bila fitur ini
ternyata memang diharapkan ada.

### [ASUMSI-21] "Lupa Password?" pada login internal tidak punya endpoint
Mockup `1_index_login.html` (baris 118) punya tautan "Lupa Password?" tapi §8 CLAUDE.md
tidak mendaftarkan endpoint forgot-password/reset-password apa pun.

**Keputusan:** tautan bersifat dekoratif di fase ini, tidak diimplementasikan (sesuai §10,
tidak menambah fitur di luar cakupan). Reset password untuk user internal hanya bisa
dilakukan Admin lewat `PUT /api/users/:id`.

---

## B. Hal yang tidak dijelaskan dokumen maupun mockup

### [ASUMSI-01] Kolom audit `created_at`/`updated_at`
CLAUDE.md §4 tidak mencantumkan kolom timestamp administratif di setiap tabel (kecuali
yang eksplisit seperti `submitted_at`, `created_at` di `pendaftaran`/`audit_status`).
**Keputusan:** semua tabel (kecuali log append-only seperti `audit_status` yang cukup
`created_at`) mendapat `created_at` dan `updated_at` standar. Ini bukan field formulir,
melainkan kebutuhan operasional dasar (debugging, sorting, Prisma default).

### [ASUMSI-02] Kolom `users.nik`
Modal "Daftar Akun Peserta" (`1_index.html` baris 214-244) meminta NIK saat registrasi,
sebelum pendaftaran beasiswa mana pun dibuat. CLAUDE.md §4 tidak mencantumkan `nik` di
tabel `users` (db_rbac) — NIK hanya muncul di `pendaftaran_data_diri` (db_transaksi).

**Keputusan:** tambahkan kolom `nik` (nullable, unique) ke `users` karena field ini nyata
ada di form mockup dan harus disimpan di suatu tempat saat akun dibuat (record
`pendaftaran` belum ada di titik ini). NIK yang diisi ulang di wizard pendaftaran
(`pendaftaran_data_diri.nik`) adalah salinan independen/snapshot, bisa saja berbeda kalau
user salah ketik salah satunya — sistem tidak memvalidasi silang keduanya kecuali diminta
lebih lanjut.

### [ASUMSI-03] Strategi pembuatan `username`
Form registrasi publik (`1_index.html`) tidak meminta user memilih username maupun
password — hanya NIK, Nama, Email ("Username dan password sementara akan dikirimkan ke
email ini").

**Keputusan:** untuk peserta publik, `username` di-generate server dari bagian sebelum
`@` di email, ditambah suffix angka acak bila terjadi bentrok unique constraint. Password
sementara di-generate acak (mis. 12 karakter alfanumerik), di-hash argon2id sebelum
disimpan, dan dikirim ke email user sekali saja (tidak pernah disimpan plaintext, tidak
bisa dilihat ulang lewat API). Untuk user internal (dibuat Admin lewat `POST /api/users`),
Admin mengisi username secara manual (biasanya sama dengan email dinas, seperti contoh
`ahmad@beasiswa.go.id` di `4_index_admin.html` baris 363).

### [ASUMSI-20] Tidak ada endpoint ganti password mandiri
Karena registrasi publik tidak melibatkan user memilih password sendiri, idealnya ada
endpoint "ganti password pertama kali". Namun §8 CLAUDE.md tidak mencantumkan endpoint
semacam itu (hanya `register`, `verify-email`, `login`, `refresh`, dan CRUD `/api/users`
khusus ADMIN).

**Keputusan:** tidak menambah endpoint baru di luar §8 (sesuai §10). User publik login
memakai password sementara yang dikirim email; jika ingin mengganti, alurnya di luar
cakupan fase ini. Dicatat sebagai keterbatasan yang perlu dikonfirmasi bila dianggap
kurang aman untuk produksi.

### [ASUMSI-04] "Ingat Saya" pada login internal
Checkbox "Ingat Saya" (`1_index_login.html` baris 111-117) tidak disebut di model data
maupun aturan keamanan CLAUDE.md.

**Keputusan:** tidak menambah kolom baru. Saat login dengan `remember_me: true`, endpoint
`/api/auth/login` cukup mengeset `refresh_tokens.expires_at` lebih panjang (mis. 30 hari)
dibanding default (mis. 7 hari), memakai kolom yang sudah ada.

### [ASUMSI-24] Dropdown "Masuk Sebagai" pada login internal
Sesuai §6 aturan #3 CLAUDE.md, dropdown ini murni kosmetik. Body request
`POST /api/auth/login` tidak menyertakan field role sama sekali — backend menentukan role
dari `users.role_id` di database. `OPENAPI.yaml` tidak mendefinisikan field role pada
request login untuk memastikan hal ini tidak "tergoda" diimplementasikan oleh developer.

### [ASUMSI-05] Field `beasiswa` yang tidak muncul di modal "Tambah Beasiswa"
Modal "Tambah Beasiswa" (`4_index_admin.html` baris 442-472) hanya punya 3 input: Nama,
Kuota, Metode. Tapi landing page (`1_index.html`) dan modal detailnya menampilkan
`deskripsi`, `persyaratan_khusus`, dan `tanggal_tutup` ("Batas Pendaftaran") sebagai data
yang jelas tersimpan di suatu tempat.

**Keputusan:** semua kolom tetap dipertahankan di `ERD.md` sesuai CLAUDE.md §4 (kode,
deskripsi, persyaratan_khusus, tanggal_buka, tanggal_tutup, dll). Modal "Tambah Beasiswa"
pada mockup dianggap versi simplifikasi visual, bukan spesifikasi lengkap form —
form final di implementasi harus punya field untuk seluruh kolom tabel. Kolom `kode`
di-generate otomatis dari `nama` (slug) karena tidak ada input eksplisit untuknya di mana
pun dalam mockup.

### [ASUMSI-06] Unique constraint `persyaratan (beasiswa_id, nama_dokumen)`
Tidak eksplisit diminta, tapi masuk akal untuk mencegah Admin membuat dua baris
persyaratan dengan nama sama pada satu beasiswa yang sama (mis. dua kali "KTP").

### [ASUMSI-07] Format `kode_pendaftaran`
CLAUDE.md §4 memberi contoh `REG-2026-0001` (4 digit). Mockup menunjukkan dua contoh
berbeda: `REG-2026-8801` (`2_index_verifikator.html`, `3_index_wawancara.html`,
`6_index_lulus.html`) dan `REG-2026-090021` (`3_index_terkirim.html`, `4_index_revisi.html`)
— tidak konsisten jumlah digitnya (data dummy mockup, bukan spesifikasi format).

**Keputusan:** ikuti format eksplisit di CLAUDE.md: `REG-{tahun}-{urutan 4 digit
zero-padded}`, mis. `REG-2026-0001`, `REG-2026-0002`, dst, reset per tahun.

### [ASUMSI-08] Unique constraint parsial "1 pendaftaran aktif per user" di MySQL
§5 CLAUDE.md meminta "unique constraint parsial + pengecekan di service" untuk menegakkan
1 pendaftaran aktif. MySQL (beda dengan PostgreSQL) tidak mendukung `UNIQUE INDEX ... WHERE
kondisi`.

**Keputusan:** tambah kolom generated `active_flag` pada `pendaftaran` (bernilai `1` jika
status bukan status gagal final, `NULL` jika sudah `DITOLAK_ADMIN`/`TIDAK_LULUS_WAWANCARA`),
lalu buat `UNIQUE (user_id, active_flag)`. MySQL mengizinkan banyak baris dengan nilai
`NULL` pada unique index, sehingga constraint ini efektif hanya membatasi satu baris
"aktif" per user, sambil tetap mengizinkan riwayat pendaftaran gagal yang tak terbatas.
Pengecekan aturan yang sama tetap diulang di level service sebagai lapisan kedua (defense
in depth), sesuai instruksi CLAUDE.md.

### [ASUMSI-10] Index `nik` di `pendaftaran_data_diri` bersifat non-unique
Karena satu NIK secara sah bisa muncul di lebih dari satu baris riwayat pendaftaran
(misalnya: mendaftar program A → `DITOLAK_ADMIN` → mendaftar ulang program B), NIK tidak
dibuat unique di tabel transaksional ini (berbeda dengan `users.nik` yang unique per akun).

### [ASUMSI-11] Reupload dokumen saat revisi meng-*update* baris yang sama
Mockup (`4_index_revisi.html` baris 293-313) menampilkan ulang input file kosong pada
persyaratan yang direvisi, dengan catatan verifikator di bawahnya — tidak menunjukkan
riwayat file lama tetap tampil berdampingan.

**Keputusan:** `pendaftaran_dokumen` punya unique constraint `(pendaftaran_id,
persyaratan_id)` — upload ulang meng-*update* baris (ganti `dokumen_uuid`), bukan insert
baris baru. File fisik lama di `db_dokumen` tidak dihapus otomatis (untuk jejak audit),
hanya tidak lagi dirujuk oleh `pendaftaran_dokumen`.

### [ASUMSI-12] Satu checkbox mewakili dua kolom persetujuan
Mockup pendaftaran hanya punya satu checkbox gabungan (`checkSah`), sedangkan CLAUDE.md
§4 mendefinisikan dua kolom: `setuju_keabsahan` dan `setuju_ketentuan`.

**Keputusan:** kedua kolom dipertahankan (karena eksplisit ditulis CLAUDE.md, bukan
field yang boleh dihilangkan begitu saja), tapi backend mengisi keduanya sekaligus
`true` dari satu checkbox yang sama pada saat submit. Tidak ada dua checkbox terpisah
di form yang akan dibangun.

### [ASUMSI-13] Tidak ada unique constraint per `persyaratan_id` di `db_dokumen.dokumen`
Service Dokumen menyimpan setiap file yang pernah diunggah apa adanya (termasuk versi
lama yang sudah digantikan saat revisi), karena service ini tidak memahami konsep
"pendaftaran aktif" — konsep itu murni milik Service Transaksi. Keunikan "dokumen mana
yang berlaku saat ini" ditegakkan di `pendaftaran_dokumen` (lihat ASUMSI-11), bukan di
`db_dokumen`.

---

## C. Asumsi terkait `OPENAPI.yaml`

### [ASUMSI-14] Status code `DELETE` = 200, bukan 204
Karena §7 CLAUDE.md mewajibkan response envelope `{success, data, message, errors}` di
**semua** service, endpoint `DELETE` tidak bisa mengembalikan `204 No Content` (tidak
punya body). Semua `DELETE` di `OPENAPI.yaml` mengembalikan `200 OK` dengan
`data: null` dan `message` deskriptif.

### [ASUMSI-15] Dua endpoint dikecualikan dari envelope JSON
`GET /api/dokumen/:uuid` (stream file biner) dan `GET /api/hasil-seleksi/export` (file
Excel) tidak mungkin dibungkus `{success, data, ...}` karena keduanya me-return file
mentah dengan `Content-Type` berbeda (`application/octet-stream`/mime asli dan
`application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`). Response error pada
kedua endpoint ini (mis. 403/404) tetap memakai envelope JSON standar.

### [ASUMSI-16] Parameter `:id` pada endpoint verifikasi & wawancara merujuk `pendaftaran_id`
`GET /api/verifikasi/antrian` dan `GET /api/wawancara/antrian` menampilkan **daftar
pendaftaran** yang perlu diproses (bukan daftar record `verifikasi`/`wawancara`). Maka
`GET /api/verifikasi/:id`, `POST /api/verifikasi/:id/keputusan`, dan
`POST /api/wawancara/:id/penilaian` diasumsikan memakai `:id` = `pendaftaran.id`,
konsisten dengan apa yang diklik user di tabel antrian pada `2_index_verifikator.html`
dan `3_index_wawancara.html`. Endpoint ini menciptakan baris baru di `verifikasi`/
`wawancara` (atau meng-update untuk wawancara, lihat ASUMSI-11 relatif untuk wawancara)
secara internal.

### [ASUMSI-17] Pemisahan upload file vs simpan section 3
`POST /api/dokumen/upload` (Service Dokumen, menerima `multipart/form-data`) dipanggil
lebih dulu per file untuk mendapatkan `dokumen_uuid`. Baru kemudian
`PUT /api/pendaftaran/:id/section/3` (Service Transaksi) dipanggil dengan body berisi
daftar pasangan `{persyaratan_id, dokumen_uuid}` untuk mencatat tautannya di
`pendaftaran_dokumen`. Ini dipilih karena upload file besar sebaiknya langsung menyentuh
service yang relevan (Dokumen), bukan lewat body JSON section milik Transaksi.

### [ASUMSI-18] Body `submit` membawa data persetujuan
Karena §8 tidak punya endpoint `PUT .../section/4` terpisah untuk Bagian 4 (Persetujuan),
`POST /api/pendaftaran/:id/submit` sekaligus menerima `setuju_keabsahan` dan
`setuju_ketentuan` di body-nya, lalu memvalidasi kelengkapan seluruh section sebelum
transisi status `DRAFT`/`REVISI` → `DIAJUKAN`.

### [ASUMSI-19] Konvensi paginasi
CLAUDE.md tidak menetapkan pola paginasi. Semua endpoint `GET` berbentuk daftar (users,
roles, menus, beasiswa, persyaratan, verifikasi/antrian, wawancara/antrian) memakai query
param `page` (default 1) dan `limit` (default 10, maks 100), dengan `data.items[]` +
`data.pagination {page, limit, total, total_pages}` di response — pola REST umum yang
konsisten dengan gaya `snake_case` CLAUDE.md.

### [ASUMSI-23] `GET /health` ditambahkan meski di luar daftar eksplisit §8
§7 CLAUDE.md mewajibkan setiap service punya `GET /health`. Endpoint ini ditambahkan di
`OPENAPI.yaml` sebagai pelengkap (bukan bagian dari 8 kelompok endpoint utama), tanpa
autentikasi, mengembalikan status service secara sederhana.

### [ASUMSI-25] Cara `POST /api/auth/login` membedakan login publik vs internal
§6 aturan #4 CLAUDE.md menyatakan "Endpoint login sama, tapi login internal menolak
`CALON_PESERTA` dan login publik menolak role internal" — tapi tidak dijelaskan bagaimana
satu endpoint yang sama tahu konteks mana yang berlaku untuk satu request tertentu.

**Keputusan:** body request `POST /api/auth/login` menyertakan field wajib
`channel: "PUBLIK" | "INTERNAL"`, diisi otomatis oleh frontend sesuai halaman asal
(`1_index.html` mengirim `PUBLIK`, `1_index_login.html` mengirim `INTERNAL`). Backend
memvalidasi role user hasil lookup password terhadap `channel` ini — bukan dari dropdown
"Masuk Sebagai" yang murni kosmetik (lihat [ASUMSI-24]). Field ini murni penentu *daftar
role yang diizinkan lewat channel tersebut*, bukan role yang diklaim user.

---

## Ringkasan Konflik Mockup vs PDF

| # | Topik | PDF | Mockup | Keputusan |
|---|---|---|---|---|
| 1 | Field Bagian 1 (Data Diri) | 6 field (termasuk 1 duplikat "No. HP") | 12 field lengkap (+ tempat lahir, jenis kelamin, provinsi/kab/kec/kel) | Ikuti mockup — lihat [ASUMSI-09] |
| 2 | Surat Kelulusan PDF & Daftar Ulang | Tidak disebut sama sekali | Ada tombol/modal di `6_index_lulus.html` | Tidak diimplementasikan, di luar cakupan §8 — lihat [ASUMSI-22] |
| 3 | Lupa Password | Tidak disebut | Ada tautan di `1_index_login.html` | Dekoratif, tidak diimplementasikan — lihat [ASUMSI-21] |

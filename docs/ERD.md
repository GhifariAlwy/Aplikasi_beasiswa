# ERD — Aplikasi Pendaftaran Beasiswa Pelatihan

Sumber: `CLAUDE.md` §4 (model data dasar) diperkaya dan diverifikasi field-per-field
terhadap mockup `docs/mockup/2_index_awal.html` (wizard pendaftaran) dan
`docs/mockup/4_index_revisi.html` (wizard mode revisi), serta mockup lain yang relevan
(`1_index.html`, `1_index_login.html`, `2_index_verifikator.html`, `3_index_wawancara.html`,
`4_index_admin.html`, `6_index_lulus.html`). Konflik mockup vs PDF dan keputusan desain
yang tidak eksplisit didokumentasikan di `docs/ASUMSI.md` — rujukan `[ASUMSI-xx]`
mengarah ke nomor butir di file tersebut.

Konvensi:
- Semua tabel MySQL pakai `id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY` kecuali disebut lain.
- Semua tabel (kecuali tabel log append-only) punya `created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP`
  dan `updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP`. Ini kolom
  audit standar, bukan field formulir — lihat `[ASUMSI-01]`.
- FK sungguhan hanya dibuat **di dalam database yang sama**. Kolom yang menunjuk ke service
  lain (mis. `user_id` di db_transaksi menunjuk ke db_rbac) ditandai **(ref lintas-service, no FK)**
  sesuai ADR-003 (tanpa FK lintas service, wajib divalidasi di level aplikasi).
- Timestamp disimpan UTC (§7 CLAUDE.md).

---

## 1. db_rbac (MySQL)

### 1.1 `roles`

| Kolom | Tipe | Nullable | Keterangan |
|---|---|---|---|
| id | BIGINT UNSIGNED | NOT NULL | PK |
| kode | VARCHAR(30) | NOT NULL | `CALON_PESERTA`\|`VERIFIKATOR`\|`LEMBAGA_SELEKSI`\|`ADMIN` |
| nama | VARCHAR(100) | NOT NULL | Nama tampilan role, mis. "Verifikator" |
| created_at, updated_at | DATETIME | NOT NULL | |

- **UNIQUE** `uq_roles_kode (kode)`
- Index: PK saja diperlukan (tabel kecil, statis)

### 1.2 `users`

| Kolom | Tipe | Nullable | Keterangan |
|---|---|---|---|
| id | BIGINT UNSIGNED | NOT NULL | PK |
| nik | VARCHAR(16) | NULL | Diisi saat registrasi publik (modal "Daftar Akun" di `1_index.html`). NULL untuk user internal yang dibuat via CRUD Admin. `[ASUMSI-02]` |
| nama | VARCHAR(150) | NOT NULL | |
| username | VARCHAR(50) | NOT NULL | `[ASUMSI-03]` (strategi generate untuk peserta publik) |
| email | VARCHAR(150) | NOT NULL | |
| password_hash | VARCHAR(255) | NOT NULL | argon2id |
| role_id | BIGINT UNSIGNED | NOT NULL | FK → `roles.id` |
| is_email_verified | BOOLEAN | NOT NULL | DEFAULT false |
| is_active | BOOLEAN | NOT NULL | DEFAULT true |
| last_login_at | DATETIME | NULL | |
| created_at, updated_at | DATETIME | NOT NULL | |

- **UNIQUE** `uq_users_username (username)`
- **UNIQUE** `uq_users_email (email)`
- **UNIQUE** `uq_users_nik (nik)` — unique index MySQL mengizinkan banyak NULL, jadi tidak mengganggu user internal tanpa NIK
- Index: `idx_users_role_id (role_id)`
- FK: `role_id → roles.id` (RESTRICT)

### 1.3 `menus`

| Kolom | Tipe | Nullable | Keterangan |
|---|---|---|---|
| id | BIGINT UNSIGNED | NOT NULL | PK |
| parent_id | BIGINT UNSIGNED | NULL | FK self → `menus.id`, untuk submenu |
| nama | VARCHAR(100) | NOT NULL | |
| path | VARCHAR(150) | NOT NULL | mis. `/wawancara` |
| icon | VARCHAR(50) | NULL | class bootstrap-icons, mis. `bi-chat-square-text` |
| urutan | INT UNSIGNED | NOT NULL | DEFAULT 0 |
| is_active | BOOLEAN | NOT NULL | DEFAULT true |
| created_at, updated_at | DATETIME | NOT NULL | |

- Index: `idx_menus_parent_id (parent_id)`, `idx_menus_urutan (urutan)`
- FK: `parent_id → menus.id` (SET NULL on delete)

### 1.4 `role_menu_access`

| Kolom | Tipe | Nullable | Keterangan |
|---|---|---|---|
| id | BIGINT UNSIGNED | NOT NULL | PK |
| role_id | BIGINT UNSIGNED | NOT NULL | FK → `roles.id` |
| menu_id | BIGINT UNSIGNED | NOT NULL | FK → `menus.id` |
| can_view | BOOLEAN | NOT NULL | DEFAULT false |
| can_create | BOOLEAN | NOT NULL | DEFAULT false |
| can_update | BOOLEAN | NOT NULL | DEFAULT false |
| can_delete | BOOLEAN | NOT NULL | DEFAULT false |
| created_at, updated_at | DATETIME | NOT NULL | |

- **UNIQUE** `uq_role_menu (role_id, menu_id)` — satu baris akses per kombinasi role+menu
- FK: `role_id → roles.id` (CASCADE), `menu_id → menus.id` (CASCADE)

### 1.5 `refresh_tokens`

| Kolom | Tipe | Nullable | Keterangan |
|---|---|---|---|
| id | BIGINT UNSIGNED | NOT NULL | PK |
| user_id | BIGINT UNSIGNED | NOT NULL | FK → `users.id` |
| token_hash | VARCHAR(255) | NOT NULL | hash token, bukan token mentah |
| expires_at | DATETIME | NOT NULL | Diperpanjang jika "Ingat Saya" dicentang saat login internal `[ASUMSI-04]` |
| revoked_at | DATETIME | NULL | diisi saat rotasi/logout |
| created_at | DATETIME | NOT NULL | |

- Index: `idx_refresh_tokens_user_id (user_id)`, `idx_refresh_tokens_expires_at (expires_at)`
- FK: `user_id → users.id` (CASCADE)

### 1.6 `email_verifications`

| Kolom | Tipe | Nullable | Keterangan |
|---|---|---|---|
| id | BIGINT UNSIGNED | NOT NULL | PK |
| user_id | BIGINT UNSIGNED | NOT NULL | FK → `users.id` |
| token_hash | VARCHAR(255) | NOT NULL | |
| expires_at | DATETIME | NOT NULL | |
| used_at | DATETIME | NULL | |
| created_at | DATETIME | NOT NULL | |

- Index: `idx_email_verifications_user_id (user_id)`
- FK: `user_id → users.id` (CASCADE)

---

## 2. db_master (MySQL)

### 2.1 `beasiswa`

Field diverifikasi gabungan dari `1_index.html` (kartu program + modal detail: nama,
deskripsi, batas pendaftaran, metode, kuota, persyaratan khusus) dan `4_index_admin.html`
(modal "Tambah Beasiswa": nama, kuota, metode saja — field lain tetap ada di tabel karena
dipakai di layar lain, lihat `[ASUMSI-05]`).

| Kolom | Tipe | Nullable | Keterangan |
|---|---|---|---|
| id | BIGINT UNSIGNED | NOT NULL | PK |
| kode | VARCHAR(30) | NOT NULL | Auto-generate dari nama (slug), tidak ada input eksplisit di mockup `[ASUMSI-05]` |
| nama | VARCHAR(150) | NOT NULL | mis. "Pelatihan Web Developer Specialist" |
| deskripsi | TEXT | NULL | ditampilkan di modal detail landing page |
| persyaratan_khusus | TEXT | NULL | bullet list persyaratan khusus (disimpan sebagai teks multi-baris) |
| kuota | INT UNSIGNED | NOT NULL | |
| metode | ENUM('DARING','HYBRID','LURING') | NOT NULL | dari opsi "Daring (Online)/Hybrid/Luring (Offline)" |
| tanggal_buka | DATE | NOT NULL | |
| tanggal_tutup | DATE | NOT NULL | "Batas Pendaftaran" di kartu program |
| status | ENUM('AKTIF','NONAKTIF','DITUTUP') | NOT NULL | DEFAULT 'AKTIF' |
| deleted_at | DATETIME | NULL | soft delete |
| created_at, updated_at | DATETIME | NOT NULL | |

- **UNIQUE** `uq_beasiswa_kode (kode)`
- Index: `idx_beasiswa_status (status)`, `idx_beasiswa_tanggal_tutup (tanggal_tutup)`

### 2.2 `persyaratan`

Field diambil dari `4_index_admin.html` tabel "Master Data Persyaratan Dokumen": Nama
Dokumen, Format Allowed, Max Size, Mandatory. Kolom `urutan` dipertahankan dari CLAUDE.md
karena urutan tampil dokumen di wizard (KTP → KK → Ijazah → Surat Rekomendasi) bersifat tetap.

| Kolom | Tipe | Nullable | Keterangan |
|---|---|---|---|
| id | BIGINT UNSIGNED | NOT NULL | PK |
| beasiswa_id | BIGINT UNSIGNED | NOT NULL | FK → `beasiswa.id` |
| nama_dokumen | VARCHAR(150) | NOT NULL | mis. "KTP (Kartu Tanda Penduduk)" |
| format_allowed | VARCHAR(100) | NOT NULL | csv, mis. `pdf,jpg,png` |
| max_size_kb | INT UNSIGNED | NOT NULL | DEFAULT 2048 (2MB sesuai mockup) |
| is_mandatory | BOOLEAN | NOT NULL | DEFAULT true |
| urutan | INT UNSIGNED | NOT NULL | DEFAULT 0 |
| created_at, updated_at | DATETIME | NOT NULL | |

- Index: `idx_persyaratan_beasiswa_id (beasiswa_id)`
- **UNIQUE** `uq_persyaratan_nama (beasiswa_id, nama_dokumen)` `[ASUMSI-06]`
- FK: `beasiswa_id → beasiswa.id` (CASCADE)

---

## 3. db_transaksi (MySQL)

### 3.1 `pendaftaran`

| Kolom | Tipe | Nullable | Keterangan |
|---|---|---|---|
| id | BIGINT UNSIGNED | NOT NULL | PK |
| kode_pendaftaran | VARCHAR(20) | NOT NULL | Format `REG-YYYY-NNNN` `[ASUMSI-07]` |
| user_id | BIGINT UNSIGNED | NOT NULL | (ref lintas-service ke db_rbac.users, no FK) |
| beasiswa_id | BIGINT UNSIGNED | NOT NULL | (ref lintas-service ke db_master.beasiswa, no FK) |
| beasiswa_snapshot | JSON | NOT NULL | salinan data beasiswa saat pendaftaran dibuat (ADR-003) |
| status | ENUM('DRAFT','DIAJUKAN','LOLOS_ADMIN','DITOLAK_ADMIN','REVISI','LULUS_WAWANCARA','TIDAK_LULUS_WAWANCARA') | NOT NULL | DEFAULT 'DRAFT' |
| section_terakhir | TINYINT UNSIGNED | NOT NULL | DEFAULT 1, section wizard (1-3) terakhir yang tersimpan |
| jumlah_revisi | INT UNSIGNED | NOT NULL | DEFAULT 0 |
| submitted_at | DATETIME | NULL | |
| active_flag | TINYINT UNSIGNED GENERATED ALWAYS AS (CASE WHEN status NOT IN ('DITOLAK_ADMIN','TIDAK_LULUS_WAWANCARA') THEN 1 ELSE NULL END) STORED | NULL | Kolom bantu untuk unique constraint parsial, lihat catatan di bawah |
| created_at, updated_at | DATETIME | NOT NULL | |

- **UNIQUE** `uq_pendaftaran_kode (kode_pendaftaran)`
- **UNIQUE** `uq_pendaftaran_user_aktif (user_id, active_flag)` — MySQL tidak mendukung
  partial index bergaya Postgres (`WHERE`), jadi aturan "1 pendaftaran aktif per user"
  (§5 CLAUDE.md) ditegakkan lewat **generated column** `active_flag`: bernilai `1` selama
  status bukan status gagal final, dan `NULL` setelah `DITOLAK_ADMIN`/`TIDAK_LULUS_WAWANCARA`.
  MySQL unique index mengizinkan banyak baris `NULL`, tapi hanya satu baris `(user_id, 1)`
  — sehingga user boleh mendaftar ulang program lain hanya setelah pendaftaran lamanya
  berstatus gagal final. `[ASUMSI-08]`
- Index: `idx_pendaftaran_user_id (user_id)`, `idx_pendaftaran_beasiswa_id (beasiswa_id)`, `idx_pendaftaran_status (status)`

### 3.2 `pendaftaran_data_diri`

Field diekstrak **persis** dari Bagian 1 mockup `2_index_awal.html` (baris 99-170) dan
dikonfirmasi ulang di `4_index_revisi.html` (baris 205-259): NIK, Nama Lengkap, Tempat
Lahir, Tanggal Lahir, Jenis Kelamin, Alamat Domisili, Provinsi, Kabupaten/Kota, Kecamatan,
Kelurahan, No. HP/WhatsApp, Email. Ini lebih detail dari diagram alur PDF — lihat
`[ASUMSI-09]` (konflik mockup vs PDF).

| Kolom | Tipe | Nullable | Keterangan |
|---|---|---|---|
| pendaftaran_id | BIGINT UNSIGNED | NOT NULL | PK, FK → `pendaftaran.id` (relasi 1-1) |
| nik | VARCHAR(16) | NOT NULL | |
| nama_lengkap | VARCHAR(150) | NOT NULL | |
| tempat_lahir | VARCHAR(100) | NOT NULL | |
| tanggal_lahir | DATE | NOT NULL | |
| jenis_kelamin | ENUM('L','P') | NOT NULL | sesuai `value="L"/"P"` di mockup |
| alamat_domisili | TEXT | NOT NULL | |
| provinsi | VARCHAR(100) | NOT NULL | |
| kabupaten_kota | VARCHAR(100) | NOT NULL | |
| kecamatan | VARCHAR(100) | NOT NULL | |
| kelurahan | VARCHAR(100) | NOT NULL | |
| no_hp | VARCHAR(20) | NOT NULL | |
| email | VARCHAR(150) | NOT NULL | |
| created_at, updated_at | DATETIME | NOT NULL | |

- Index: `idx_data_diri_nik (nik)` (non-unique — NIK boleh berulang lintas pendaftaran historis berbeda, lihat `[ASUMSI-10]`)
- FK: `pendaftaran_id → pendaftaran.id` (CASCADE)

### 3.3 `pendaftaran_pendidikan`

Field dari Bagian 2 mockup (baris 173-199 `2_index_awal.html`): Pendidikan Terakhir, Nama
Instansi/Sekolah/Universitas, Jurusan/Program Studi, Pekerjaan Saat Ini.

| Kolom | Tipe | Nullable | Keterangan |
|---|---|---|---|
| pendaftaran_id | BIGINT UNSIGNED | NOT NULL | PK, FK → `pendaftaran.id` (relasi 1-1) |
| pendidikan_terakhir | ENUM('SMA_SMK','D3_D4','S1','S2_S3') | NOT NULL | dari opsi select mockup |
| nama_instansi | VARCHAR(200) | NOT NULL | |
| jurusan | VARCHAR(150) | NOT NULL | |
| pekerjaan | VARCHAR(150) | NOT NULL | free text, mis. "Belum Bekerja"/"Software Developer" |
| created_at, updated_at | DATETIME | NOT NULL | |

- FK: `pendaftaran_id → pendaftaran.id` (CASCADE)

### 3.4 `pendaftaran_dokumen`

Merepresentasikan Bagian 3 mockup (4 dokumen: KTP, KK, Ijazah, Surat Rekomendasi — jumlah
dan jenisnya dinamis mengikuti `persyaratan` milik beasiswa terkait).

| Kolom | Tipe | Nullable | Keterangan |
|---|---|---|---|
| id | BIGINT UNSIGNED | NOT NULL | PK |
| pendaftaran_id | BIGINT UNSIGNED | NOT NULL | FK → `pendaftaran.id` |
| persyaratan_id | BIGINT UNSIGNED | NOT NULL | (ref lintas-service ke db_master.persyaratan, no FK) |
| dokumen_uuid | CHAR(36) | NOT NULL | (ref lintas-service ke db_dokumen.dokumen.id, no FK) |
| nama_dokumen | VARCHAR(150) | NOT NULL | nama file asli, mis. "ktp_yosep.jpg" (untuk tampilan cepat tanpa join ke db_dokumen) |
| created_at, updated_at | DATETIME | NOT NULL | |

- **UNIQUE** `uq_dokumen_pendaftaran_persyaratan (pendaftaran_id, persyaratan_id)` — upload
  ulang saat revisi meng-*update* baris ini (bukan menambah baris baru) `[ASUMSI-11]`
- Index: `idx_pendaftaran_dokumen_pendaftaran_id (pendaftaran_id)`
- FK: `pendaftaran_id → pendaftaran.id` (CASCADE)

### 3.5 `pendaftaran_persetujuan`

Mockup `2_index_awal.html` Bagian 4 (baris 227-238) hanya menampilkan **satu** checkbox
gabungan ("Saya menyatakan ... benar, sah ... Apabila di kemudian hari ditemukan
kebohongan..."). CLAUDE.md §4 mendefinisikan dua kolom boolean (`setuju_keabsahan`,
`setuju_ketentuan`). Kedua kolom dipertahankan sesuai CLAUDE.md (final, bukan mockup-field
yang perlu dihapus), tapi keduanya diisi bersamaan dari satu checkbox yang sama —
lihat `[ASUMSI-12]`.

| Kolom | Tipe | Nullable | Keterangan |
|---|---|---|---|
| pendaftaran_id | BIGINT UNSIGNED | NOT NULL | PK, FK → `pendaftaran.id` (relasi 1-1) |
| setuju_keabsahan | BOOLEAN | NOT NULL | DEFAULT false |
| setuju_ketentuan | BOOLEAN | NOT NULL | DEFAULT false |
| disetujui_at | DATETIME | NULL | |
| created_at, updated_at | DATETIME | NOT NULL | |

- FK: `pendaftaran_id → pendaftaran.id` (CASCADE)

### 3.6 `verifikasi`

Setiap kali Verifikator menekan "Submit Keputusan Verifikasi" (`2_index_verifikator.html`
baris 487-489) tercipta satu baris baru (histori per siklus, termasuk siklus setelah revisi).

| Kolom | Tipe | Nullable | Keterangan |
|---|---|---|---|
| id | BIGINT UNSIGNED | NOT NULL | PK |
| pendaftaran_id | BIGINT UNSIGNED | NOT NULL | FK → `pendaftaran.id` |
| verifikator_id | BIGINT UNSIGNED | NOT NULL | (ref lintas-service ke db_rbac.users, no FK) |
| keputusan | ENUM('DISETUJUI','DITOLAK','REVISI') | NOT NULL | dari opsi select mockup |
| catatan_umum | TEXT | NULL | wajib diisi FE saat REVISI/DITOLAK (§5 CLAUDE.md), nullable di DB |
| created_at | DATETIME | NOT NULL | |

- Index: `idx_verifikasi_pendaftaran_id (pendaftaran_id)`
- FK: `pendaftaran_id → pendaftaran.id` (CASCADE)

### 3.7 `verifikasi_checklist`

Field dari tabel checklist per dokumen di `2_index_verifikator.html` (baris 328-432):
kolom "Kesesuaian Data" (radio Sesuai/Ditolak) dan "Catatan Perbaikan Verifikator".

| Kolom | Tipe | Nullable | Keterangan |
|---|---|---|---|
| id | BIGINT UNSIGNED | NOT NULL | PK |
| verifikasi_id | BIGINT UNSIGNED | NOT NULL | FK → `verifikasi.id` |
| persyaratan_id | BIGINT UNSIGNED | NOT NULL | (ref lintas-service ke db_master.persyaratan, no FK) |
| is_sesuai | BOOLEAN | NOT NULL | true = "Sesuai", false = "Ditolak" |
| catatan_perbaikan | VARCHAR(500) | NULL | ditampilkan ke peserta di mode revisi (`4_index_revisi.html` baris 306) |
| created_at | DATETIME | NOT NULL | |

- **UNIQUE** `uq_checklist_verifikasi_persyaratan (verifikasi_id, persyaratan_id)`
- FK: `verifikasi_id → verifikasi.id` (CASCADE)

### 3.8 `wawancara`

Field dari `3_index_wawancara.html` (baris 244-288): 3 skor input + nilai akhir
kalkulasi otomatis + status kelulusan + catatan evaluasi. Tombol "Edit Nilai" pada baris
182-185 menandakan baris ini di-*update* di tempat, bukan insert baru per percobaan.

| Kolom | Tipe | Nullable | Keterangan |
|---|---|---|---|
| id | BIGINT UNSIGNED | NOT NULL | PK |
| pendaftaran_id | BIGINT UNSIGNED | NOT NULL | FK → `pendaftaran.id` |
| penilai_id | BIGINT UNSIGNED | NOT NULL | (ref lintas-service ke db_rbac.users, no FK) |
| nilai_komunikasi | DECIMAL(5,2) | NOT NULL | skala 0-100, bobot 30% |
| nilai_teknis | DECIMAL(5,2) | NOT NULL | skala 0-100, bobot 40% |
| nilai_komitmen | DECIMAL(5,2) | NOT NULL | skala 0-100, bobot 30% |
| nilai_akhir | DECIMAL(5,2) | NOT NULL | dihitung server: `komunikasi*0.3 + teknis*0.4 + komitmen*0.3` |
| status | ENUM('LULUS','TIDAK_LULUS') | NOT NULL | |
| catatan_evaluasi | TEXT | NOT NULL | |
| created_at, updated_at | DATETIME | NOT NULL | |

- **UNIQUE** `uq_wawancara_pendaftaran (pendaftaran_id)` — satu penilaian per pendaftaran, boleh di-update
- FK: `pendaftaran_id → pendaftaran.id` (CASCADE)

### 3.9 `audit_status`

Log append-only setiap transisi status (§5 CLAUDE.md — wajib ditulis oleh `assertTransition`).

| Kolom | Tipe | Nullable | Keterangan |
|---|---|---|---|
| id | BIGINT UNSIGNED | NOT NULL | PK |
| pendaftaran_id | BIGINT UNSIGNED | NOT NULL | FK → `pendaftaran.id` |
| status_lama | VARCHAR(30) | NOT NULL | |
| status_baru | VARCHAR(30) | NOT NULL | |
| actor_id | BIGINT UNSIGNED | NOT NULL | (ref lintas-service ke db_rbac.users, no FK) |
| actor_role | VARCHAR(30) | NOT NULL | snapshot kode role pelaku saat transisi |
| catatan | TEXT | NULL | |
| created_at | DATETIME | NOT NULL | (tidak ada `updated_at` — log tidak pernah diubah) |

- Index: `idx_audit_status_pendaftaran_id (pendaftaran_id)`
- FK: `pendaftaran_id → pendaftaran.id` (CASCADE)

---

## 4. db_dokumen (PostgreSQL)

### 4.1 `dokumen`

| Kolom | Tipe | Nullable | Keterangan |
|---|---|---|---|
| id | UUID | NOT NULL | PK, `DEFAULT gen_random_uuid()` |
| kode_pendaftaran | VARCHAR(20) | NOT NULL | (ref lintas-service ke db_transaksi.pendaftaran, no FK) — dipakai untuk struktur folder `/storage/permohonan/{kode_pendaftaran}/` |
| persyaratan_id | BIGINT | NOT NULL | (ref lintas-service ke db_master.persyaratan, no FK) |
| nama_file_asli | VARCHAR(255) | NOT NULL | nama asli dari user, hanya disimpan sebagai metadata (tidak dipakai sebagai nama fisik) |
| nama_file_simpan | VARCHAR(255) | NOT NULL | `{uuid}_{jenis}.ext`, sesuai §6.12 CLAUDE.md |
| path | VARCHAR(500) | NOT NULL | `/storage/permohonan/{kode_pendaftaran}/{nama_file_simpan}` |
| mime_terdeteksi | VARCHAR(100) | NOT NULL | hasil deteksi magic bytes, bukan dari header/ekstensi upload |
| ukuran_byte | INTEGER | NOT NULL | |
| sha256 | CHAR(64) | NOT NULL | |
| status_scan | VARCHAR(20) | NOT NULL | `PENDING`\|`CLEAN`\|`INFECTED`\|`SKIPPED` (`SKIPPED` dipakai jika ClamAV opsional tidak diaktifkan, §6.12 CLAUDE.md) |
| uploaded_by | BIGINT | NOT NULL | (ref lintas-service ke db_rbac.users, no FK) |
| metadata | JSONB | NULL | metadata tambahan bebas (mis. dimensi gambar, jumlah halaman PDF) |
| created_at | TIMESTAMPTZ | NOT NULL | `DEFAULT now()` |

- Index: `idx_dokumen_kode_pendaftaran (kode_pendaftaran)`, `idx_dokumen_persyaratan_id (persyaratan_id)`, `idx_dokumen_uploaded_by (uploaded_by)`
- Tidak ada UNIQUE selain PK — satu `persyaratan_id` per pendaftaran seharusnya hanya
  punya satu dokumen *aktif*, tapi keunikan itu ditegakkan di db_transaksi
  (`pendaftaran_dokumen`), bukan di sini, karena service Dokumen tidak tahu konsep
  "pendaftaran aktif" (hanya menyimpan berkas apa adanya, termasuk riwayat file lama
  yang sudah digantikan). `[ASUMSI-13]`

---

## Ringkasan

| Database | Jumlah Tabel |
|---|---|
| db_rbac | 6 |
| db_master | 2 |
| db_transaksi | 9 |
| db_dokumen | 1 |
| **Total** | **18** |

#!/usr/bin/env bash
set -euo pipefail

# Seed demo lintas database. Script ini sengaja memakai database client di dalam
# container agar tidak bergantung pada tool tambahan di host.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ ! -f "$ROOT_DIR/infra/.env" ]]; then
  echo "infra/.env tidak ditemukan; salin dari infra/.env.example terlebih dahulu." >&2
  exit 1
fi
# shellcheck disable=SC1091
source "$ROOT_DIR/infra/.env"
COMPOSE=(docker compose -f "$ROOT_DIR/infra/docker-compose.yml" --env-file "$ROOT_DIR/infra/.env")
MYSQL_RBAC=( "${COMPOSE[@]}" exec -T db-rbac mysql -uroot "-p${MYSQL_ROOT_PASSWORD}" db_rbac )
MYSQL_MASTER=( "${COMPOSE[@]}" exec -T db-master mysql -uroot "-p${MYSQL_ROOT_PASSWORD}" db_master )
MYSQL_TX=( "${COMPOSE[@]}" exec -T db-transaksi mysql -uroot "-p${MYSQL_ROOT_PASSWORD}" db_transaksi )
PSQL_DOC=( "${COMPOSE[@]}" exec -T db-dokumen psql -U "${POSTGRES_USER}" -d db_dokumen )

echo "[1/4] Memakai data dasar RBAC/Master yang sudah dimigrasikan..."
"${MYSQL_MASTER[@]}" <<'SQL'
INSERT INTO beasiswa (kode,nama,deskripsi,persyaratan_khusus,kuota,metode,tanggal_buka,tanggal_tutup,status,created_at,updated_at)
VALUES
('web-developer-specialist','Web Developer Specialist','Pelatihan pengembangan web profesional.','Memiliki minat pada teknologi web.',30,'HYBRID','2026-01-01','2026-12-31','AKTIF',UTC_TIMESTAMP(),UTC_TIMESTAMP()),
('data-analyst-sql','Data Analyst & SQL','Pelatihan analisis data dan SQL.','Mampu menggunakan komputer dasar.',25,'DARING','2026-01-01','2026-12-31','AKTIF',UTC_TIMESTAMP(),UTC_TIMESTAMP()),
('ui-ux-design-prototyping','UI/UX Design & Prototyping','Pelatihan desain antarmuka dan prototyping.','Memiliki ketertarikan pada desain.',20,'DARING','2026-01-01','2026-12-31','AKTIF',UTC_TIMESTAMP(),UTC_TIMESTAMP())
ON DUPLICATE KEY UPDATE status='AKTIF',deleted_at=NULL;
INSERT INTO persyaratan (beasiswa_id,nama_dokumen,format_allowed,max_size_kb,is_mandatory,urutan,created_at,updated_at)
SELECT b.id,v.nama,'pdf,jpg,png',2048,1,v.urutan,UTC_TIMESTAMP(),UTC_TIMESTAMP()
FROM beasiswa b JOIN (SELECT 'KTP' nama,1 urutan UNION ALL SELECT 'KK',2 UNION ALL SELECT 'Ijazah',3 UNION ALL SELECT 'Surat Rekomendasi',4) v
WHERE b.kode IN ('web-developer-specialist','data-analyst-sql','ui-ux-design-prototyping')
ON DUPLICATE KEY UPDATE format_allowed='pdf,jpg,png',max_size_kb=2048,is_mandatory=1,urutan=VALUES(urutan);
SQL
# Image production sengaja tidak membawa dev dependency tsx; role/menu seed dasar
# dijalankan saat provisioning service, sementara role minimum dipastikan tersedia.
"${MYSQL_RBAC[@]}" <<'SQL'
INSERT INTO roles (kode,nama,created_at,updated_at) VALUES
('CALON_PESERTA','Calon Peserta',UTC_TIMESTAMP(),UTC_TIMESTAMP()),
('VERIFIKATOR','Verifikator',UTC_TIMESTAMP(),UTC_TIMESTAMP()),
('LEMBAGA_SELEKSI','Lembaga Seleksi',UTC_TIMESTAMP(),UTC_TIMESTAMP()),
('ADMIN','Administrator System',UTC_TIMESTAMP(),UTC_TIMESTAMP())
ON DUPLICATE KEY UPDATE nama=VALUES(nama);
SQL
"${MYSQL_MASTER[@]}" -NBe "SELECT COUNT(*) FROM beasiswa" | grep -q '[1-9]' || {
  echo "db_master kosong; jalankan seed service-master saat provisioning." >&2
  exit 1
}
"${MYSQL_RBAC[@]}" -NBe "SELECT COUNT(*) FROM roles" | grep -q '[1-9]' || {
  echo "db_rbac kosong; jalankan seed service-rbac saat provisioning." >&2
  exit 1
}

echo "[2/4] Menyiapkan lima akun peserta demo..."
participant_hash="$("${MYSQL_RBAC[@]}" -NBe "SELECT password_hash FROM users ORDER BY id LIMIT 1")"
if [[ -z "$participant_hash" ]]; then
  echo "Tidak menemukan hash password dari seed RBAC." >&2
  exit 1
fi
"${MYSQL_RBAC[@]}" <<SQL
INSERT INTO users
  (nik, nama, username, email, password_hash, role_id, is_email_verified, is_active, created_at, updated_at)
SELECT v.nik, v.nama, v.username, v.email, '${participant_hash}',
       r.id, 1, 1, UTC_TIMESTAMP(), UTC_TIMESTAMP()
FROM (
  SELECT '3273010101010001' nik, 'Demo Peserta Draft' nama, 'demo.peserta1' username, 'peserta1@demo.beasiswa.local' email
  UNION ALL SELECT '3273010101010002', 'Demo Peserta Diajukan', 'demo.peserta2', 'peserta2@demo.beasiswa.local'
  UNION ALL SELECT '3273010101010003', 'Demo Peserta Revisi', 'demo.peserta3', 'peserta3@demo.beasiswa.local'
  UNION ALL SELECT '3273010101010004', 'Demo Peserta Lolos Admin', 'demo.peserta4', 'peserta4@demo.beasiswa.local'
  UNION ALL SELECT '3273010101010005', 'Demo Peserta Lulus Wawancara', 'demo.peserta5', 'peserta5@demo.beasiswa.local'
) v
JOIN roles r ON r.kode = 'CALON_PESERTA'
ON DUPLICATE KEY UPDATE nama = VALUES(nama), password_hash = VALUES(password_hash),
  role_id = VALUES(role_id), is_email_verified = 1, is_active = 1;
SQL
u1="$("${MYSQL_RBAC[@]}" -NBe "SELECT id FROM users WHERE username='demo.peserta1'")"
u2="$("${MYSQL_RBAC[@]}" -NBe "SELECT id FROM users WHERE username='demo.peserta2'")"
u3="$("${MYSQL_RBAC[@]}" -NBe "SELECT id FROM users WHERE username='demo.peserta3'")"
u4="$("${MYSQL_RBAC[@]}" -NBe "SELECT id FROM users WHERE username='demo.peserta4'")"
u5="$("${MYSQL_RBAC[@]}" -NBe "SELECT id FROM users WHERE username='demo.peserta5'")"
verifikator_id="$("${MYSQL_RBAC[@]}" -NBe "SELECT id FROM users WHERE username='verifikator'")"
lembaga_id="$("${MYSQL_RBAC[@]}" -NBe "SELECT id FROM users WHERE username='lembaga'")"

echo "[3/4] Menyiapkan lima pendaftaran dan riwayat seleksi..."
b1="$("${MYSQL_MASTER[@]}" -NBe "SELECT id FROM beasiswa WHERE kode='web-developer-specialist' AND deleted_at IS NULL LIMIT 1")"
b2="$("${MYSQL_MASTER[@]}" -NBe "SELECT id FROM beasiswa WHERE kode='data-analyst-sql' AND deleted_at IS NULL LIMIT 1")"
b3="$("${MYSQL_MASTER[@]}" -NBe "SELECT id FROM beasiswa WHERE kode='ui-ux-design-prototyping' AND deleted_at IS NULL LIMIT 1")"
for value in "$b1" "$b2" "$b3"; do [[ "$value" =~ ^[0-9]+$ ]] || { echo "Program demo tidak lengkap." >&2; exit 1; }; done
req1_text="$("${MYSQL_MASTER[@]}" -NBe "SELECT id FROM persyaratan WHERE beasiswa_id=$b1 ORDER BY urutan" | tr '\n' ' ')"
req2_text="$("${MYSQL_MASTER[@]}" -NBe "SELECT id FROM persyaratan WHERE beasiswa_id=$b2 ORDER BY urutan" | tr '\n' ' ')"
req3_text="$("${MYSQL_MASTER[@]}" -NBe "SELECT id FROM persyaratan WHERE beasiswa_id=$b3 ORDER BY urutan" | tr '\n' ' ')"
read -r -a req1 <<< "$req1_text"
read -r -a req2 <<< "$req2_text"
read -r -a req3 <<< "$req3_text"
for reqs in "${req1[*]}" "${req2[*]}" "${req3[*]}"; do
  [[ "$(wc -w <<<"$reqs")" -eq 4 ]] || { echo "Persyaratan demo tidak lengkap." >&2; exit 1; }
done

snapshot() {
  "${MYSQL_MASTER[@]}" -NBe \
    "SELECT JSON_OBJECT('id', b.id, 'kode', b.kode, 'nama', b.nama, 'deskripsi', b.deskripsi,
      'persyaratan_khusus', b.persyaratan_khusus, 'kuota', b.kuota, 'metode', b.metode,
      'tanggal_buka', DATE_FORMAT(b.tanggal_buka, '%Y-%m-%d'),
      'tanggal_tutup', DATE_FORMAT(b.tanggal_tutup, '%Y-%m-%d'),
      'persyaratan', COALESCE((SELECT JSON_ARRAYAGG(JSON_OBJECT('id', p.id, 'nama_dokumen', p.nama_dokumen,
        'format_allowed', p.format_allowed, 'max_size_kb', p.max_size_kb, 'is_mandatory', p.is_mandatory,
        'urutan', p.urutan)) FROM persyaratan p WHERE p.beasiswa_id=b.id), JSON_ARRAY()))
      FROM beasiswa b WHERE b.id=$1"
}
s1="$(snapshot "$b1")"; s2="$(snapshot "$b2")"; s3="$(snapshot "$b3")"

"${MYSQL_TX[@]}" <<SQL
SET FOREIGN_KEY_CHECKS=0;
DELETE FROM audit_status WHERE pendaftaran_id IN (SELECT id FROM pendaftaran WHERE kode_pendaftaran LIKE 'DEMO-%');
DELETE FROM verifikasi_checklist WHERE verifikasi_id IN (SELECT id FROM verifikasi WHERE pendaftaran_id IN (SELECT id FROM pendaftaran WHERE kode_pendaftaran LIKE 'DEMO-%'));
DELETE FROM verifikasi WHERE pendaftaran_id IN (SELECT id FROM pendaftaran WHERE kode_pendaftaran LIKE 'DEMO-%');
DELETE FROM wawancara WHERE pendaftaran_id IN (SELECT id FROM pendaftaran WHERE kode_pendaftaran LIKE 'DEMO-%');
DELETE FROM pendaftaran_dokumen WHERE pendaftaran_id IN (SELECT id FROM pendaftaran WHERE kode_pendaftaran LIKE 'DEMO-%');
DELETE FROM pendaftaran_data_diri WHERE pendaftaran_id IN (SELECT id FROM pendaftaran WHERE kode_pendaftaran LIKE 'DEMO-%');
DELETE FROM pendaftaran_pendidikan WHERE pendaftaran_id IN (SELECT id FROM pendaftaran WHERE kode_pendaftaran LIKE 'DEMO-%');
DELETE FROM pendaftaran_persetujuan WHERE pendaftaran_id IN (SELECT id FROM pendaftaran WHERE kode_pendaftaran LIKE 'DEMO-%');
DELETE FROM pendaftaran WHERE kode_pendaftaran LIKE 'DEMO-%';
SET FOREIGN_KEY_CHECKS=1;

INSERT INTO pendaftaran (kode_pendaftaran,user_id,beasiswa_id,beasiswa_snapshot,status,section_terakhir,jumlah_revisi,created_at,updated_at)
VALUES
 ('DEMO-DRAFT', $u1, $b1,'$s1','DRAFT',1,0,UTC_TIMESTAMP(),UTC_TIMESTAMP()),
 ('DEMO-DIAJUKAN', $u2, $b2,'$s2','DIAJUKAN',4,0,UTC_TIMESTAMP(),UTC_TIMESTAMP()),
 ('DEMO-REVISI', $u3, $b3,'$s3','REVISI',4,1,UTC_TIMESTAMP(),UTC_TIMESTAMP()),
 ('DEMO-LOLOS', $u4, $b1,'$s1','LOLOS_ADMIN',4,0,UTC_TIMESTAMP(),UTC_TIMESTAMP()),
 ('DEMO-LULUS', $u5, $b2,'$s2','LULUS_WAWANCARA',4,0,UTC_TIMESTAMP(),UTC_TIMESTAMP());
SET @p2=(SELECT id FROM pendaftaran WHERE kode_pendaftaran='DEMO-DIAJUKAN');
SET @p3=(SELECT id FROM pendaftaran WHERE kode_pendaftaran='DEMO-REVISI');
SET @p4=(SELECT id FROM pendaftaran WHERE kode_pendaftaran='DEMO-LOLOS');
SET @p5=(SELECT id FROM pendaftaran WHERE kode_pendaftaran='DEMO-LULUS');
SET @p1=(SELECT id FROM pendaftaran WHERE kode_pendaftaran='DEMO-DRAFT');
SET @v=$verifikator_id;
SET @l=$lembaga_id;
INSERT INTO pendaftaran_data_diri (pendaftaran_id,nik,nama_lengkap,tempat_lahir,tanggal_lahir,jenis_kelamin,alamat_domisili,provinsi,kabupaten_kota,kecamatan,kelurahan,no_hp,email,created_at,updated_at)
VALUES
(@p1,'3273010101010001','Demo Peserta Draft','Bandung','2000-01-01','L','Jl. Demo 1','Jawa Barat','Kota Bandung','Coblong','Dago','081234567890','peserta1@demo.beasiswa.local',UTC_TIMESTAMP(),UTC_TIMESTAMP()),
(@p2,'3273010101010002','Demo Peserta Diajukan','Bandung','2000-01-01','L','Jl. Demo 1','Jawa Barat','Kota Bandung','Coblong','Dago','081234567890','peserta2@demo.beasiswa.local',UTC_TIMESTAMP(),UTC_TIMESTAMP()),
(@p3,'3273010101010003','Demo Peserta Revisi','Bandung','2000-01-01','L','Jl. Demo 1','Jawa Barat','Kota Bandung','Coblong','Dago','081234567890','peserta3@demo.beasiswa.local',UTC_TIMESTAMP(),UTC_TIMESTAMP()),
(@p4,'3273010101010004','Demo Peserta Lolos Admin','Bandung','2000-01-01','L','Jl. Demo 1','Jawa Barat','Kota Bandung','Coblong','Dago','081234567890','peserta4@demo.beasiswa.local',UTC_TIMESTAMP(),UTC_TIMESTAMP()),
(@p5,'3273010101010005','Demo Peserta Lulus Wawancara','Bandung','2000-01-01','L','Jl. Demo 1','Jawa Barat','Kota Bandung','Coblong','Dago','081234567890','peserta5@demo.beasiswa.local',UTC_TIMESTAMP(),UTC_TIMESTAMP());
INSERT INTO pendaftaran_pendidikan (pendaftaran_id,pendidikan_terakhir,nama_instansi,jurusan,pekerjaan,created_at,updated_at)
SELECT id,'S1','Universitas Demo','Teknik Informatika','Peserta',UTC_TIMESTAMP(),UTC_TIMESTAMP()
FROM pendaftaran WHERE kode_pendaftaran LIKE 'DEMO-%';
INSERT INTO pendaftaran_persetujuan (pendaftaran_id,setuju_keabsahan,setuju_ketentuan,disetujui_at,created_at,updated_at)
SELECT id,1,1,UTC_TIMESTAMP(),UTC_TIMESTAMP(),UTC_TIMESTAMP() FROM pendaftaran WHERE kode_pendaftaran <> 'DEMO-DRAFT' AND kode_pendaftaran LIKE 'DEMO-%';
INSERT INTO pendaftaran_dokumen (pendaftaran_id,persyaratan_id,dokumen_uuid,nama_dokumen,created_at,updated_at)
VALUES
(@p2,${req2[0]},'00000000-0000-4000-8000-000000000021','KTP',UTC_TIMESTAMP(),UTC_TIMESTAMP()),
(@p2,${req2[1]},'00000000-0000-4000-8000-000000000022','KK',UTC_TIMESTAMP(),UTC_TIMESTAMP()),
(@p2,${req2[2]},'00000000-0000-4000-8000-000000000023','Ijazah',UTC_TIMESTAMP(),UTC_TIMESTAMP()),
(@p2,${req2[3]},'00000000-0000-4000-8000-000000000024','Surat Rekomendasi',UTC_TIMESTAMP(),UTC_TIMESTAMP());
INSERT INTO pendaftaran_dokumen (pendaftaran_id,persyaratan_id,dokumen_uuid,nama_dokumen,created_at,updated_at)
VALUES
(@p3,${req3[0]},'00000000-0000-4000-8000-000000000031','KTP',UTC_TIMESTAMP(),UTC_TIMESTAMP()),
(@p3,${req3[1]},'00000000-0000-4000-8000-000000000032','KK',UTC_TIMESTAMP(),UTC_TIMESTAMP()),
(@p3,${req3[2]},'00000000-0000-4000-8000-000000000033','Ijazah',UTC_TIMESTAMP(),UTC_TIMESTAMP()),
(@p3,${req3[3]},'00000000-0000-4000-8000-000000000034','Surat Rekomendasi',UTC_TIMESTAMP(),UTC_TIMESTAMP());
INSERT INTO pendaftaran_dokumen (pendaftaran_id,persyaratan_id,dokumen_uuid,nama_dokumen,created_at,updated_at)
VALUES
(@p4,${req1[0]},'00000000-0000-4000-8000-000000000041','KTP',UTC_TIMESTAMP(),UTC_TIMESTAMP()),
(@p4,${req1[1]},'00000000-0000-4000-8000-000000000042','KK',UTC_TIMESTAMP(),UTC_TIMESTAMP()),
(@p4,${req1[2]},'00000000-0000-4000-8000-000000000043','Ijazah',UTC_TIMESTAMP(),UTC_TIMESTAMP()),
(@p4,${req1[3]},'00000000-0000-4000-8000-000000000044','Surat Rekomendasi',UTC_TIMESTAMP(),UTC_TIMESTAMP());
INSERT INTO pendaftaran_dokumen (pendaftaran_id,persyaratan_id,dokumen_uuid,nama_dokumen,created_at,updated_at)
VALUES
(@p5,${req2[0]},'00000000-0000-4000-8000-000000000051','KTP',UTC_TIMESTAMP(),UTC_TIMESTAMP()),
(@p5,${req2[1]},'00000000-0000-4000-8000-000000000052','KK',UTC_TIMESTAMP(),UTC_TIMESTAMP()),
(@p5,${req2[2]},'00000000-0000-4000-8000-000000000053','Ijazah',UTC_TIMESTAMP(),UTC_TIMESTAMP()),
(@p5,${req2[3]},'00000000-0000-4000-8000-000000000054','Surat Rekomendasi',UTC_TIMESTAMP(),UTC_TIMESTAMP());
SQL

# Dokumen demo memakai UUID stabil agar seed dapat dijalankan berulang.
doc_values=()
for p in 2 3 4 5; do
  case "$p" in
    2) demo_code="DEMO-DIAJUKAN" ;;
    3) demo_code="DEMO-REVISI" ;;
    4) demo_code="DEMO-LOLOS" ;;
    5) demo_code="DEMO-LULUS" ;;
  esac
  for r in 1 2 3 4; do
    uuid=$(printf '00000000-0000-4000-8000-%012d' $((p * 10 + r)))
    if [[ "$p" == 2 || "$p" == 5 ]]; then
      requirement_id="${req2[$((r - 1))]}"
    elif [[ "$p" == 4 ]]; then
      requirement_id="${req1[$((r - 1))]}"
    else
      requirement_id="${req3[$((r - 1))]}"
    fi
    doc_values+=("('$uuid','${demo_code}','${requirement_id}','demo-${p}-${r}.pdf','${uuid}_dokumen.pdf','/storage/permohonan/${demo_code}/${uuid}_dokumen.pdf','application/pdf',16,'0000000000000000000000000000000000000000000000000000000000000000','SKIPPED',1,'{\"demo\":true}')")
  done
done
doc_sql=$(IFS=,; echo "${doc_values[*]}")
"${PSQL_DOC[@]}" <<SQL
CREATE EXTENSION IF NOT EXISTS pgcrypto;
DO \$\$ BEGIN
  CREATE TYPE "StatusScan" AS ENUM ('PENDING','CLEAN','INFECTED','SKIPPED');
EXCEPTION WHEN duplicate_object THEN NULL;
END \$\$;
CREATE TABLE IF NOT EXISTS dokumen (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kode_pendaftaran varchar(20) NOT NULL,
  persyaratan_id bigint NOT NULL,
  nama_file_asli varchar(255) NOT NULL,
  nama_file_simpan varchar(255) NOT NULL,
  path varchar(500) NOT NULL,
  mime_terdeteksi varchar(100) NOT NULL,
  ukuran_byte integer NOT NULL,
  sha256 char(64) NOT NULL,
  status_scan "StatusScan" NOT NULL DEFAULT 'PENDING',
  uploaded_by bigint NOT NULL,
  metadata jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
DELETE FROM dokumen WHERE kode_pendaftaran LIKE 'DEMO-%';
INSERT INTO dokumen (id,kode_pendaftaran,persyaratan_id,nama_file_asli,nama_file_simpan,path,mime_terdeteksi,ukuran_byte,sha256,status_scan,uploaded_by,metadata)
VALUES $doc_sql
ON CONFLICT (id) DO NOTHING;
SQL

"${MYSQL_TX[@]}" <<SQL
SET @p2=(SELECT id FROM pendaftaran WHERE kode_pendaftaran='DEMO-DIAJUKAN');
SET @p3=(SELECT id FROM pendaftaran WHERE kode_pendaftaran='DEMO-REVISI');
SET @p4=(SELECT id FROM pendaftaran WHERE kode_pendaftaran='DEMO-LOLOS');
SET @p5=(SELECT id FROM pendaftaran WHERE kode_pendaftaran='DEMO-LULUS');
SET @v=$verifikator_id;
SET @l=$lembaga_id;
INSERT INTO verifikasi (pendaftaran_id,verifikator_id,keputusan,catatan_umum,created_at)
VALUES (@p2,@v,'REVISI','Perbaiki dokumen KTP.',UTC_TIMESTAMP()),(@p3,@v,'REVISI','Perbaiki dokumen KTP.',UTC_TIMESTAMP()),
       (@p4,@v,'DISETUJUI','Dokumen lengkap.',UTC_TIMESTAMP()),(@p5,@v,'DISETUJUI','Dokumen lengkap.',UTC_TIMESTAMP());
INSERT INTO verifikasi_checklist (verifikasi_id,persyaratan_id,is_sesuai,catatan_perbaikan,created_at)
SELECT v.id, x.persyaratan_id, x.is_sesuai, x.catatan, UTC_TIMESTAMP()
FROM verifikasi v
JOIN (
  SELECT @p2 pendaftaran_id, ${req2[0]} persyaratan_id, 0 is_sesuai, 'Unggah ulang KTP.' catatan
  UNION ALL SELECT @p2, ${req2[1]}, 1, NULL
  UNION ALL SELECT @p2, ${req2[2]}, 1, NULL
  UNION ALL SELECT @p2, ${req2[3]}, 1, NULL
  UNION ALL SELECT @p3, ${req3[0]}, 0, 'Unggah ulang KTP.'
  UNION ALL SELECT @p3, ${req3[1]}, 1, NULL
  UNION ALL SELECT @p3, ${req3[2]}, 1, NULL
  UNION ALL SELECT @p3, ${req3[3]}, 1, NULL
  UNION ALL SELECT @p4, ${req1[0]}, 1, NULL
  UNION ALL SELECT @p4, ${req1[1]}, 1, NULL
  UNION ALL SELECT @p4, ${req1[2]}, 1, NULL
  UNION ALL SELECT @p4, ${req1[3]}, 1, NULL
  UNION ALL SELECT @p5, ${req2[0]}, 1, NULL
  UNION ALL SELECT @p5, ${req2[1]}, 1, NULL
  UNION ALL SELECT @p5, ${req2[2]}, 1, NULL
  UNION ALL SELECT @p5, ${req2[3]}, 1, NULL
) x ON x.pendaftaran_id=v.pendaftaran_id
WHERE v.pendaftaran_id IN (@p2,@p3,@p4,@p5);
UPDATE verifikasi_checklist SET created_at=UTC_TIMESTAMP() WHERE verifikasi_id IN (SELECT id FROM verifikasi WHERE pendaftaran_id IN (@p2,@p3,@p4,@p5));
INSERT INTO wawancara (pendaftaran_id,penilai_id,nilai_komunikasi,nilai_teknis,nilai_komitmen,nilai_akhir,status,catatan_evaluasi,created_at,updated_at)
VALUES (@p5,@l,88,92,90,90.80,'LULUS','Performa sangat baik.',UTC_TIMESTAMP(),UTC_TIMESTAMP());
INSERT INTO audit_status (pendaftaran_id,status_lama,status_baru,actor_id,actor_role,catatan,created_at)
SELECT id,'DRAFT',status,$verifikator_id,'DEMO','Seed demo',UTC_TIMESTAMP() FROM pendaftaran WHERE kode_pendaftaran IN ('DEMO-DIAJUKAN','DEMO-REVISI','DEMO-LOLOS','DEMO-LULUS');
SQL

# Tambahkan file PDF kecil yang valid untuk preview demo. File hanya berada di volume
# service-dokumen dan tidak pernah disajikan sebagai static route.
"${COMPOSE[@]}" exec -T service-dokumen sh -c \
  "for spec in '2 DEMO-DIAJUKAN' '3 DEMO-REVISI' '4 DEMO-LOLOS' '5 DEMO-LULUS'; do set -- \$spec; p=\$1; code=\$2; mkdir -p /storage/permohonan/\$code; for r in 1 2 3 4; do uuid=\$(printf '00000000-0000-4000-8000-%012d' \$((p * 10 + r))); printf '%%PDF-1.4\n%% demo\n' > /storage/permohonan/\$code/\${uuid}_dokumen.pdf; done; done"

echo "Seed demo selesai."
echo "Akun peserta: peserta1@demo.beasiswa.local ... peserta5@demo.beasiswa.local"
echo "Akun internal: gunakan akun seed RBAC (password default dari SEED_DEMO_PASSWORD atau Password123!)."

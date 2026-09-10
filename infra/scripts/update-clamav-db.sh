#!/usr/bin/env bash
#
# Mengisi/memperbarui database virus ClamAV pada NAMED VOLUME docker
# (beasiswa-clamav-db) dari HOST — jaringan host punya internet, network `internal`
# compose tidak. Container clamav memakai CLAMAV_NO_FRESHCLAM=true, jadi satu-satunya
# cara memperbarui signature adalah script ini.
#
# Pemakaian:
#   ./infra/scripts/update-clamav-db.sh
#   # setelah selesai:
#   docker compose -f infra/docker-compose.yml restart clamav

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR/infra"

# Pastikan volume ada (compose sudah mendeklarasikannya, tapi script harus tetap
# jalan sebelum `docker compose up` pertama).
docker volume create beasiswa-clamav-db >/dev/null

echo "Menjalankan freshclam di container sementara (menulis ke volume)..."
docker run --rm --entrypoint freshclam \
  -v beasiswa-clamav-db:/var/lib/clamav \
  clamav/clamav:latest

echo ""
echo "Isi volume beasiswa-clamav-db:"
docker run --rm -v beasiswa-clamav-db:/var/lib/clamav clamav/clamav:latest \
  ls -lh /var/lib/clamav | grep -E 'cvd|dat' || true

echo ""
echo "Selesai. Terapkan dengan: docker compose -f infra/docker-compose.yml restart clamav"

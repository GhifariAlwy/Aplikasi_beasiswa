#!/usr/bin/env bash
#
# Membuat keypair RSA untuk JWT RS256 (ADR-005).
#
# Kenapa RS256 dan bukan HS256: dengan HS256 satu secret dipakai untuk menandatangani
# sekaligus memverifikasi, sehingga API Gateway yang seharusnya hanya memverifikasi
# ikut mampu MENERBITKAN token palsu. Dengan RS256, private key hanya dipegang
# service-rbac; Gateway cukup memegang public key.
#
# Pemakaian:
#   ./infra/scripts/generate-keys.sh          # buat kalau belum ada
#   JWT_KEY_DIR=/path/aman ./infra/scripts/generate-keys.sh --force

set -euo pipefail

KEYS_DIR="${JWT_KEY_DIR:-${HOME}/.config/beasiswa}"
PRIVATE_KEY="$KEYS_DIR/private.pem"
PUBLIC_KEY="$KEYS_DIR/public.pem"
KEY_BITS=3072

FORCE=false
if [[ "${1:-}" == "--force" ]]; then
  FORCE=true
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "ERROR: openssl tidak ditemukan. Pasang openssl lebih dulu." >&2
  exit 1
fi

mkdir -p "$KEYS_DIR"
chmod 700 "$KEYS_DIR"

if [[ -f "$PRIVATE_KEY" && "$FORCE" != true ]]; then
  echo "Keypair sudah ada di $KEYS_DIR — dibiarkan apa adanya."
  echo "Menimpa keypair akan membatalkan SEMUA token yang beredar."
  echo "Jalankan dengan --force kalau memang ingin membuat ulang."
  exit 0
fi

echo "Membuat private key RSA ${KEY_BITS} bit..."
openssl genpkey -algorithm RSA -pkeyopt "rsa_keygen_bits:${KEY_BITS}" -out "$PRIVATE_KEY" 2>/dev/null

echo "Menurunkan public key..."
openssl rsa -pubout -in "$PRIVATE_KEY" -out "$PUBLIC_KEY" 2>/dev/null

# Private key hanya boleh dibaca pemiliknya.
chmod 600 "$PRIVATE_KEY" "$PUBLIC_KEY"

echo ""
echo "Selesai:"
echo "  private : $PRIVATE_KEY  (HANYA untuk service-rbac, mode 600)"
echo "  public  : $PUBLIC_KEY   (untuk api-gateway)"
echo ""
echo "Keypair berada di luar repository; set JWT_PRIVATE_KEY_HOST/JWT_PUBLIC_KEY_HOST di infra/.env."

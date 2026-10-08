#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ -e .env ]; then echo '.env already exists; refusing to overwrite'; exit 1; fi
mkdir -p .local
umask 077
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out .local/jwt.pem 2>/dev/null
openssl pkey -in .local/jwt.pem -pubout -outform DER -out .local/jwt-public.der
openssl pkcs8 -topk8 -nocrypt -in .local/jwt.pem -outform DER -out .local/jwt-private.der
python3 scripts/create-env.py

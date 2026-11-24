#!/usr/bin/env bash
# Creates the lab PKI in ./certs. Usage:
#   ./certs.sh             -> ca + backend + frontend
#   ./certs.sh evil        -> rogue CA + a "frontend" client cert it signed (break-it exercise)
#   BACKEND_SAN="DNS:localhost" ./certs.sh backend   -> re-issue backend cert with other names
set -euo pipefail
cd "$(dirname "$0")/certs"

DAYS=30
BACKEND_SAN="${BACKEND_SAN:-DNS:backend,DNS:localhost}"

run() { echo "+ $*"; "$@"; }

ca() {
  # Self-signed root: Subject == Issuer. keyUsage=keyCertSign means "may sign other certs".
  run openssl req -x509 -new -newkey rsa:2048 -noenc -keyout ca.key -out ca.crt -days $DAYS \
    -subj "/CN=Lab Root CA" -addext "keyUsage=critical,keyCertSign,cRLSign"
}

backend() {
  # 1) key + CSR (the request). SAN = names clients may use to reach this server.
  run openssl req -new -newkey rsa:2048 -noenc -keyout backend.key -out backend.csr \
    -subj "/CN=backend" -addext "subjectAltName=$BACKEND_SAN" -addext "extendedKeyUsage=serverAuth"
  # 2) CA signs the CSR -> certificate. Only the CSR travels; the key stays here.
  run openssl x509 -req -in backend.csr -CA ca.crt -CAkey ca.key -out backend.crt -days $DAYS \
    -copy_extensions copyall
}

frontend() {
  # Client cert: no SAN needed, EKU=clientAuth says "may authenticate as a TLS client".
  run openssl req -new -newkey rsa:2048 -noenc -keyout frontend.key -out frontend.csr \
    -subj "/CN=frontend" -addext "extendedKeyUsage=clientAuth"
  run openssl x509 -req -in frontend.csr -CA ca.crt -CAkey ca.key -out frontend.crt -days $DAYS \
    -copy_extensions copyall
}

evil() {
  # Same CN "frontend", but signed by a CA the backend doesn't trust.
  run openssl req -x509 -new -newkey rsa:2048 -noenc -keyout evil-ca.key -out evil-ca.crt -days $DAYS \
    -subj "/CN=Evil CA" -addext "keyUsage=critical,keyCertSign,cRLSign"
  run openssl req -new -newkey rsa:2048 -noenc -keyout evil.key -out evil.csr \
    -subj "/CN=frontend" -addext "extendedKeyUsage=clientAuth"
  run openssl x509 -req -in evil.csr -CA evil-ca.crt -CAkey evil-ca.key -out evil.crt -days $DAYS \
    -copy_extensions copyall
}

if [ $# -eq 0 ]; then set -- ca backend frontend; fi
for step in "$@"; do echo "== $step"; "$step"; done

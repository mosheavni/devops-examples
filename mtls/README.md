# mTLS lab

```text
 you (laptop) ──HTTP──▶ frontend :8080 ──mTLS──▶ backend :8443
                       (client cert)            (server cert, REQUIRES client cert)
 you (curl) ───────────────────mTLS───────────▶ backend :8443
```

## Components

| Piece         | File                          | Role                                                                                                 |
| ------------- | ----------------------------- | ---------------------------------------------------------------------------------------------------- |
| CA            | `certs/ca.crt` + `ca.key`     | The only thing both sides trust. Signs everyone's cert. `ca.key` = power to mint identities.         |
| Backend cert  | `certs/backend.crt` + `.key`  | Proves "I am `backend`". SAN = `backend`, `localhost` (the names clients may use). EKU = serverAuth. |
| Frontend cert | `certs/frontend.crt` + `.key` | Proves "I am `frontend`". EKU = clientAuth.                                                          |
| CSR           | `certs/*.csr`                 | "Please sign this public key + name". The private key never leaves its owner.                        |
| backend       | `backend/server.py`           | `verify_mode = CERT_REQUIRED` → no valid client cert, no handshake. Logs every accept/reject.        |
| frontend      | `frontend/app.py`             | Trusts only `ca.crt`, presents `frontend.crt` when calling backend.                                  |

Plain TLS: client checks server. **mTLS: server also checks client.** Each side checks: signed by my trusted CA? not expired? right name/usage?

All commands run from `mtls/`.

## 1. Build the PKI

All openssl commands live in [certs.sh](certs.sh) (commented). Read it first, then run one step at a time to see each command and its output:

```bash
./certs.sh ca
```

```bash
./certs.sh backend
```

```bash
./certs.sh frontend
```

(`./certs.sh` with no args does all three.)

Look inside (compare Issuer vs Subject, SAN, EKU):

```bash
openssl x509 -in certs/backend.crt -noout -subject -issuer -dates -ext subjectAltName,extendedKeyUsage
```

```bash
openssl verify -CAfile certs/ca.crt certs/backend.crt certs/frontend.crt
```

## 2. Run it

```bash
docker compose up -d
```

```bash
curl localhost:8080
```

Expect `frontend -> backend OK ... Hello frontend!`. Keep backend logs open in another tab:

```bash
docker compose logs -f backend
```

## 3. Poke it (you are now the client)

| #   | Try                                                                                                                                | Expect                                            | Lesson                                                           |
| --- | ---------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------- | ---------------------------------------------------------------- |
| a   | `curl --cacert certs/ca.crt https://localhost:8443`                                                                                | fails; log: `PEER_DID_NOT_RETURN_A_CERTIFICATE`   | Server demands a client cert.                                    |
| b   | `curl --cacert certs/ca.crt --cert certs/frontend.crt --key certs/frontend.key https://localhost:8443`                             | `Hello frontend!`                                 | You borrowed frontend's identity. Keys = identity; protect them. |
| c   | same as b but `https://127.0.0.1:8443`                                                                                             | `no alternative certificate subject name matches` | Client checks server's SAN.                                      |
| d   | same as b but drop `--cacert`                                                                                                      | `unable to get local issuer certificate`          | Your laptop doesn't trust the lab CA.                            |
| e   | `openssl s_client -connect localhost:8443 -CAfile certs/ca.crt -cert certs/frontend.crt -key certs/frontend.key -brief </dev/null` | handshake summary                                 | Raw TLS view: protocol, cipher, peer cert.                       |

## 4. Break it

**Rogue CA** — a cert with the right name, signed by the wrong CA:

```bash
./certs.sh evil
```

```bash
curl --cacert certs/ca.crt --cert certs/evil.crt --key certs/evil.key https://localhost:8443
```

Backend log: `unable to get local issuer certificate`. CN says `frontend`, but **trust comes from the signature, not the name.**

**Frontend without a cert** — comment out the `load_cert_chain` line in `frontend/app.py`, then:

```bash
docker compose restart frontend
```

`curl localhost:8080` → FAILED. Uncomment and restart to fix.

**Backend without SAN `backend`** — re-issue the backend cert with only `localhost`:

```bash
BACKEND_SAN="DNS:localhost" ./certs.sh backend
```

Then `docker compose restart backend` and `curl localhost:8080` → hostname mismatch from the frontend's side. Fix: `./certs.sh backend` and restart.

## Cleanup

```bash
docker compose down
```

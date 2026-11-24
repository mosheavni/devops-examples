# Backend: HTTPS server that REQUIRES a client certificate (the "m" in mTLS).
import ssl
from http.server import HTTPServer, BaseHTTPRequestHandler

ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain("/certs/backend.crt", "/certs/backend.key")  # who I am
ctx.load_verify_locations("/certs/ca.crt")                       # whom I trust to vouch for clients
ctx.verify_mode = ssl.CERT_REQUIRED                              # no client cert -> no handshake


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        peer = self.connection.getpeercert()  # only present because the handshake verified it
        cn = dict(x[0] for x in peer["subject"])["commonName"]
        body = f"Hello {cn}! Your cert was verified against my CA. (TLS {self.connection.version()})\n"
        data = body.encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(data)))  # lets the client know where the body ends
        self.end_headers()
        self.wfile.write(data)


class Server(HTTPServer):
    def get_request(self):
        sock, addr = self.socket.accept()
        try:
            sock = ctx.wrap_socket(sock, server_side=True)  # TLS handshake happens here
        except (ssl.SSLError, OSError) as e:
            print(f"[backend] handshake REJECTED from {addr[0]}: {e}", flush=True)
            sock.close()
            raise
        print(f"[backend] handshake OK from {addr[0]}: client={sock.getpeercert()['subject']}", flush=True)
        return sock, addr


print("[backend] mTLS listening on :8443", flush=True)
Server(("0.0.0.0", 8443), Handler).serve_forever()

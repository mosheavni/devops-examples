# Frontend: plain HTTP for you on :8080; calls the backend over mTLS.
import ssl, urllib.request
from http.server import HTTPServer, BaseHTTPRequestHandler

ctx = ssl.create_default_context(cafile="/certs/ca.crt")           # trust ONLY our lab CA
ctx.load_cert_chain("/certs/frontend.crt", "/certs/frontend.key")  # present my client cert


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            with urllib.request.urlopen("https://backend:8443/", context=ctx, timeout=5) as r:
                body = f"frontend -> backend OK\nbackend said: {r.read().decode()}"
        except Exception as e:
            body = f"frontend -> backend FAILED: {e}\n"
        self.send_response(200)
        self.end_headers()
        self.wfile.write(body.encode())


print("[frontend] HTTP listening on :8080", flush=True)
HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()

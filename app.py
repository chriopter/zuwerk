"""Minimal Zuwerk web application."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = "127.0.0.1"
PORT = 8000

PAGE = b"""<!doctype html>
<html lang="de">
<head><meta charset="utf-8"><title>Zuwerk</title></head>
<body>
  <main>
    <h1>Zuwerk</h1>
    <p>Projekte f\xc3\xbcr Menschen und Agenten.</p>
  </main>
</body>
</html>
"""


class Handler(BaseHTTPRequestHandler):
    """Serve the initial Zuwerk page."""

    def do_GET(self) -> None:
        if self.path != "/":
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(PAGE)))
        self.end_headers()
        self.wfile.write(PAGE)

    def log_message(self, format: str, *args: object) -> None:
        return


def main() -> None:
    print(f"Zuwerk läuft auf http://{HOST}:{PORT}")
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()

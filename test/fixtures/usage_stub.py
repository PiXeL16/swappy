# ABOUTME: Real local HTTP server standing in for Anthropic's usage endpoint in swappy's tests.
# ABOUTME: Serves the status/body files in the directory given as argv[1]; logs each request.
import http.server
import json
import os
import subprocess
import sys

DIR = sys.argv[1]


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        with open(os.path.join(DIR, "requests.log"), "a") as f:
            f.write(json.dumps({
                "path": self.path,
                "auth": self.headers.get("Authorization"),
                "beta": self.headers.get("anthropic-beta"),
            }) + "\n")
        # Snapshot every process's argv while swappy's request is in flight, so tests can
        # prove the bearer token never appears on a command line.
        ps = subprocess.run(["ps", "-axo", "args="], capture_output=True, text=True).stdout
        with open(os.path.join(DIR, "ps.log"), "a") as f:
            f.write(ps)
        with open(os.path.join(DIR, "status")) as f:
            status = int(f.read().strip())
        with open(os.path.join(DIR, "body"), "rb") as f:
            body = f.read()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
with open(os.path.join(DIR, "port.tmp"), "w") as f:
    f.write(str(server.server_address[1]))
os.replace(os.path.join(DIR, "port.tmp"), os.path.join(DIR, "port"))
server.serve_forever()

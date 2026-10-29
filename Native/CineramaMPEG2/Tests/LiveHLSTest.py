"""Exercise HLS reloads over loopback HTTP with a growing generated playlist."""
import http.server
from pathlib import Path
import subprocess
import sys
import threading
import time
from urllib.parse import urlparse, parse_qs

root = Path(sys.argv[1]).resolve()
playlist = (root / "hls.m3u8").read_text().splitlines()
header, entries = [], []
for line in playlist:
    if line.startswith("#EXTINF"):
        entries.append([line])
    elif entries and not line.startswith("#"):
        entries[-1].append(line)
    elif not entries and line != "#EXT-X-ENDLIST":
        header.append(line)
assert len(entries) >= 3
start = time.monotonic()
class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(root), **kwargs)
    def log_message(self, *args):
        pass
    def do_GET(self):
        path = urlparse(self.path).path
        if path in ("/jitter.ts", "/stalled.ts"):
            body = (root / "jitter.ts").read_bytes()
            self.send_response(200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            if path == "/stalled.ts":
                self.wfile.write(body[:(len(body) * 2 // 5 // 188) * 188])
                self.wfile.flush()
                time.sleep(3)
                return
            # Pace the ten-second fixture near its media rate, then add a
            # one-second gap after four seconds. A burst followed by a sleep
            # would also pass without prefetch because TCP buffers the burst.
            began = time.monotonic()
            try:
                for chunk in range(40):
                    deadline = began + chunk * 0.25 + (1 if chunk >= 16 else 0)
                    time.sleep(max(0, deadline - time.monotonic()))
                    chunk_start = (len(body) * chunk // 40 // 188) * 188
                    end = (len(body) * (chunk + 1) // 40 // 188) * 188 if chunk < 39 else len(body)
                    self.wfile.write(body[chunk_start:end])
                    self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
        if path == "/slow":
            time.sleep(3)
            return
        if path == "/unavailable":
            self.send_error(503)
            return
        if parse_qs(urlparse(self.path).query).get("X-Plex-Token") != ["fixture-test"]:
            self.send_error(403)
            return
        if self.path.split("?")[0] == "/hls.m3u8":
            elapsed = time.monotonic() - start
            count = min(len(entries), 1 + int(elapsed / 0.7))
            lines = header + [line for entry in entries[:count] for line in entry]
            if elapsed > 2.2:
                lines.append("#EXT-X-ENDLIST")
            body = ("\n".join(lines) + "\n").encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/vnd.apple.mpegurl")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            super().do_GET()
server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    subprocess.run([sys.argv[2], f"http://127.0.0.1:{server.server_port}/hls.m3u8?X-Plex-Token=fixture-test"], check=True, timeout=30)
    subprocess.run([sys.argv[2], "--buffered-cancel-read", f"http://127.0.0.1:{server.server_port}/stalled.ts"], check=True, timeout=10)
    subprocess.run([sys.argv[2], "--unbuffered-jitter", f"http://127.0.0.1:{server.server_port}/jitter.ts"], check=True, timeout=20)
    subprocess.run([sys.argv[2], "--buffered-jitter", f"http://127.0.0.1:{server.server_port}/jitter.ts"], check=True, timeout=20)
    subprocess.run([sys.argv[2], "--failure", f"http://127.0.0.1:{server.server_port}/unavailable"], check=True, timeout=15)
    subprocess.run([sys.argv[2], "--cancel", f"http://127.0.0.1:{server.server_port}/slow"], check=True, timeout=5)
finally:
    server.shutdown()
    server.server_close()

"""
Cal AI Automation Server
Listens for HTTP requests from the glasses app and triggers Appium uploads.

Usage:
  python server.py

The server runs on port 8765. When it receives a POST to /upload with
{"count": N}, it runs the Appium script to upload N photos inclusive.

Make sure appium and pymobiledevice3 tunnel are running.
"""

import subprocess
import sys
import os
from http.server import HTTPServer, BaseHTTPRequestHandler
import json

PORT = 8765
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SCRIPT_PATH = os.path.join(SCRIPT_DIR, "cal_ai_automate.py")


class AutomationHandler(BaseHTTPRequestHandler):

    def do_POST(self):
        if self.path == "/upload":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length).decode("utf-8")

            try:
                data = json.loads(body) if body else {}
                count = data.get("count", 1)
                count = max(1, min(count, 3))  # Clamp 1-3
            except json.JSONDecodeError:
                count = 1

            print(f"\n{'='*50}")
            print(f"  Received upload request: {count} photo(s)")
            print(f"{'='*50}\n")

            # Run the automation script in a subprocess
            cmd = [sys.executable, SCRIPT_PATH, "upload", str(count), "--inclusive"]
            print(f"Running: {' '.join(cmd)}\n")

            process = subprocess.Popen(
                cmd,
                cwd=SCRIPT_DIR,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True
            )

            # Send immediate response to the app
            response = json.dumps({"status": "started", "count": count})
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(response.encode())

            # Stream subprocess output to console
            for line in process.stdout:
                print(line, end="")
            process.wait()

            print(f"\nAutomation finished (exit code: {process.returncode})")

        else:
            self.send_response(404)
            self.end_headers()

    def do_GET(self):
        if self.path == "/status":
            response = json.dumps({"status": "ready"})
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(response.encode())
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        # Suppress default request logging
        pass


if __name__ == "__main__":
    import socket
    hostname = socket.gethostname()
    local_ip = socket.gethostbyname(hostname)

    server = HTTPServer(("0.0.0.0", PORT), AutomationHandler)
    print(f"Cal AI Automation Server running on port {PORT}")
    print(f"  Local:   http://127.0.0.1:{PORT}")
    print(f"  Network: http://{local_ip}:{PORT}")
    print(f"\nThe glasses app should POST to http://{local_ip}:{PORT}/upload")
    print(f'  Body: {{"count": N}}')
    print(f"\nWaiting for requests...\n")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nServer stopped.")
        server.server_close()

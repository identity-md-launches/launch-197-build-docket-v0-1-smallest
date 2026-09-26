"""Regression: optimization must not disable the local gas helper's chain guard."""
import json
from pathlib import Path
import subprocess
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer


class GasHelperTest(unittest.TestCase):
    def test_chain_guard_survives_optimized_python(self):
        seen = []

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_args):
                pass

            def do_POST(self):
                request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                seen.append(request["method"])
                body = json.dumps({"jsonrpc": "2.0", "id": 1, "result": "0x1"}).encode()
                self.send_response(200)
                self.end_headers()
                self.wfile.write(body)

        server = HTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            result = subprocess.run([
                "python3", "-O", "script/measure-anvil-gas.py",
                "0x0000000000000000000000000000000000000001",
                "--rpc-url", f"http://127.0.0.1:{server.server_port}",
            ], cwd=Path(__file__).resolve().parents[1], capture_output=True, text=True, timeout=10)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Local Anvil chain 31337 only", result.stderr)
            self.assertEqual(seen, ["eth_chainId"])
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == "__main__":
    unittest.main()

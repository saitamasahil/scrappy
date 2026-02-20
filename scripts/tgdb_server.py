import http.server
import socketserver
import urllib.parse
import os
import sys

PORT = 8080
TMP_FILE = "/tmp/scrappy_tgdb_key.txt"

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Scrappy TheGamesDB API Key</title>
    <style>
        body { font-family: sans-serif; display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100vh; background-color: #f4f4f4; margin: 0; }
        .container { background: white; padding: 2rem; border-radius: 8px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); width: 90%; max-width: 500px; text-align: center; }
        h1 { font-size: 1.5rem; margin-bottom: 1rem; color: #333; }
        p { color: #666; margin-bottom: 1.5rem; line-height: 1.5; }
        input[type="text"] { width: 100%; padding: 10px; margin-bottom: 1rem; border: 1px solid #ccc; border-radius: 4px; box-sizing: border-box; font-size: 1rem; }
        button { background-color: #007BFF; color: white; border: none; padding: 10px 20px; font-size: 1rem; border-radius: 4px; cursor: pointer; width: 100%; }
        button { background-color: #007BFF; color: white; border: none; padding: 10px 20px; font-size: 1rem; border-radius: 4px; cursor: pointer; width: 100%; }
        button:hover { background-color: #0056b3; }
        .success { color: green; display: none; margin-top: 1rem; font-weight: bold; }
        .instructions { background: #f9f9f9; padding: 1rem; border-radius: 4px; margin-bottom: 1.5rem; text-align: left; font-size: 0.95rem; border: 1px solid #eee; }
        .instructions h3 { margin-top: 0; color: #444; font-size: 1.1rem; }
        .instructions ol { padding-left: 1.5rem; margin-bottom: 1rem; color: #555; }
        .instructions li { margin-bottom: 0.5rem; }
        .instructions a { color: #007BFF; text-decoration: none; word-break: break-all; }
        .instructions a:hover { text-decoration: underline; }
        .note { font-size: 0.85rem; color: #666; background: #fff3cd; padding: 0.75rem; border-radius: 4px; border: 1px solid #ffeeba; margin-top: 1rem; margin-bottom: 0; }
    </style>
</head>
<body>
    <div class="container">
        <h1>TheGamesDB API Key Setup</h1>
        <div class="instructions">
            <h3>Getting TheGamesDB API Key</h3>
            <ol>
                <li>Go to <a href="https://thegamesdb.net/" target="_blank">https://thegamesdb.net/</a> and log in (or create an account if you don’t have one).</li>
                <li>After logging in, visit: <br><a href="https://api.thegamesdb.net/key.php" target="_blank">https://api.thegamesdb.net/key.php</a></li>
                <li>Request a new API key or retrieve your already requested key.</li>
                <li>Copy the key and paste it below.</li>
            </ol>
            <p class="note">The <strong>TheGamesDB API</strong> is limited to <strong>1,000 requests per IP address per month</strong>. If you need more than <strong>1,000 requests per month</strong>, you must <strong>register for a private API key</strong> through TheGamesDB. Private keys provide higher request limits and are recommended for heavy usage.</p>
        </div>
        <form id="keyForm" method="POST" action="/">
            <input type="text" name="apikey" id="apikey" placeholder="Enter your 64-character API key" required minlength="64" maxlength="64" autocomplete="off" spellcheck="false">
            <button type="submit">Submit Key</button>
        </form>
        <div id="successMsg" class="success">Key received! You can close this page and check your device.</div>
    </div>
    <script>
        document.getElementById('keyForm').onsubmit = function() {
            setTimeout(function() {
                document.getElementById('keyForm').style.display = 'none';
                document.getElementById('successMsg').style.display = 'block';
            }, 100);
            return true;
        };
    </script>
</body>
</html>
"""

class APIKeyHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        # Suppress automatic logging to stdout to keep it clean, or keep it for debugging
        pass

    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-type", "text/html")
        self.end_headers()
        self.wfile.write(HTML_TEMPLATE.encode("utf-8"))

    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length).decode('utf-8')
        parsed_data = urllib.parse.parse_qs(post_data)
        
        if 'apikey' in parsed_data:
            api_key = parsed_data['apikey'][0].strip()
            if len(api_key) >= 64: # At least 64 chars
                try:
                    with open(TMP_FILE, "w") as f:
                        f.write(api_key)
                    
                    self.send_response(200)
                    self.send_header("Content-type", "text/html")
                    self.end_headers()
                    # We just serve the same template, but the JS logic toggles visibility of success msg based on form submission
                    # The browser will handle it via the JS inside HTML_TEMPLATE
                    self.wfile.write(HTML_TEMPLATE.replace('display: none;', 'display: block;', 1).encode("utf-8")) # make success visible on reload
                    
                    print(f"API Key received and saved to {TMP_FILE}. Shutting down server...", flush=True)
                    # Shutdown server in a separate thread to allow response to finish sending
                    import threading
                    threading.Thread(target=self.server.shutdown).start()
                    return
                except Exception as e:
                    print(f"Error writing key: {e}", file=sys.stderr)
                    self.send_error(500, "Internal Server Error")
                    return
        
        self.send_error(400, "Bad Request: API Key missing or invalid length")

def main():
    try:
        # Avoid "address already in use"
        socketserver.TCPServer.allow_reuse_address = True
        with socketserver.TCPServer(("", PORT), APIKeyHandler) as httpd:
            print(f"Serving HTTP on port {PORT}... waiting for API key", flush=True)
            # handle requests until shutdown is called
            httpd.serve_forever()
                
    except OSError as e:
        print(f"Error starting server: {e}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("\nServer stopped manually.", flush=True)
        sys.exit(0)

if __name__ == "__main__":
    main()

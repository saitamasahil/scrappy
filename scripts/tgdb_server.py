import http.server
import socketserver
import urllib.parse
import os
import sys
import base64
import argparse

PORT = 8080
TMP_FILE = "/tmp/scrappy_tgdb_key.txt"

def build_html(theme="dark", accent="cbaa0f", logo_b64=""):
    """Build the HTML page with theme-aware styling."""
    is_dark = theme != "light"

    # Theme colors
    if is_dark:
        bg = "#0a0a0f"
        card_bg = "#16161e"
        card_border = "#2a2a35"
        text_primary = "#e4e4e8"
        text_secondary = "#9a9aa8"
        input_bg = "#1e1e28"
        input_border = "#3a3a45"
        input_focus_border = f"#{accent}"
        instructions_bg = "#12121a"
        instructions_border = "#2a2a35"
        note_bg = "#1a1a10"
        note_border = "#3a3520"
        note_text = "#d4c878"
        success_bg = "#0a1a0a"
        success_border = "#1a3a1a"
        success_text = "#4ade80"
        link_color = f"#{accent}"
        logo_filter = "none"
    else:
        bg = "#f0f0f4"
        card_bg = "#ffffff"
        card_border = "#e0e0e5"
        text_primary = "#1a1a2e"
        text_secondary = "#6a6a7a"
        input_bg = "#f5f5f8"
        input_border = "#d0d0d8"
        input_focus_border = f"#{accent}"
        instructions_bg = "#f8f8fc"
        instructions_border = "#e8e8ed"
        note_bg = "#fffdf0"
        note_border = "#f0e8c0"
        note_text = "#8a7a20"
        success_bg = "#f0fdf0"
        success_border = "#c0e8c0"
        success_text = "#22872d"
        link_color = f"#{accent}"
        logo_filter = "invert(1)"

    logo_section = ""
    if logo_b64:
        logo_section = f'''
        <div class="logo-container">
            <img src="data:image/png;base64,{logo_b64}" alt="Scrappy" class="logo" style="filter: {logo_filter};">
        </div>'''

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Scrappy &mdash; TheGamesDB API Key</title>
    <link rel="icon" type="image/png" href="data:image/png;base64,{logo_b64}">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap" rel="stylesheet">
    <style>
        * {{ margin: 0; padding: 0; box-sizing: border-box; }}

        body {{
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
            background: {bg};
            color: {text_primary};
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 1rem;
        }}

        .page {{
            width: 100%;
            max-width: 480px;
            animation: fadeInUp 0.6s ease-out;
        }}

        @keyframes popIn {{
            from {{ opacity: 0; transform: scale(0.9); }}
            to {{ opacity: 1; transform: scale(1); }}
        }}

        @keyframes fadeInUp {{
            from {{ opacity: 0; transform: translateY(20px); }}
            to {{ opacity: 1; transform: translateY(0); }}
        }}

        @keyframes logoReveal {{
            0% {{ opacity: 0; transform: scale(0); }}
            40% {{ opacity: 1; transform: scale(1.15); }}
            70% {{ transform: scale(0.95); }}
            100% {{ opacity: 1; transform: scale(1); }}
        }}

        @keyframes pulse {{
            0%, 100% {{ opacity: 0.6; }}
            50% {{ opacity: 1; }}
        }}

        .logo-container {{
            text-align: center;
            margin-bottom: 1.5rem;
        }}

        .logo {{
            height: 64px;
            animation: logoReveal 0.8s ease-out;
        }}

        .card {{
            background: {card_bg};
            border: 1px solid {card_border};
            border-radius: 16px;
            padding: 2rem;
            margin-bottom: 1rem;
        }}

        .card-header {{
            text-align: center;
            margin-bottom: 1.5rem;
        }}

        .card-header h1 {{
            font-size: 1.35rem;
            font-weight: 600;
            margin-bottom: 0.35rem;
            letter-spacing: -0.01em;
        }}

        .card-header .subtitle {{
            font-size: 0.85rem;
            color: {text_secondary};
        }}

        .divider {{
            height: 1px;
            background: {card_border};
            margin: 1.25rem 0;
        }}

        .instructions {{
            background: {instructions_bg};
            border: 1px solid {instructions_border};
            border-radius: 10px;
            padding: 1.25rem;
            margin-bottom: 1.5rem;
        }}

        .instructions h3 {{
            font-size: 0.9rem;
            font-weight: 600;
            margin-bottom: 0.75rem;
            color: {text_primary};
        }}

        .instructions ol {{
            padding-left: 1.25rem;
            margin: 0;
        }}

        .instructions li {{
            font-size: 0.85rem;
            color: {text_secondary};
            margin-bottom: 0.5rem;
            line-height: 1.5;
        }}

        .instructions li:last-child {{
            margin-bottom: 0;
        }}

        .instructions a {{
            color: {link_color};
            text-decoration: none;
            font-weight: 500;
        }}

        .instructions a:hover {{
            text-decoration: underline;
        }}

        .form-group {{
            margin-bottom: 1rem;
        }}

        .form-label {{
            display: block;
            font-size: 0.8rem;
            font-weight: 500;
            color: {text_secondary};
            margin-bottom: 0.4rem;
            text-transform: uppercase;
            letter-spacing: 0.05em;
        }}

        input[type="text"] {{
            width: 100%;
            padding: 12px 14px;
            background: {input_bg};
            border: 1.5px solid {input_border};
            border-radius: 10px;
            color: {text_primary};
            font-size: 0.95rem;
            font-family: 'Inter', monospace;
            transition: border-color 0.2s ease, box-shadow 0.2s ease;
            outline: none;
        }}

        input[type="text"]:focus {{
            border-color: {input_focus_border};
            box-shadow: 0 0 0 3px {input_focus_border}22;
        }}

        input[type="text"]::placeholder {{
            color: {text_secondary};
            opacity: 0.6;
        }}

        .btn {{
            width: 100%;
            padding: 12px 20px;
            background: #{accent};
            color: {"#000" if is_dark else "#fff"};
            border: none;
            border-radius: 10px;
            font-size: 0.95rem;
            font-weight: 600;
            font-family: 'Inter', sans-serif;
            cursor: pointer;
            transition: transform 0.15s ease, opacity 0.2s ease;
            letter-spacing: 0.01em;
        }}

        .btn:hover {{
            opacity: 0.9;
            transform: translateY(-1px);
        }}

        .btn:active {{
            transform: translateY(0px);
        }}

        .note {{
            background: {note_bg};
            border: 1px solid {note_border};
            border-radius: 8px;
            padding: 0.85rem 1rem;
            font-size: 0.8rem;
            color: {note_text};
            line-height: 1.5;
        }}

        .success-overlay {{
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(0, 0, 0, 0.7);
            display: none;
            align-items: center;
            justify-content: center;
            z-index: 100;
            backdrop-filter: blur(4px);
            -webkit-backdrop-filter: blur(4px);
        }}

        .success-overlay.visible {{
            display: flex;
        }}

        .success-card {{
            background: {card_bg};
            border: 1px solid {success_border};
            border-radius: 16px;
            padding: 2.5rem 3rem;
            text-align: center;
            animation: popIn 0.4s ease-out;
            max-width: 380px;
            width: 90%;
        }}

        .success-card .check {{
            width: 56px;
            height: 56px;
            background: {success_text};
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 1.8rem;
            color: {card_bg};
            margin: 0 auto 1rem;
            animation: logoReveal 0.5s ease-out;
        }}

        .success-card h2 {{
            font-size: 1.2rem;
            font-weight: 600;
            color: {success_text};
            margin-bottom: 0.5rem;
        }}

        .success-card p {{
            font-size: 0.9rem;
            color: {text_secondary};
            line-height: 1.5;
        }}

        .footer {{
            text-align: center;
            margin-top: 1rem;
            font-size: 0.75rem;
            color: {text_secondary};
            opacity: 0.6;
        }}

        .accent-dot {{
            display: inline-block;
            width: 8px;
            height: 8px;
            background: #{accent};
            border-radius: 50%;
            margin-right: 6px;
            animation: pulse 2s ease-in-out infinite;
        }}
    </style>
</head>
<body>
    <div class="page">
        {logo_section}

        <div class="card" id="mainCard">
            <div class="card-header">
                <h1>TheGamesDB API Key</h1>
                <span class="subtitle"><span class="accent-dot"></span>Add your API key for higher request limits</span>
            </div>

            <div class="instructions">
                <h3>How to get your API key</h3>
                <ol>
                    <li>Go to <a href="https://thegamesdb.net/" target="_blank">thegamesdb.net</a> and log in or create an account.</li>
                    <li>Visit <a href="https://api.thegamesdb.net/key.php" target="_blank">api.thegamesdb.net/key.php</a></li>
                    <li>Request a new API key or retrieve your existing key.</li>
                    <li>Copy the key and paste it below.</li>
                </ol>
            </div>

            <form id="keyForm" method="POST" action="/">
                <div class="form-group">
                    <label class="form-label" for="apikey">API Key</label>
                    <input type="text" name="apikey" id="apikey" placeholder="Paste your 64-character key here" required minlength="64" maxlength="64" autocomplete="off" spellcheck="false">
                </div>
                <button type="submit" class="btn">Submit Key</button>
            </form>

            <div class="divider"></div>

            <div class="note">
                Without an API key, TheGamesDB limits you to a very small number of requests. With a key, you get 1,000 requests per month per IP. For even higher limits, register for a private key through TheGamesDB.
            </div>
        </div>

        <div class="success-overlay" id="successOverlay">
            <div class="success-card">
                <div class="check">&#10003;</div>
                <h2>Key Saved Successfully</h2>
                <p>You can close this page now.<br>Scrappy will pick up the key automatically.</p>
            </div>
        </div>

        <div class="footer">Scrappy &bull; muOS Artwork Scraper</div>
    </div>
    <script>
        document.getElementById('keyForm').onsubmit = function() {{
            setTimeout(function() {{
                document.getElementById('successOverlay').classList.add('visible');
            }}, 150);
            return true;
        }};
    </script>
</body>
</html>"""


class APIKeyHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-type", "text/html")
        self.end_headers()
        self.wfile.write(html_page.encode("utf-8"))

    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length).decode('utf-8')
        parsed_data = urllib.parse.parse_qs(post_data)

        if 'apikey' in parsed_data:
            api_key = parsed_data['apikey'][0].strip()
            if len(api_key) >= 64:
                try:
                    with open(TMP_FILE, "w") as f:
                        f.write(api_key)

                    self.send_response(200)
                    self.send_header("Content-type", "text/html")
                    self.end_headers()
                    # Show success state - replace overlay class to make it visible on reload
                    success_html = html_page.replace('class="success-overlay"', 'class="success-overlay visible"', 1)
                    self.wfile.write(success_html.encode("utf-8"))

                    print(f"API Key received and saved to {TMP_FILE}. Shutting down server...", flush=True)
                    import threading
                    threading.Thread(target=self.server.shutdown).start()
                    return
                except Exception as e:
                    print(f"Error writing key: {e}", file=sys.stderr)
                    self.send_error(500, "Internal Server Error")
                    return

        self.send_error(400, "Bad Request: API Key missing or invalid length")


def main():
    global html_page

    parser = argparse.ArgumentParser()
    parser.add_argument("--theme", default="dark", choices=["dark", "light"])
    parser.add_argument("--accent", default="cbaa0f")
    parser.add_argument("--logo", default="")
    args = parser.parse_args()

    # Load and encode logo
    logo_b64 = ""
    if args.logo and os.path.isfile(args.logo):
        try:
            with open(args.logo, "rb") as f:
                logo_b64 = base64.b64encode(f.read()).decode("ascii")
        except Exception:
            pass

    html_page = build_html(theme=args.theme, accent=args.accent, logo_b64=logo_b64)

    try:
        socketserver.TCPServer.allow_reuse_address = True
        with socketserver.TCPServer(("", PORT), APIKeyHandler) as httpd:
            print(f"Serving HTTP on port {PORT}... waiting for API key", flush=True)
            httpd.serve_forever()

    except OSError as e:
        print(f"Error starting server: {e}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("\nServer stopped manually.", flush=True)
        sys.exit(0)

if __name__ == "__main__":
    main()

import http.server
import socketserver
import urllib.parse
import os
import sys
import base64
import argparse

PORT = 8084
TMP_FILE = "/tmp/scrappy_igdb_key.txt"

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
    <title>Scrappy &mdash; IGDB Credentials</title>
    <link rel="icon" type="image/png" href="data:image/png;base64,{logo_b64}">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Roboto:wght@400;500;700&display=swap" rel="stylesheet">
    <link href="https://fonts.googleapis.com/css2?family=Material+Symbols+Rounded:opsz,wght,FILL,GRAD@20..48,100..700,0..1,-50..200" rel="stylesheet" />
    <style>
        * {{ margin: 0; padding: 0; box-sizing: border-box; }}

        body {{
            font-family: 'Roboto', system-ui, sans-serif;
            background: {bg};
            color: {text_primary};
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 1rem;
            font-size: 14px;
            line-height: 20px;
            letter-spacing: 0.25px;
        }}

        .material-symbols-rounded {{
            font-size: 20px;
            line-height: 1;
            font-variation-settings: 'FILL' 0, 'wght' 400, 'GRAD' 0, 'opsz' 24;
            display: inline-block;
            vertical-align: middle;
        }}

        .page {{
            width: 100%;
            max-width: 500px;
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
            border-radius: 28px;
            padding: 2rem;
            margin-bottom: 1rem;
        }}

        .card-header {{
            text-align: center;
            margin-bottom: 1.5rem;
        }}

        .card-header h1 {{
            font-size: 24px;
            font-weight: 400;
            margin-bottom: 0.35rem;
        }}

        .card-header .subtitle {{
            font-size: 14px;
            color: {text_secondary};
            font-weight: 400;
        }}

        .divider {{
            height: 1px;
            background: {card_border};
            margin: 1.25rem 0;
            opacity: 0.5;
        }}

        .instructions {{
            background: {instructions_bg};
            border: 1px solid {instructions_border};
            border-radius: 12px;
            padding: 1.25rem;
            margin-bottom: 1.5rem;
        }}

        .instructions h3 {{
            font-size: 14px;
            font-weight: 500;
            margin-bottom: 0.75rem;
            color: {text_primary};
            display: flex;
            align-items: center;
            gap: 8px;
        }}

        .instructions ol {{
            padding-left: 1.25rem;
            margin: 0;
        }}

        .instructions li {{
            font-size: 14px;
            color: {text_secondary};
            margin-bottom: 0.5rem;
            line-height: 1.6;
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
            margin-bottom: 1.25rem;
        }}

        .form-label {{
            display: block;
            font-size: 12px;
            font-weight: 500;
            color: {text_secondary};
            margin-bottom: 0.5rem;
            letter-spacing: 0.5px;
        }}

        input[type="text"] {{
            width: 100%;
            padding: 14px 16px;
            background: transparent;
            border: 1px solid {input_border};
            border-radius: 4px;
            color: {text_primary};
            font-size: 14px;
            font-family: 'Roboto', sans-serif;
            transition: border-color 0.2s;
            outline: none;
        }}

        input[type="text"]:focus {{
            border-color: {input_focus_border};
            border-width: 2px;
            padding: 13px 15px;
        }}

        input[type="text"]::placeholder {{
            color: {text_secondary};
            opacity: 0.6;
        }}

        .btn {{
            width: 100%;
            height: 48px;
            padding: 0 24px;
            background: #{accent};
            color: {"#000" if is_dark else "#fff"};
            border: none;
            border-radius: 9999px;
            font-size: 14px;
            font-weight: 500;
            font-family: 'Roboto', sans-serif;
            cursor: pointer;
            transition: background 0.2s, box-shadow 0.2s;
            letter-spacing: 0.1px;
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 8px;
        }}

        .btn:hover {{
            box-shadow: 0px 1px 2px 0px rgba(0,0,0,0.3), 0px 1px 3px 1px rgba(0,0,0,0.15);
        }}

        .btn:active {{
            box-shadow: none;
        }}

        .note {{
            background: {note_bg};
            border: 1px solid {note_border};
            border-radius: 12px;
            padding: 1rem 1.25rem;
            font-size: 14px;
            color: {note_text};
            line-height: 1.6;
            display: flex;
            align-items: flex-start;
            gap: 10px;
        }}

        .note .material-symbols-rounded {{
            font-size: 20px;
            flex-shrink: 0;
            margin-top: 1px;
        }}

        .success-overlay {{
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(0, 0, 0, 0.5);
            display: none;
            align-items: center;
            justify-content: center;
            z-index: 100;
        }}

        .success-overlay.visible {{
            display: flex;
        }}

        .success-card {{
            background: {card_bg};
            border: none;
            border-radius: 28px;
            padding: 2.5rem 3rem;
            text-align: center;
            animation: popIn 0.4s ease-out;
            max-width: 380px;
            width: 90%;
            box-shadow: 0px 1px 3px 0px rgba(0,0,0,0.3), 0px 4px 8px 3px rgba(0,0,0,0.15);
        }}

        .success-card .check {{
            width: 56px;
            height: 56px;
            background: {success_text};
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            color: {card_bg};
            margin: 0 auto 1rem;
            animation: logoReveal 0.5s ease-out;
        }}

        .success-card .check .material-symbols-rounded {{
            font-size: 32px;
            font-variation-settings: 'FILL' 1, 'wght' 500, 'GRAD' 0, 'opsz' 24;
        }}

        .success-card h2 {{
            font-size: 24px;
            font-weight: 400;
            color: {success_text};
            margin-bottom: 0.5rem;
        }}

        .success-card p {{
            font-size: 14px;
            color: {text_secondary};
            line-height: 1.6;
        }}

        .footer {{
            text-align: center;
            margin-top: 1rem;
            font-size: 12px;
            color: {text_secondary};
            opacity: 0.5;
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
                <h1>IGDB Credentials</h1>
                <span class="subtitle"><span class="accent-dot"></span>Connect Scrappy to IGDB for rich metadata</span>
            </div>

            <div class="instructions">
                <h3><span class="material-symbols-rounded">info</span> How to setup IGDB</h3>
                <ol>
                    <li>Sign up/Log In for a <a href="https://www.twitch.tv/" target="_blank">Twitch account</a>.</li>
                    <li>Setup <a href="https://www.twitch.tv/settings/security" target="_blank">2FA in your profile</a> (if you haven't already) &mdash; you can't proceed without it.</li>
                    <li>Go to the <a href="https://dev.twitch.tv/console/apps/create" target="_blank">Twitch Developer Portal</a> and create a new application.</li>
                    <li>Fill any name/category, leave client type as-is. Set <code>https://localhost</code> in <b>OAuth Redirect URLs</b>.</li>
                    <li>Click <b>Manage</b>, scroll down, and copy your <b>Client ID</b> and <b>Client Secret</b>.</li>
                </ol>
            </div>

            <form id="credForm" method="POST" action="/">
                <div class="form-group">
                    <label class="form-label" for="client_id">Client ID</label>
                    <input type="text" name="client_id" id="client_id" placeholder="Paste your Twitch Client ID" required autocomplete="off" spellcheck="false">
                </div>
                <div class="form-group">
                    <label class="form-label" for="client_secret">Client Secret</label>
                    <input type="text" name="client_secret" id="client_secret" placeholder="Paste your Twitch Client Secret" required autocomplete="off" spellcheck="false">
                </div>
                <button type="submit" class="btn"><span class="material-symbols-rounded">save</span> Save Credentials</button>
            </form>

            <div class="divider"></div>

            <div class="note">
                <span class="material-symbols-rounded">lightbulb</span>
                <span>Scrappy uses IGDB to fetch high-quality artwork and metadata for your games. Your credentials are saved locally on this device.</span>
            </div>
        </div>

        <div class="success-overlay" id="successOverlay">
            <div class="success-card">
                <div class="check"><span class="material-symbols-rounded">check</span></div>
                <h2>Credentials Saved</h2>
                <p>You can close this page now.<br>Scrappy will pick up the credentials automatically.</p>
            </div>
        </div>

        <div class="footer">Scrappy &bull; muOS Artwork Scraper</div>
    </div>
    <script>
        document.getElementById('credForm').onsubmit = function(e) {{
            e.preventDefault();
            // Instantly show the success overlay for a premium, snappy visual response
            document.getElementById('successOverlay').classList.add('visible');
            
            // Post the credentials in the background
            var params = new URLSearchParams(new FormData(this));
            fetch('/', {{
                method: 'POST',
                body: params,
                headers: {{
                    'Content-Type': 'application/x-www-form-urlencoded'
                }}
            }}).catch(function(err) {{
                console.error("Save failed:", err);
            }});
        }};
    </script>
</body>
</html>"""


class CredHandler(http.server.SimpleHTTPRequestHandler):
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

        if 'client_id' in parsed_data and 'client_secret' in parsed_data:
            client_id = parsed_data['client_id'][0].strip()
            client_secret = parsed_data['client_secret'][0].strip()
            
            if client_id and client_secret:
                try:
                    # Save in format client_id:client_secret
                    with open(TMP_FILE, "w") as f:
                        f.write(f"{client_id}:{client_secret}")

                    self.send_response(200)
                    self.send_header("Content-type", "text/html")
                    self.end_headers()
                    success_html = html_page.replace('class="success-overlay"', 'class="success-overlay visible"', 1)
                    self.wfile.write(success_html.encode("utf-8"))

                    print(f"IGDB credentials received and saved to {TMP_FILE}. Shutting down server...", flush=True)
                    import threading
                    threading.Thread(target=self.server.shutdown).start()
                    return
                except Exception as e:
                    print(f"Error writing credentials: {e}", file=sys.stderr)
                    self.send_error(500, "Internal Server Error")
                    return

        self.send_error(400, "Bad Request: Credentials missing")


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
        with socketserver.TCPServer(("", PORT), CredHandler) as httpd:
            print(f"Serving HTTP on port {PORT}... waiting for IGDB credentials", flush=True)
            httpd.serve_forever()

    except OSError as e:
        print(f"Error starting server: {e}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("\nServer stopped manually.", flush=True)
        sys.exit(0)

if __name__ == "__main__":
    main()

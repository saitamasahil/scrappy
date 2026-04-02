import http.server
import socketserver
import json
import os
import sys
import base64
import argparse
import time
import re
import urllib.parse
import xml.etree.ElementTree as ET
from pathlib import Path
from datetime import datetime

PORT = 8083
REGEN_FILE = "/tmp/scrappy_tpl_regen.json"
PREVIEW_XML = "/tmp/scrappy_tpl_preview.xml"


class TemplateMakerHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # Suppress default logging

    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(204)
        self.end_headers()

    def do_GET(self):
        try:
            parsed = urllib.parse.urlparse(self.path)
            path = parsed.path
            qs = urllib.parse.parse_qs(parsed.query)

            if path == "/":
                self.serve_ui()
            elif path in ["/favicon.ico", "/favicon.png"]:
                self.serve_favicon()
            elif path == "/api/templates":
                self.api_list_templates()
            elif path.startswith("/api/template/"):
                name = urllib.parse.unquote(path[14:])
                self.api_get_template(name)
            elif path == "/api/resources":
                self.api_list_resources()
            elif path.startswith("/api/resource/"):
                rel = urllib.parse.unquote(path[14:])
                self.api_get_resource(rel)
            elif path.startswith("/api/sample-media/"):
                media_type = urllib.parse.unquote(path[18:])
                self.api_get_sample_media(media_type)
            elif path == "/api/preview":
                self.api_get_preview(qs)
            elif path.startswith("/api/preview-image/"):
                folder = urllib.parse.unquote(path[19:])
                self.api_get_preview_image(folder)
            else:
                self.send_error(404)
        except Exception as e:
            print(f"GET error: {e}")
            self.send_error(500, str(e))

    def do_POST(self):
        try:
            if self.path == "/api/preview":
                self.api_generate_preview()
            elif self.path == "/api/save":
                self.api_save_template()
            elif self.path == "/api/upload-resource":
                self.api_upload_resource()
            else:
                self.send_error(404)
        except Exception as e:
            print(f"POST error: {e}")
            self.send_error(500, str(e))

    def send_json(self, data, status=200):
        body = json.dumps(data).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-type", "application/json")
        self.send_header("Content-Length", len(body))
        self.end_headers()
        self.wfile.write(body)

    def serve_favicon(self):
        if args.logo and os.path.exists(args.logo):
            self.serve_file(args.logo)
        else:
            self.send_error(404)

    def serve_file(self, file_path, content_type=None):
        if not os.path.exists(file_path):
            self.send_error(404)
            return
        if not content_type:
            ext = os.path.splitext(file_path)[1].lower()
            content_type = {
                ".png": "image/png", ".jpg": "image/jpeg",
                ".jpeg": "image/jpeg", ".gif": "image/gif",
                ".webp": "image/webp", ".xml": "application/xml",
            }.get(ext, "application/octet-stream")
        with open(file_path, "rb") as f:
            data = f.read()
        self.send_response(200)
        self.send_header("Content-type", content_type)
        self.send_header("Content-Length", len(data))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(data)

    # ── API Endpoints ─────────────────────────────────────────────

    def api_list_templates(self):
        templates = []
        tpl_dir = args.templates_dir
        if os.path.isdir(tpl_dir):
            for f in sorted(os.listdir(tpl_dir)):
                if f.endswith(".xml"):
                    name = f[:-4]
                    path = os.path.join(tpl_dir, f)
                    try:
                        content = open(path).read()
                        # Extract output types
                        types = []
                        for t in ["cover", "screenshot", "wheel", "marquee", "texture"]:
                            if f'type="{t}"' in content:
                                types.append(t)
                        # Extract resolution
                        wm = re.search(r'<output [^>]*width="(\d+)"', content)
                        hm = re.search(r'<output [^>]*height="(\d+)"', content)
                        res = f"{wm.group(1)}x{hm.group(1)}" if wm and hm else None
                        templates.append({
                            "name": name, "types": types,
                            "resolution": res, "file": f
                        })
                    except:
                        templates.append({"name": name, "types": [], "file": f})
        self.send_json(templates)

    def api_get_template(self, name):
        path = os.path.join(args.templates_dir, name + ".xml")
        if not os.path.exists(path):
            path = os.path.join(args.templates_dir, name)
        if not os.path.exists(path):
            self.send_error(404, "Template not found")
            return
        with open(path) as f:
            content = f.read()
        self.send_json({"name": name, "xml": content})

    def api_list_resources(self):
        resources = {"masks": [], "frames": [], "other": []}
        res_dir = args.resources_dir
        if not os.path.isdir(res_dir):
            self.send_json(resources)
            return
        for item in sorted(os.listdir(res_dir)):
            full = os.path.join(res_dir, item)
            if os.path.isdir(full):
                category = item  # "mask", "frames"
                key = "masks" if "mask" in category else (
                    "frames" if "frame" in category else "other")
                for f in sorted(os.listdir(full)):
                    if f.lower().endswith((".png", ".jpg", ".jpeg")):
                        resources[key].append({
                            "name": f, "path": f"{item}/{f}",
                            "size": os.path.getsize(os.path.join(full, f))
                        })
            elif item.lower().endswith((".png", ".jpg", ".jpeg")):
                resources["other"].append({
                    "name": item, "path": item,
                    "size": os.path.getsize(full)
                })
        self.send_json(resources)

    def api_get_resource(self, rel_path):
        file_path = os.path.join(args.resources_dir, rel_path)
        if not os.path.exists(file_path):
            self.send_error(404)
            return
        self.serve_file(file_path)

    def api_get_sample_media(self, media_type):
        """Serve fake ROM sample media for preview reference."""
        type_map = {
            "cover": "covers", "screenshot": "screenshots",
            "wheel": "wheels", "marquee": "marquees",
            "texture": "textures"
        }
        folder = type_map.get(media_type, media_type)
        sample_dir = args.sample_dir
        # Check cache folder first (source images)
        cache_path = os.path.join(sample_dir, folder)
        if os.path.isdir(cache_path):
            for src_dir in sorted(os.listdir(cache_path)):
                src_path = os.path.join(cache_path, src_dir)
                if os.path.isdir(src_path):
                    for f in os.listdir(src_path):
                        fpath = os.path.join(src_path, f)
                        if os.path.isfile(fpath):
                            self.serve_file(fpath)
                            return
        self.send_error(404, f"No sample media for {media_type}")

    def api_get_preview(self, qs):
        """Serve the latest generated preview image."""
        sample_media = os.path.join(args.sample_dir, "media")
        
        target_folder = None
        if "type" in qs:
            val = qs["type"][0]
            type_map = { "cover": "covers", "screenshot": "screenshots", "wheel": "wheels", "marquee": "marquees", "texture": "textures" }
            target_folder = type_map.get(val, "covers")
            
        folders_to_check = [target_folder] if target_folder else ["covers", "screenshots", "wheels", "marquees", "textures"]

        for folder in folders_to_check:
            if not folder: continue
            path = os.path.join(sample_media, folder, "fake-rom.png")
            if os.path.exists(path):
                # Check for the LÖVE thread completion flag!
                done_file = "/tmp/scrappy_preview_done.txt"
                if not os.path.exists(done_file):
                    continue # Still generating! Wait for LÖVE to write this file.
                    
                # Check mtime if timestamp provided
                if "t" in qs:
                    mtime = os.path.getmtime(path)
                    self.send_response(200)
                    self.send_header("Content-type", "application/json")
                    self.end_headers()
                    self.wfile.write(json.dumps({
                        "ready": True, "mtime": mtime,
                        "url": f"/api/preview-image/{folder}"
                    }).encode())
                    return
                self.serve_file(path)
                return
        self.send_json({"ready": False}, 200)

    def api_get_preview_image(self, folder):
        """Serve a specific preview image by output folder."""
        sample_media = os.path.join(args.sample_dir, "media")
        path = os.path.join(sample_media, folder, "fake-rom.png")
        if os.path.exists(path):
            self.serve_file(path)
        else:
            self.send_error(404)

    last_preview_time = 0

    def api_generate_preview(self):
        """Accept XML, write temp file, signal Scrappy to generate preview."""
        # Simple throttle to prevent completely spamming Scrappy's queue
        current_time = time.time()
        if current_time - self.__class__.last_preview_time < 0.5:
            self.send_json({"status": "ignored", "message": "Throttled"})
            return
        self.__class__.last_preview_time = current_time

        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length).decode('utf-8')
        data = json.loads(body)
        xml_content = data.get("xml", "")

        if not xml_content.strip():
            self.send_json({"status": "error", "message": "Empty XML"}, 400)
            return

        # Remove any existing regen file to avoid duplicate picks by Scrappy's 1-sec poll
        if os.path.exists(REGEN_FILE):
            try: os.remove(REGEN_FILE)
            except: pass

        # Remove the 'done' lockfile so polling knows we're waiting
        done_file = "/tmp/scrappy_preview_done.txt"
        if os.path.exists(done_file):
            try: os.remove(done_file)
            except: pass

        # Write temp XML
        with open(PREVIEW_XML, "w") as f:
            f.write(xml_content)

        # Signal Scrappy to regenerate using this XML
        regen = {
            "xml_path": PREVIEW_XML,
            "timestamp": time.time()
        }
        with open(REGEN_FILE, "w") as f:
            json.dump(regen, f)

        self.send_json({"status": "ok", "message": "Preview generation requested"})

    def api_save_template(self):
        """Save XML as a template file."""
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length).decode('utf-8')
        data = json.loads(body)

        name = data.get("name", "").strip()
        xml = data.get("xml", "").strip()

        if not name or not xml:
            self.send_json({"status": "error", "message": "Name and XML required"}, 400)
            return

        # Sanitize name
        safe_name = "".join(c for c in name if c.isalnum() or c in "-_ ,.()").strip()
        if not safe_name:
            self.send_json({"status": "error", "message": "Invalid name"}, 400)
            return

        # Validate XML
        try:
            ET.fromstring(xml)
        except ET.ParseError as e:
            self.send_json({"status": "error", "message": f"Invalid XML: {e}"}, 400)
            return

        path = os.path.join(args.templates_dir, safe_name + ".xml")
        overwrite = data.get("overwrite", False)
        if os.path.exists(path) and not overwrite:
            self.send_json({
                "status": "exists",
                "message": f"Template '{safe_name}' already exists. Set overwrite=true to replace."
            }, 409)
            return

        with open(path, "w") as f:
            f.write(xml)

        self.send_json({"status": "ok", "name": safe_name, "file": safe_name + ".xml"})

    def api_upload_resource(self):
        """Upload a custom mask/frame PNG."""
        content_type = self.headers.get('Content-Type', '')
        if 'boundary=' not in content_type:
            self.send_json({"status": "error", "message": "Expected multipart"}, 400)
            return

        boundary = content_type.split('boundary=')[1].encode()
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)
        parts = body.split(b'--' + boundary)

        params = {}
        file_data = None
        filename = None

        for part in parts:
            if b'Content-Disposition: form-data;' not in part:
                continue
            try:
                head, bdy = part.split(b'\r\n\r\n', 1)
                head = head.decode()
                name_match = head.split('name="')[1].split('"')[0]
                if 'filename="' in head:
                    filename = head.split('filename="')[1].split('"')[0]
                    file_data = bdy.rsplit(b'\r\n', 1)[0]
                else:
                    params[name_match] = bdy.rsplit(b'\r\n', 1)[0].decode()
            except:
                pass

        category = params.get("category", "mask")  # "mask" or "frames"
        if not file_data or not filename:
            self.send_json({"status": "error", "message": "No file uploaded"}, 400)
            return

        dest_dir = os.path.join(args.resources_dir, category)
        os.makedirs(dest_dir, exist_ok=True)
        dest_path = os.path.join(dest_dir, filename)

        with open(dest_path, "wb") as f:
            f.write(file_data)

        rel_path = f"{category}/{filename}"
        self.send_json({"status": "ok", "path": rel_path, "name": filename})

    # ── HTML UI ───────────────────────────────────────────────────

    def serve_ui(self):
        html = build_html(
            theme=args.theme, accent=args.accent,
            logo_b64=get_logo_b64(args.logo)
        )
        body = html.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-type", "text/html")
        self.send_header("Content-Length", len(body))
        self.end_headers()
        self.wfile.write(body)


def get_logo_b64(path):
    if not path or not os.path.exists(path):
        return ""
    try:
        with open(path, "rb") as f:
            return base64.b64encode(f.read()).decode("utf-8")
    except:
        return ""


def build_html(theme="dark", accent="cbaa0f", logo_b64=""):
    """Load the HTML template and inject theme variables."""
    is_dark = "light" not in theme.lower()

    replacements = {
        "%%BG%%": "#0a0a0f" if is_dark else "#f4f4f9",
        "%%CARD_BG%%": "#16161e" if is_dark else "#ffffff",
        "%%CARD_BORDER%%": "#2a2a35" if is_dark else "#e1e1e8",
        "%%TEXT_PRIMARY%%": "#e4e4e8" if is_dark else "#1a1a2e",
        "%%TEXT_SECONDARY%%": "#9a9aa8" if is_dark else "#5c5c6d",
        "%%ACCENT%%": f"#{accent}",
        "%%INPUT_BG%%": "#1e1e28" if is_dark else "#f5f5f8",
        "%%HEADER_BG%%": "rgba(10, 10, 15, 0.9)" if is_dark else "rgba(255, 255, 255, 0.9)",
        "%%PANEL_BG%%": "#12121a" if is_dark else "#f8f8fc",
        "%%HOVER_BG%%": "#2a2a38" if is_dark else "#e8e8f0",
        "%%LOGO_B64%%": logo_b64,
        "%%LOGO_FILTER%%": "none" if is_dark else "invert(1)",
    }

    # Load template HTML file
    html_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "template_maker_ui.html")
    try:
        with open(html_path, "r") as f:
            html = f.read()
        for key, val in replacements.items():
            html = html.replace(key, val)
        return html
    except FileNotFoundError:
        return f"<html><body><h1>Error: template_maker_ui.html not found at {html_path}</h1></body></html>"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Scrappy Template Maker")
    parser.add_argument("--theme", default="dark")
    parser.add_argument("--accent", default="cbaa0f")
    parser.add_argument("--logo", default="")
    parser.add_argument("--templates-dir", required=True)
    parser.add_argument("--resources-dir", required=True)
    parser.add_argument("--sample-dir", required=True)
    args = parser.parse_args()

    socketserver.ThreadingTCPServer.allow_reuse_address = True
    socketserver.ThreadingTCPServer.daemon_threads = True
    with socketserver.ThreadingTCPServer(("", PORT), TemplateMakerHandler) as httpd:
        print(f"Template Maker serving at port {PORT}")
        print(f"Templates: {args.templates_dir}")
        print(f"Resources: {args.resources_dir}")
        print(f"Sample: {args.sample_dir}")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nServer stopped.")

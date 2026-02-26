import http.server
import socketserver
import json
import os
import sys
import base64
import argparse
import time
import threading
import urllib.parse
import xml.etree.ElementTree as ET
import shutil
from datetime import datetime
from pathlib import Path

PORT = 8082
REGEN_FILE = "/tmp/scrappy_regen.json"

class ArtworkManagerHandler(http.server.BaseHTTPRequestHandler):
    def send_json_error(self, status_code, message, detail=None):
        payload = {"status": "error", "message": message}
        if detail is not None:
            payload["detail"] = str(detail)

        try:
            self.send_response(status_code)
            self.send_header("Content-type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(payload).encode("utf-8"))
        except Exception as e:
            # Fallback to plain send_error if JSON response itself fails
            try:
                self.send_error(status_code, f"{message} ({e})")
            except Exception:
                pass
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
            parsed_url = urllib.parse.urlparse(self.path)
            path = parsed_url.path

            if path == "/":
                self.serve_ui()
            elif path in ["/favicon.ico", "/favicon.png"]:
                self.serve_favicon()
            elif path == "/api/cache":
                self.api_get_platforms()
            elif path.startswith("/api/games/"):
                platform = urllib.parse.unquote(path[11:])
                self.api_get_games(platform)
            elif path == "/api/templates":
                self.api_get_templates()
            elif path == "/api/config":
                self.api_get_config()
            elif path.startswith("/api/media/"):
                self.api_get_media(path)
            elif path.startswith("/api/output/"):
                self.api_get_output_media(path)
            else:
                self.send_error(404)
        except Exception as e:
            print(f"Exception in do_GET: {e}")
            self.send_error(500, str(e))

    def serve_favicon(self):
        # Reuse the same logo file passed to the server, if available.
        if args.logo and os.path.exists(args.logo):
            self.serve_file(args.logo)
            return
        # If no logo, send 404
        self.send_error(404)

    def do_POST(self):
        if self.path == "/api/regenerate":
            self.api_regenerate()
        elif self.path == "/api/upload":
            self.api_upload()
        else:
            self.send_error(404)

    def serve_ui(self):
        html = build_html(
            theme=args.theme,
            accent=args.accent,
            logo_b64=get_logo_b64(args.logo)
        )
        self.send_response(200)
        self.send_header("Content-type", "text/html")
        self.end_headers()
        self.wfile.write(html.encode("utf-8"))

    def api_get_platforms(self):
        platforms = []
        if os.path.exists(args.cache):
            for item in sorted(os.listdir(args.cache)):
                p_path = os.path.join(args.cache, item)
                if os.path.isdir(p_path) and os.path.exists(os.path.join(p_path, "db.xml")):
                    platforms.append(item)
        
        self.send_response(200)
        self.send_header("Content-type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(platforms).encode("utf-8"))

    def api_get_games(self, platform):
        p_path = os.path.join(args.cache, platform)
        quickid_path = os.path.join(p_path, "quickid.xml")
        db_path = os.path.join(p_path, "db.xml")

        if not os.path.exists(quickid_path) or not os.path.exists(db_path):
            self.send_error(400, "Missing cache XML files")
            return

        # Map ROM filename -> ID
        rom_map = {}
        try:
            tree = ET.parse(quickid_path)
            for q in tree.findall("quickid"):
                filepath = q.get("filepath")
                id = q.get("id")
                if filepath and id:
                    filename = os.path.basename(filepath)
                    rom_map[id] = filename
        except Exception as e:
            print(f"Error parsing quickid.xml: {e}")

        # Map ID -> resources
        if not os.path.exists(db_path):
            print(f"db.xml not found at {db_path}")
            return
            
        games = []
        try:
            tree = ET.parse(db_path)
            game_data = {} # id -> {rom -> name, media -> {type -> [{source, file}]}}
            for res in tree.findall("resource"):
                gid = res.get("id")
                rtype = res.get("type", "").lower()
                if gid not in game_data:
                    game_data[gid] = {"rom": rom_map.get(gid, gid), "media": {}}
                
                path = res.text
                if path:
                    source_type = res.get("source")
                    # Extract the type-specific filename (which is the SHA1/ID)
                    filename = os.path.basename(path)
                    
                    if rtype not in game_data[gid]["media"]:
                        game_data[gid]["media"][rtype] = []
                    
                    game_data[gid]["media"][rtype].append({
                        "source": source_type,
                        "file": filename,
                        "path": path # The full relative path from db.xml
                    })
            
            for gid, data in game_data.items():
                games.append({
                    "id": gid,
                    "rom": data["rom"],
                    "media": data["media"]
                })
        except Exception as e:
            print(f"Error parsing db.xml: {e}")

        # Sort games by ROM name
        games.sort(key=lambda x: x["rom"].lower())

        self.send_response(200)
        self.send_header("Content-type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(games).encode("utf-8"))

    def api_get_templates(self):
        templates = []
        templates_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "templates")
        if os.path.exists(templates_dir):
            for f in sorted(os.listdir(templates_dir)):
                if f.endswith(".xml"):
                    templates.append(f[:-4]) # Remove .xml extension for display
        
        self.send_response(200)
        self.send_header("Content-type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(templates).encode("utf-8"))

    def api_get_config(self):
        # We need to find the actual config file. Scrappy's tools.lua spawns us with --cache.
        # Usually config is in the same parent dir as cache, or in the work dir.
        config_data = {"artworkXml": "box2d"}
        
        # Try to find skyscraper_config.ini in work dir
        work_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        config_path = os.path.join(work_dir, "skyscraper_config.ini")
        
        if os.path.exists(config_path):
            try:
                with open(config_path, "r") as f:
                    for line in f:
                        if line.startswith("artworkXml"):
                            val = line.split("=")[1].strip().strip('"')
                            # Extract filename without extension and path
                            filename = os.path.basename(val)
                            if filename.endswith(".xml"):
                                filename = filename[:-4]
                            config_data["artworkXml"] = filename
                            break
            except:
                pass

        self.send_response(200)
        self.send_header("Content-type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(config_data).encode("utf-8"))

    def api_get_media(self, media_path):
        # /api/media/Platform/RelPathToMedia
        # rel_path is the exact path from db.xml
        parts = media_path.split("/")
        if len(parts) < 5:
            self.send_error(400)
            return
        
        platform = urllib.parse.unquote(parts[3])
        # Join all remaining parts to get the full relative path
        rel_path = "/".join([urllib.parse.unquote(p) for p in parts[4:]])

        file_path = os.path.join(args.cache, platform, rel_path)
        self.serve_file(file_path)

    def api_get_output_media(self, media_path):
        # /api/output/Platform/RomBase.png
        parts = media_path.split("/")
        if len(parts) < 5:
            self.send_error(400)
            return
        
        platform = urllib.parse.unquote(parts[3])
        rom_base = urllib.parse.unquote(parts[4])
        
        # Output is usually in data/output relative to work_dir
        work_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        # Check skyscraper_config for gameListFolder if possible, but default to data/output
        output_dir = os.path.join(work_dir, "data", "output")
        
        # Scrappy's artwork.lua uses {output_dir}/{platform}/media/covers/{rom_base}.png
        file_path = os.path.join(output_dir, platform, "media", "covers", rom_base)
        if not file_path.lower().endswith(".png"):
            file_path += ".png"
            
        self.serve_file(file_path)

    def serve_file(self, file_path):
        if not os.path.exists(file_path):
            self.send_error(404)
            return

        self.send_response(200)
        
        # Detect actual mime type
        mime_type = "image/png" # Default
        try:
            with open(file_path, "rb") as f:
                header = f.read(10)
                if header.startswith(b"\x89PNG"):
                    mime_type = "image/png"
                elif header.startswith(b"\xff\xd8"):
                    mime_type = "image/jpeg"
                elif header.startswith(b"GIF8"):
                    mime_type = "image/gif"
                elif b"WEBP" in header:
                    mime_type = "image/webp"
        except:
            pass
            
        self.send_header("Content-type", mime_type)
        self.send_header("Content-Length", os.path.getsize(file_path))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        with open(file_path, "rb") as f:
            self.wfile.write(f.read())

    def api_regenerate(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)
        data = json.loads(post_data.decode('utf-8'))

        platform = data.get("platform")
        rom = data.get("rom")
        xml = data.get("xml", "box2d")

        if not platform or not rom:
            self.send_error(400, "Missing platform or rom")
            return

        # Write to regen file for Lua to pick up
        regen_req = {
            "platform": platform,
            "rom": rom,
            "xml": xml,
            "timestamp": time.time()
        }
        with open(REGEN_FILE, "w") as f:
            json.dump(regen_req, f)

        self.send_response(200)
        self.send_header("Content-type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({"status": "ok"}).encode("utf-8"))

    def api_upload(self):
        # Multipart form data parsing
        content_type = self.headers.get('Content-Type')
        if not content_type or 'boundary=' not in content_type:
            self.send_json_error(400, "Content-Type must be multipart/form-data")
            return
            
        boundary = content_type.split('boundary=')[1].encode()
        try:
            content_length = int(self.headers.get('Content-Length'))
            body = self.rfile.read(content_length)
        except Exception as e:
            self.send_json_error(400, "Error reading request body", detail=e)
            return

        parts = body.split(b'--' + boundary)
        params = {}
        file_data = None
        
        for part in parts:
            if b'Content-Disposition: form-data;' in part:
                try:
                    head, bdy = part.split(b'\r\n\r\n', 1)
                    head = head.decode()
                    name_match = urllib.parse.unquote(head).split('name="')[1].split('"')[0]

                    if 'filename="' in head:
                        try:
                            orig_name = head.split('filename="')[1].split('"')[0]
                            params['uploaded_ext'] = os.path.splitext(orig_name)[1].lower()
                        except Exception:
                            params['uploaded_ext'] = ".png"
                        file_data = bdy.rsplit(b'\r\n', 1)[0]
                    else:
                        params[name_match] = bdy.rsplit(b'\r\n', 1)[0].decode()
                except Exception as e:
                    print(f"Error parsing part: {e}")

        gid = params.get("gid")
        platform = params.get("platform")
        mtype = params.get("type")
        source = params.get("source")

        if not all([gid, platform, mtype, file_data]):
            self.send_json_error(
                400,
                "Missing upload data",
                detail=f"gid={gid}, platform={platform}, type={mtype}",
            )
            return

        mtype_lower = mtype.lower()
        type_map = {
            "cover": "covers",
            "screenshot": "screenshots",
            "wheel": "wheels",
            "marquee": "marquees",
            "video": "videos",
            "texture": "textures",
        }
        folder_type = type_map.get(mtype_lower, mtype_lower)
        if not folder_type.endswith('s') and folder_type not in ["covers", "wheels", "marquees"]:
             folder_type += 's'

        cache_root = Path(args.cache)
        platform_root = cache_root / platform

        # Extension handling: If it's a cover/wheel, Skyscraper often expects no extension in db.xml
        # but the file MUST exist. We'll save as {gid}{ext} and also {gid} to be safe if it's the standard source.
        ext = params.get('uploaded_ext', '.png')
        final_filename = gid + ext

        type_root = platform_root / folder_type
        try:
            type_root.mkdir(parents=True, exist_ok=True)
        except Exception as e:
            self.send_json_error(500, "Failed to create media type directory", detail=e)
            return

        # 1. Aggressive cleanup of ALL sources for this GID in this type folder
        try:
            for src_dir in type_root.iterdir():
                if src_dir.is_dir():
                    for p in src_dir.iterdir():
                        if p.is_file() and p.stem == gid:
                            try:
                                p.unlink()
                            except Exception:
                                # Ignore individual file removal errors
                                pass
        except Exception:
            # Ignore traversal errors; they'll surface later if files still exist
            pass

        # 2. Save new file to 'local'
        dest_dir = type_root / "local"
        try:
            dest_dir.mkdir(parents=True, exist_ok=True)
        except Exception as e:
            self.send_json_error(500, "Failed to create local media directory", detail=e)
            return

        dest_path = dest_dir / final_filename

        try:
            with open(dest_path, "wb") as f:
                f.write(file_data)
            # Also save a version without extension if standard Skyscraper behavior suggests it
            if folder_type in ["covers", "wheels", "marquees"]:
                no_ext_path = dest_dir / gid
                shutil.copy2(str(dest_path), str(no_ext_path))
        except Exception as e:
            self.send_json_error(500, "Failed to write uploaded media file", detail=e)
            return

        # 3. Update db.xml
        db_path = platform_root / "db.xml"
        fs_rel_path = f"{folder_type}/local/{final_filename}"

        # Determine what path to put in db.xml.
        # For screenshots, usually includes extension. For covers/wheels, usually does NOT.
        db_rel_path = fs_rel_path
        if folder_type in ["covers", "wheels", "marquees"]:
            db_rel_path = f"{folder_type}/local/{gid}"

        if not db_path.exists():
            self.send_json_error(500, "db.xml not found for platform", detail=db_path)
            return

        try:
            tree = ET.parse(str(db_path))
            root = tree.getroot()

            # Remove all existing resources for this ID and Type
            to_remove = []
            for res in root.findall("resource"):
                if res.get("id") == gid and res.get("type", "").lower() == mtype_lower:
                    to_remove.append(res)

            for res in to_remove:
                root.remove(res)

            # Add new local resource
            new_res = ET.SubElement(root, "resource")
            new_res.set("id", gid)
            new_res.set("type", mtype_lower)
            new_res.set("source", "local")
            new_res.set("timestamp", str(int(time.time() * 1000)))
            new_res.text = db_rel_path

            tree.write(str(db_path), encoding="utf-8", xml_declaration=True)
        except Exception as e:
            self.send_json_error(500, "Failed to update db.xml", detail=e)
            return

        # 4. Validate final path used for previews
        preview_path = platform_root / db_rel_path
        if not preview_path.exists():
            # Fallback to the actual file path with extension, just in case
            alt_preview_path = platform_root / fs_rel_path
            if not alt_preview_path.exists():
                self.send_json_error(
                    500,
                    "Media file appears to be missing after upload",
                    detail=f"expected={preview_path}, alt={alt_preview_path}",
                )
                return

        self.send_response(200)
        self.send_header("Content-type", "application/json")
        self.end_headers()
        # new_path uses the db.xml-style relative path so UI and db.xml stay consistent
        self.wfile.write(json.dumps({"status": "ok", "new_path": db_rel_path}).encode("utf-8"))

def get_logo_b64(path):
    if not path or not os.path.exists(path):
        return ""
    try:
        with open(path, "rb") as f:
            return base64.b64encode(f.read()).decode("utf-8")
    except:
        return ""

def build_html(theme="dark", accent="cbaa0f", logo_b64=""):
    is_dark = "light" not in theme.lower()
    
    bg = "#0a0a0f" if is_dark else "#f4f4f9"
    card_bg = "#16161e" if is_dark else "#ffffff"
    card_border = "#2a2a35" if is_dark else "#e1e1e8"
    text_primary = "#e4e4e8" if is_dark else "#1a1a2e"
    text_secondary = "#9a9aa8" if is_dark else "#5c5c6d"
    input_bg = "#1e1e28" if is_dark else "#ffffff"
    header_bg = "rgba(10, 10, 15, 0.8)" if is_dark else "rgba(255, 255, 255, 0.8)"
    tab_bar_bg = "rgba(0, 0, 0, 0.2)" if is_dark else "rgba(0, 0, 0, 0.03)"
    badge_bg = "rgba(255, 255, 255, 0.05)" if is_dark else "rgba(0, 0, 0, 0.05)"
    thumb_bg = "#000000" if is_dark else "#f0f0f5"
    modal_item_bg = "rgba(0, 0, 0, 0.2)" if is_dark else "rgba(0, 0, 0, 0.03)"
    tpl_select_bg = "rgba(0, 0, 0, 0.1)" if is_dark else "rgba(0, 0, 0, 0.02)"

    return f"""
<!DOCTYPE html>
<html>
<head>
    <title>Scrappy Artwork Manager</title>
    <link rel="icon" type="image/png" href="/favicon.png">
    <link rel="shortcut icon" type="image/png" href="/favicon.png">
    <link rel="apple-touch-icon" href="/favicon.png">
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
    <style>
        :root {{
            --bg: {bg};
            --card-bg: {card_bg};
            --card-border: {card_border};
            --text-primary: {text_primary};
            --text-secondary: {text_secondary};
            --accent: #{accent};
            --input-bg: {input_bg};
            --header-bg: {header_bg};
            --tab-bar-bg: {tab_bar_bg};
            --badge-bg: {badge_bg};
            --thumb-bg: {thumb_bg};
            --modal-item-bg: {modal_item_bg};
            --tpl-select-bg: {tpl_select_bg};
        }}
        
        * {{ box-sizing: border-box; -webkit-tap-highlight-color: transparent; }}
        body {{
            background: var(--bg);
            color: var(--text-primary);
            font-family: 'Inter', sans-serif;
            margin: 0;
            padding: 0;
            display: flex;
            flex-direction: column;
            min-height: 100vh;
        }}

        header {{
            background: var(--header-bg);
            backdrop-filter: blur(10px);
            padding: 20px;
            text-align: center;
            border-bottom: 1px solid var(--card-border);
            position: sticky;
            top: 0;
            z-index: 100;
        }}

        .logo-container {{
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 15px;
            animation: logoReveal 1s cubic-bezier(0.2, 0.8, 0.2, 1);
        }}

        .logo {{ height: 40px; }}
        .title-group {{ text-align: center; }}
        h1 {{ margin: 0; font-size: 20px; font-weight: 700; letter-spacing: -0.5px; }}
        .status-dot {{
            display: inline-block;
            width: 8px;
            height: 8px;
            background: var(--accent);
            border-radius: 50%;
            margin-right: 8px;
            box-shadow: 0 0 10px var(--accent);
            animation: blink 2s ease-in-out infinite;
        }}

        @keyframes blink {{
            0%, 100% {{ opacity: 1; }}
            50% {{ opacity: 0.3; }}
        }}

        .status-subtitle {{
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 13px;
            color: var(--text-secondary);
            margin-top: 5px;
            font-weight: 500;
        }}

        #platform-tabs {{
            display: flex;
            gap: 10px;
            padding: 15px;
            overflow-x: auto;
            background: var(--tab-bar-bg);
            scrollbar-width: none;
        }}
        #platform-tabs::-webkit-scrollbar {{ display: none; }}

        .tab {{
            padding: 8px 16px;
            background: var(--card-bg);
            border: 1px solid var(--card-border);
            border-radius: 20px;
            color: var(--text-secondary);
            white-space: nowrap;
            cursor: pointer;
            font-weight: 500;
            font-size: 14px;
            transition: all 0.2s;
        }}
        .tab.active {{
            background: var(--accent);
            color: #fff;
            border-color: var(--accent);
        }}

        main {{
            flex: 1;
            padding: 20px;
            max-width: 1200px;
            margin: 0 auto;
            width: 100%;
        }}

        .search-container {{
            margin-bottom: 20px;
            position: relative;
        }}
        #search-input {{
            width: 100%;
            background: var(--input-bg);
            border: 1px solid var(--card-border);
            border-radius: 12px;
            padding: 12px 15px;
            color: var(--text-primary);
            font-family: inherit;
            font-size: 16px;
            outline: none;
            transition: border-color 0.2s;
        }}
        #search-input:focus {{ border-color: var(--accent); }}

        #game-grid {{
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
            gap: 20px;
        }}

        .game-card {{
            background: var(--card-bg);
            border: 1px solid var(--card-border);
            border-radius: 16px;
            overflow: hidden;
            transition: transform 0.2s, border-color 0.2s;
            cursor: pointer;
            display: flex;
            flex-direction: column;
            animation: fadeInUp 0.5s ease-out backwards;
        }}
        .game-card:hover {{
            transform: translateY(-4px);
            border-color: var(--accent);
        }}

        .thumb-wrapper {{
            aspect-ratio: 4/3;
            background: var(--thumb-bg);
            display: flex;
            align-items: center;
            justify-content: center;
            overflow: hidden;
            position: relative;
        }}
        .thumb-wrapper img {{
            width: 100%;
            height: 100%;
            object-fit: contain;
        }}
        .no-thumb {{ color: var(--text-secondary); font-size: 12px; }}

        .game-info {{
            padding: 12px;
            flex: 1;
        }}
        .game-title {{
            font-size: 13px;
            font-weight: 600;
            margin-bottom: 8px;
            display: -webkit-box;
            -webkit-line-clamp: 2;
            -webkit-box-orient: vertical;
            overflow: hidden;
            line-height: 1.4;
        }}
        .type-badges {{
            display: flex;
            flex-wrap: wrap;
            gap: 4px;
        }}
        .badge {{
            font-size: 9px;
            text-transform: uppercase;
            padding: 2px 5px;
            border-radius: 4px;
            background: var(--badge-bg);
            color: var(--text-secondary);
            font-weight: 700;
        }}

        /* Modal Styles */
        #modal-overlay {{
            position: fixed;
            top: 0; left: 0; right: 0; bottom: 0;
            background: rgba(0,0,0,0.85);
            backdrop-filter: blur(8px);
            z-index: 1000;
            display: none;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }}
        #modal {{
            background: var(--card-bg);
            border: 1px solid var(--card-border);
            border-radius: 24px;
            width: 100%;
            max-width: 600px;
            max-height: 90vh;
            overflow-y: auto;
            position: relative;
            padding-bottom: 80px;
        }}
        .modal-header {{
            padding: 20px;
            border-bottom: 1px solid var(--card-border);
            position: sticky;
            top: 0;
            background: var(--card-bg);
            display: flex;
            justify-content: space-between;
            align-items: flex-start;
        }}
        .modal-header h2 {{ margin: 0; font-size: 18px; }}
        .close-btn {{
            background: none;
            border: none;
            color: var(--text-secondary);
            font-size: 24px;
            cursor: pointer;
        }}

        .media-list {{ padding: 20px; display: flex; flex-direction: column; gap: 20px; }}
        .media-item {{
            background: var(--modal-item-bg);
            border-radius: 16px;
            padding: 15px;
            border: 1px solid var(--card-border);
        }}
        .media-label {{
            font-size: 12px;
            font-weight: 700;
            text-transform: uppercase;
            color: var(--accent);
            margin-bottom: 10px;
            display: flex;
            justify-content: space-between;
        }}
        .media-preview-container {{
            width: 100%;
            aspect-ratio: 16/9;
            background: var(--thumb-bg);
            border-radius: 8px;
            margin-bottom: 15px;
            display: flex;
            align-items: center;
            justify-content: center;
        }}
        .media-preview-container img {{
            max-width: 100%;
            max-height: 100%;
            object-fit: contain;
        }}
        
        .action-group {{
            display: flex;
            gap: 10px;
        }}
        .btn {{
            flex: 1;
            padding: 10px;
            border-radius: 10px;
            border: none;
            font-family: inherit;
            font-weight: 600;
            font-size: 14px;
            cursor: pointer;
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 8px;
            transition: opacity 0.2s;
        }}
        .btn:active {{ opacity: 0.7; }}
        .btn-upload {{ background: var(--accent); color: white; }}
        .btn-regen {{ background: #27ae60; color: white; }}
        
        #modal-actions {{
            position: absolute;
            bottom: 0;
            left: 0;
            right: 0;
            padding: 15px 20px;
            background: var(--card-bg);
            border-top: 1px solid var(--card-border);
            display: none; /* We're moving them into the list */
        }}

        .template-selector {{
            padding: 20px;
            background: var(--tpl-select-bg);
            border-radius: 16px;
            margin: 20px;
            border: 1px solid var(--card-border);
        }}
        .template-list {{
            display: flex;
            gap: 10px;
            overflow-x: auto;
            padding: 10px 0;
            scrollbar-width: thin;
        }}
        .template-chip {{
            padding: 8px 15px;
            border-radius: 20px;
            background: var(--card-bg);
            border: 1px solid var(--card-border);
            color: var(--text-secondary);
            font-size: 13px;
            white-space: nowrap;
            cursor: pointer;
            transition: all 0.2s;
        }}
        .template-chip.active {{
            background: var(--accent);
            border-color: var(--accent);
            color: white;
        }}
        .scroll-hint {{
            font-size: 11px;
            color: var(--text-secondary);
            text-align: right;
            margin-top: 5px;
            opacity: 0.6;
        }}

        #toast {{
            position: fixed;
            bottom: 30px;
            left: 50%;
            transform: translateX(-50%);
            background: var(--accent);
            color: white;
            padding: 12px 24px;
            border-radius: 30px;
            font-weight: 600;
            box-shadow: 0 10px 30px rgba(0,0,0,0.5);
            display: none;
            z-index: 2000;
        }}

        @keyframes fadeInUp {{
            from {{ opacity: 0; transform: translateY(10px); }}
            to {{ opacity: 1; transform: translateY(0); }}
        }}
        @keyframes logoReveal {{
            0% {{ opacity: 0; transform: scale(0); }}
            40% {{ opacity: 1; transform: scale(1.15); }}
            70% {{ transform: scale(0.95); }}
            100% {{ opacity: 1; transform: scale(1); }}
        }}
        @keyframes pulse {{
            0% {{ box-shadow: 0 0 0 0 rgba(203, 170, 15, 0.4); }}
            70% {{ box-shadow: 0 0 0 10px rgba(203, 170, 15, 0); }}
            100% {{ box-shadow: 0 0 0 0 rgba(203, 170, 15, 0); }}
        }}

        footer {{
            padding: 30px 20px;
            text-align: center;
            font-size: 12px;
            color: var(--text-secondary);
            border-top: 1px solid var(--card-border);
            margin-top: 40px;
        }}

        /* Responsive adjustments */
        @media (max-width: 480px) {{
            #game-grid {{ grid-template-columns: repeat(2, 1fr); gap: 12px; }}
            .game-card {{ border-radius: 12px; }}
            .media-item {{ padding: 10px; }}
        }}
    </style>
</head>
<body>
    <header>
        <div class="logo-container">
            <img src="data:image/png;base64,{logo_b64}" class="logo" onerror="this.style.display='none'">
            <div class="title-group">
                <h1>Artwork Manager</h1>
                <div class="status-subtitle">
                    <span class="status-dot"></span> 
                    Manage your handheld's artwork
                </div>
            </div>
        </div>
    </header>

    <div id="platform-tabs"></div>

    <main>
        <div class="search-container">
            <input type="text" id="search-input" placeholder="Search games...">
        </div>
        <div id="game-grid"></div>
    </main>

    <div id="modal-overlay">
        <div id="modal">
            <div class="modal-header">
                <div class="title-group">
                    <h2 id="modal-game-title">Game Title</h2>
                    <span id="modal-game-rom" style="font-size: 11px; color: var(--text-secondary); font-family: 'JetBrains Mono'">filename.zip</span>
                </div>
                <button class="close-btn">&times;</button>
            </div>
            <div class="media-list" id="modal-media-list"></div>
            <div id="modal-actions">
                <button class="btn btn-regen" id="btn-regen-global">Regenerate Final Artwork</button>
            </div>
        </div>
    </div>

    <div id="toast"></div>

    <footer>
        <p>Scrappy Artwork Manager &copy; {datetime.now().year}</p>
        <p style="opacity: 0.5;">Manage your handheld's media cache from anywhere</p>
    </footer>

    <script>
        let platforms = [];
        let currentGameList = [];
        let templates = [];
        let activePlatform = '';
        let activeGame = null;
        let activeTemplate = 'box2d';

        const searchInput = document.getElementById('search-input');
        const toast = document.getElementById('toast');
        const platformTabs = document.getElementById('platform-tabs');
        const gameGrid = document.getElementById('game-grid');
        const modalOverlay = document.getElementById('modal-overlay');
        const modalMediaList = document.getElementById('modal-media-list');
        const modalTitle = document.getElementById('modal-game-title');
        const modalSubtitle = document.getElementById('modal-game-rom');

        function buildMediaUrl(platform, relPath) {{
            const encodedPath = relPath.split('/').map(encodeURIComponent).join('/');
            return `/api/media/${{encodeURIComponent(platform)}}/${{encodedPath}}`;
        }}

        async function init() {{
            const pRes = await fetch('/api/cache');
            platforms = await pRes.json();
            
            const tRes = await fetch('/api/templates');
            templates = await tRes.json();
            
            const cRes = await fetch('/api/config');
            const config = await cRes.json();
            activeTemplate = config.artworkXml || 'box2d';

            platformTabs.innerHTML = '';
            platforms.forEach(p => {{
                const tab = document.createElement('div');
                tab.className = 'tab';
                tab.textContent = p;
                tab.onclick = () => switchPlatform(p);
                platformTabs.appendChild(tab);
            }});

            if (platforms.length > 0) switchPlatform(platforms[0]);
        }}

        async function switchPlatform(p) {{
            activePlatform = p;
            document.querySelectorAll('.tab').forEach(t => {{
                t.classList.toggle('active', t.textContent === p);
            }});
            
            gameGrid.innerHTML = '<div style="grid-column: 1/-1; text-align: center; padding: 40px; color: var(--text-secondary)">Loading games...</div>';
            
            const res = await fetch(`/api/games/${{encodeURIComponent(p)}}`);
            currentGameList = await res.json();
            renderGames();
        }}

        function renderGames(filter = '') {{
            gameGrid.innerHTML = '';
            const filtered = currentGameList.filter(g => 
                g.rom.toLowerCase().includes(filter.toLowerCase()) || 
                g.id.toLowerCase().includes(filter.toLowerCase())
            );

            if (filtered.length === 0) {{
                gameGrid.innerHTML = '<div style="grid-column: 1/-1; text-align: center; padding: 40px; color: var(--text-secondary)">No games found</div>';
                return;
            }}

            filtered.forEach((g, i) => {{
                const card = document.createElement('div');
                card.className = 'game-card';
                card.style.animationDelay = `${{i * 0.05}}s`;
                
                // Try to find a preview image
                let thumbUrl = '';
                // Common Skyscraper types to check first (ordered by preference)
                const types = ['cover', 'screenshot', 'boxart', 'titlescreen', 'actionshot', 'wheel', 'marquee'];
                for (const t of types) {{
                    const mediaEntries = g.media[t] || [];
                    if (mediaEntries.length > 0) {{
                        // Prefer local source if present, otherwise fall back to first entry
                        const preferred = mediaEntries.find(entry => entry.source === 'local') || mediaEntries[0];
                        thumbUrl = buildMediaUrl(activePlatform, preferred.path);
                        break;
                    }}
                }}

                // Final fallback: use ANY available media type if preferred ones aren't found
                if (!thumbUrl) {{
                    const availableTypes = Object.keys(g.media);
                    if (availableTypes.length > 0) {{
                        const firstType = availableTypes[0];
                        const mediaEntries = g.media[firstType] || [];
                        if (mediaEntries.length > 0) {{
                            const preferred = mediaEntries.find(entry => entry.source === 'local') || mediaEntries[0];
                            thumbUrl = buildMediaUrl(activePlatform, preferred.path);
                        }}
                    }}
                }}

                card.innerHTML = `
                    <div class="thumb-wrapper">
                        ${{thumbUrl ? `<img src="${{thumbUrl}}">` : '<span class="no-thumb">NO PREVIEW</span>'}}
                    </div>
                    <div class="game-info">
                        <div class="game-title">${{g.rom}}</div>
                        <div class="type-badges">
                            ${{Object.keys(g.media).map(t => `<span class="badge">${{t}}</span>`).join('')}}
                        </div>
                    </div>
                `;
                card.onclick = () => openGameModal(g);
                gameGrid.appendChild(card);
            }});
        }}

        function openGameModal(g) {{
            activeGame = g;
            const romBase = g.rom.replace(/\.[^/.]+$/, "");
            modalTitle.textContent = romBase || 'Unknown Game';
            modalSubtitle.textContent = g.rom;
            modalMediaList.innerHTML = '';

            const types = ['cover', 'screenshot', 'wheel', 'marquee', 'texture'];
            types.forEach(t => {{
                const item = document.createElement('div');
                item.className = 'media-item';

                const mediaEntries = g.media[t] || [];
                // If empty, show placeholder to allow upload
                if (mediaEntries.length === 0) {{
                    item.innerHTML = `
                        <div class="media-label">${{t}} <span style="opacity:0.5">Missing</span></div>
                        <div class="media-preview-container"><span style="color:var(--text-secondary)">NO MEDIA</span></div>
                        <div class="action-group">
                            <button class="btn btn-upload" onclick="handleUploadClick('${{g.id}}', '${{t}}', 'screenscraper', '${{g.id}}-${{t}}.png')">Upload replacement</button>
                        </div>
                    `;
                }} else {{
                    // Prefer local source if present, otherwise fall back to first entry
                    const preferred = mediaEntries.find(entry => entry.source === 'local') || mediaEntries[0];
                    const url = buildMediaUrl(activePlatform, preferred.path);
                    item.innerHTML = `
                        <div class="media-label">${{t}} <span>Source: ${{preferred.source}}</span></div>
                        <div class="media-preview-container">
                            <img src="${{url}}" id="preview-${{t}}">
                        </div>
                        <div class="action-group">
                            <button class="btn btn-upload" onclick="handleUploadClick('${{g.id}}', '${{t}}', '${{preferred.source}}', '${{preferred.file}}')">Replace...</button>
                        </div>
                    `;
                }}
                modalMediaList.appendChild(item);
            }});

            // Add Template Selector
            const tplSection = document.createElement('div');
            tplSection.className = 'template-selector';
            tplSection.innerHTML = `
                <div class="media-label">Artwork Template</div>
                <div class="template-list" id="modal-template-list"></div>
                <div class="scroll-hint">Scroll <--> to see more</div>
            `;
            modalMediaList.appendChild(tplSection);
            
            const tplContainer = tplSection.querySelector('#modal-template-list');
            templates.forEach(t => {{
                const chip = document.createElement('div');
                chip.className = `template-chip ${{t === activeTemplate ? 'active' : ''}}`;
                chip.textContent = t;
                chip.onclick = () => {{
                    activeTemplate = t;
                    tplSection.querySelectorAll('.template-chip').forEach(c => c.classList.remove('active'));
                    chip.classList.add('active');
                }};
                tplContainer.appendChild(chip);
            }});

            // Current Artwork Preview
            const outputItem = document.createElement('div');
            outputItem.className = 'media-item';
            const outputUrl = `/api/output/${{encodeURIComponent(activePlatform)}}/${{encodeURIComponent(romBase)}}.png`;
            outputItem.innerHTML = `
                <div class="media-label" style="color:#2ecc71">Current Artwork Preview</div>
                <div class="media-preview-container">
                    <img src="${{outputUrl}}" id="final-preview" style="max-height: 100%; max-width: 100%; object-fit: contain;" onerror="this.style.display='none'">
                    <div id="regen-loader" style="display:none; position:absolute; background:rgba(0,0,0,0.5); padding:10px; border-radius:10px;">Refreshing...</div>
                </div>
                <div style="display:flex; gap:10px; margin-top:5px;">
                    <div style="font-size: 11px; color: var(--text-secondary); flex:1">
                        This is current artwork for this game
                    </div>
                    <button class="btn" style="flex:0; padding:4px 8px; font-size:10px;" onclick="refreshFinalPreview()">Refresh Preview</button>
                </div>
            `;
            modalMediaList.appendChild(outputItem);

            // Regenerate Button section
            const regenSection = document.createElement('div');
            regenSection.style.margin = '20px';
            regenSection.innerHTML = `
                <button class="btn btn-regen" id="btn-regen-modal" style="width:100%; padding:15px; font-size:16px;">
                    Generate Artwork
                </button>
            `;
            modalMediaList.appendChild(regenSection);

            regenSection.querySelector('#btn-regen-modal').onclick = async () => {{
                showToast('Requesting regeneration...');
                const res = await fetch('/api/regenerate', {{
                    method: 'POST',
                    headers: {{ 'Content-Type': 'application/json' }},
                    body: JSON.stringify({{
                        platform: activePlatform,
                        rom: activeGame.rom,
                        xml: activeTemplate
                    }})
                }});

                if (res.ok) {{
                    showToast('Regeneration started in Scrappy!');
                    setTimeout(() => refreshFinalPreview(), 2500);
                }}
            }};

            modalOverlay.style.display = 'flex';
            document.body.style.overflow = 'hidden';
        }}

        function handleUploadClick(gid, type, source, filename) {{
            const input = document.createElement('input');
            input.type = 'file';
            input.accept = 'image/png, image/jpeg, image/jpg';
            input.onchange = async (e) => {{
                const file = e.target.files[0];
                if (!file) return;

                const formData = new FormData();
                formData.append('gid', gid);
                formData.append('platform', activePlatform);
                formData.append('type', type);
                formData.append('source', source);
                formData.append('filename', filename); // Suggested base filename
                formData.append('file', file);

                showToast('Uploading replacement...');
                const res = await fetch('/api/upload', {{
                    method: 'POST',
                    body: formData
                }});

                if (res.ok) {{
                    const data = await res.json();
                    showToast('Media replaced! Tap Regenerate to apply.');
                    
                    // Update source label in the UI instantly
                    const item = document.querySelector(`.media-item:has(button[onclick*="'${{type}}'"])`);
                    if (item) {{
                        const labelSpan = item.querySelector('.media-label span');
                        if (labelSpan) labelSpan.textContent = 'Source: local';
                        const missingSpan = item.querySelector('.media-label span[style*="opacity:0.5"]');
                        if (missingSpan) missingSpan.remove();
                    }}

                    // Update activeGame data so it stays in sync
                    if (!activeGame.media[type]) activeGame.media[type] = [];
                    activeGame.media[type] = [{{
                        source: 'local',
                        file: data.new_path.split('/').pop(),
                        path: data.new_path
                    }}];

                    // Refresh current preview explicitly to the new local path
                    const img = document.getElementById(`preview-${{type}}`);
                    if (img) {{
                        const url = buildMediaUrl(activePlatform, data.new_path);
                        img.src = `${{url}}?t=${{Date.now()}}`;
                        img.style.display = 'block';
                    }}
                }} else {{
                    showToast('Upload failed.');
                }}
            }};
            input.click();
        }}

        document.getElementById('btn-regen-global').onclick = async () => {{
            if (!activeGame) return;
            
            showToast('Requesting regeneration...');
            const res = await fetch('/api/regenerate', {{
                method: 'POST',
                headers: {{ 'Content-Type': 'application/json' }},
                body: JSON.stringify({{
                    platform: activePlatform,
                    rom: activeGame.rom
                }})
            }});

            if (res.ok) {{
                showToast('Regeneration started in Scrappy!');
                setTimeout(() => refreshFinalPreview(), 2500);
            }}
        }};

        function refreshFinalPreview() {{
            const img = document.getElementById('final-preview');
            const loader = document.getElementById('regen-loader');
            if (img && activeGame) {{
                const romBase = activeGame.rom.replace(/\.[^/.]+$/, "");
                const outputUrl = `/api/output/${{encodeURIComponent(activePlatform)}}/${{encodeURIComponent(romBase)}}.png`;
                if (loader) loader.style.display = 'block';
                img.src = `${{outputUrl}}?t=${{Date.now()}}`;
                img.onload = () => {{ if (loader) loader.style.display = 'none'; img.style.display = 'block'; }};
                img.onerror = () => {{ if (loader) loader.style.display = 'none'; }};
            }}
        }}

        function closeModal() {{
            modalOverlay.style.display = 'none';
            document.body.style.overflow = 'auto';
        }}

        function showToast(msg) {{
            toast.textContent = msg;
            toast.style.display = 'block';
            setTimeout(() => toast.style.display = 'none', 3000);
        }}

        document.querySelector('.close-btn').onclick = closeModal;
        modalOverlay.onclick = (e) => {{ if (e.target === modalOverlay) closeModal(); }};
        searchInput.oninput = (e) => renderGames(e.target.value);

        init();
    </script>
</body>
</html>
"""

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--theme", default="dark")
    parser.add_argument("--accent", default="cbaa0f")
    parser.add_argument("--logo", default="")
    parser.add_argument("--cache", required=True)
    args = parser.parse_args()

    # Use ThreadingTCPServer to handle multiple simultaneous requests (UI + images)
    socketserver.ThreadingTCPServer.allow_reuse_address = True
    socketserver.ThreadingTCPServer.daemon_threads = True
    with socketserver.ThreadingTCPServer(("", PORT), ArtworkManagerHandler) as httpd:
        print(f"Artwork Manager serving at port {{PORT}}")
        print(f"Cache: {{args.cache}}")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\\nServer stopped.")

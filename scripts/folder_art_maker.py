#!/usr/bin/env python3
"""
Folder Artwork Studio - Standalone Web Server
Allows designing, previewing, and deploying custom artwork for muOS folders and subfolders.
Uses Material Design 3 aesthetic, theme/accent color injection, and Material Symbols.
Saves directly to /mnt/mmc/MUOS/info/catalogue/Folder/box/ and text/ with zero Scrappy database impact.
"""

import http.server
import socketserver
import json
import os
import sys
import base64
import argparse
import subprocess
import shutil
import re
import urllib.parse
import platform
import xml.etree.ElementTree as ET
from pathlib import Path

DEFAULT_PORT = 8084
SANDBOX_DIR = "/tmp/folder_art_studio"


def find_skyscraper_bin(work_dir):
    """Find the appropriate Skyscraper binary based on architecture."""
    machine = platform.machine().lower()
    if "aarch64" in machine or "arm" in machine:
        local_aarch64 = os.path.join(work_dir, "bin", "Skyscraper.aarch64")
        if os.path.isfile(local_aarch64) and os.access(local_aarch64, os.X_OK):
            return local_aarch64
    which_path = shutil.which("Skyscraper")
    if which_path:
        return which_path
    if os.path.isfile("/usr/local/sbin/Skyscraper"):
        return "/usr/local/sbin/Skyscraper"
    local_x86 = os.path.join(work_dir, "bin", "Skyscraper.x86_64")
    if os.path.isfile(local_x86) and os.access(local_x86, os.X_OK):
        return local_x86
    return os.path.join(work_dir, "bin", "Skyscraper.aarch64")


def get_catalogue_paths():
    """Get all possible muOS catalogue folder destination directories."""
    paths = []
    if os.path.isdir("/mnt/mmc/MUOS/info/catalogue") or os.path.isdir("/mnt/mmc"):
        paths.append("/mnt/mmc/MUOS/info/catalogue/Folder")
    if os.path.isdir("/mnt/sdcard/MUOS/info/catalogue") or os.path.isdir("/mnt/sdcard"):
        paths.append("/mnt/sdcard/MUOS/info/catalogue/Folder")
    if os.path.isdir("/run/muos/storage/info/catalogue") or os.path.isdir("/run/muos/storage"):
        paths.append("/run/muos/storage/info/catalogue/Folder")
    return paths


def scan_rom_folders(work_dir):
    """Scan /mnt/mmc/ROMS, /mnt/sdcard/ROMS and local ROMS for folders and subfolders."""
    roots = ["/mnt/mmc/ROMS", "/mnt/sdcard/ROMS", "/run/muos/storage/ROMS", os.path.join(work_dir, "ROMS")]
    folders = set()

    for root in roots:
        if os.path.isdir(root):
            for dirpath, dirnames, _ in os.walk(root):
                dirnames[:] = [d for d in dirnames if not d.startswith(".")]
                for d in dirnames:
                    full = os.path.join(dirpath, d)
                    rel = os.path.relpath(full, root)
                    folders.add(rel)
                    folders.add(d)

    if not folders:
        folders = {
            "Arcade", "Atari 2600", "Atari Lynx", "Capcom", "Cave Story", "Commodore Amiga", "Commodore C64",
            "Doom", "Game Boy", "Game Boy Advance", "Game Boy Color", "Hacks", "Homebrew", "Konami",
            "Media Player", "NEC PC Engine", "NEC PC Engine CD", "Nintendo DS", "Nintendo Entertainment System",
            "Nintendo N64", "Nintendo Pokemon Mini", "PICO-8", "Ports", "Sega 32X", "Sega Dreamcast",
            "Sega Game Gear", "Sega Master System", "Sega Mega CD", "Sega Genesis", "SNK Neo Geo",
            "Sony PlayStation", "Sony PlayStation Portable", "Super Nintendo Entertainment System", "Translations"
        }

    return sorted(list(folders))


def parse_template_xml(xml_path):
    """Inspect XML template to determine required layers and output dimensions."""
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
        output_node = root.find("output")
        width = 320
        height = 240
        if output_node is not None:
            width = int(output_node.attrib.get("width", 320))
            height = int(output_node.attrib.get("height", 240))

        layers = []
        has_text = False

        for layer in root.iter("layer"):
            res = layer.attrib.get("resource")
            if res:
                if res in ["cover", "screenshot", "wheel", "marquee", "texture", "fanart", "box"]:
                    normalized = "cover" if res == "box" else res
                    if normalized not in layers:
                        layers.append(normalized)
                elif res == "text":
                    has_text = True

        return {
            "width": width,
            "height": height,
            "layers": layers if layers else ["cover", "screenshot", "wheel"],
            "has_text": has_text
        }
    except Exception as e:
        return {
            "width": 320,
            "height": 240,
            "layers": ["cover", "screenshot", "wheel"],
            "has_text": False,
            "error": str(e)
        }


TRANSPARENT_1X1_PNG = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAA=")


def ensure_template_resources(work_dir):
    """Ensure Skyscraper can resolve masks, frames, and scanlines from templates/resources."""
    res_source = os.path.join(work_dir, "templates", "resources")
    if not os.path.isdir(res_source):
        return

    # 1. Ensure ~/.skyscraper/resources has symlinks or copies
    sky_res_dir = os.path.expanduser("~/.skyscraper/resources")
    os.makedirs(sky_res_dir, exist_ok=True)
    for item in os.listdir(res_source):
        src = os.path.join(res_source, item)
        dest = os.path.join(sky_res_dir, item)
        if not os.path.exists(dest):
            try:
                os.symlink(src, dest)
            except Exception:
                if os.path.isdir(src):
                    shutil.copytree(src, dest, dirs_exist_ok=True)
                else:
                    shutil.copy2(src, dest)

    # 2. Also ensure SANDBOX_DIR has symlinks for relative path lookups
    for item in os.listdir(res_source):
        src = os.path.join(res_source, item)
        dest = os.path.join(SANDBOX_DIR, item)
        if not os.path.exists(dest):
            try:
                os.symlink(src, dest)
            except Exception:
                pass


def render_composite(work_dir, template_path, resources_b64, title="Folder Artwork", desc=""):
    """Run isolated Skyscraper in /tmp/folder_art_studio to render composite PNG."""
    sky_bin = find_skyscraper_bin(work_dir)
    
    shutil.rmtree(SANDBOX_DIR, ignore_errors=True)
    cache_plat_dir = os.path.join(SANDBOX_DIR, "cache", "megadrive")
    input_dir = os.path.join(SANDBOX_DIR, "input")
    output_dir = os.path.join(SANDBOX_DIR, "output")
    
    os.makedirs(cache_plat_dir, exist_ok=True)
    os.makedirs(input_dir, exist_ok=True)
    os.makedirs(output_dir, exist_ok=True)

    # Link template resources (masks, frames, scanlines)
    ensure_template_resources(work_dir)

    dummy_rom = os.path.join(input_dir, "fake-rom.zip")
    with open(dummy_rom, "w") as f:
        f.write("dummy")

    with open(os.path.join(cache_plat_dir, "quickid.xml"), "w") as f:
        f.write(f'''<?xml version="1.0" encoding="UTF-8"?>
<quickids>
    <quickid filepath="{dummy_rom}" timestamp="1743052060000" id="0849f893a38c10e4cd26aeda6a5cc6c501f206f1"/>
</quickids>''')

    db_lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<resources>',
        '    <resource id="0849f893a38c10e4cd26aeda6a5cc6c501f206f1" type="platform" source="screenscraper" timestamp="1742663472468">Megadrive</resource>',
        f'    <resource id="0849f893a38c10e4cd26aeda6a5cc6c501f206f1" type="title" source="screenscraper" timestamp="1742663472468">{title}</resource>'
    ]
    if desc:
        db_lines.append(f'    <resource id="0849f893a38c10e4cd26aeda6a5cc6c501f206f1" type="description" source="screenscraper" timestamp="1742663472468">{desc}</resource>')

    type_map = {
        "cover": "covers",
        "screenshot": "screenshots",
        "wheel": "wheels",
        "marquee": "marquees",
        "texture": "textures",
        "fanart": "fanarts"
    }

    for res_type, folder_name in type_map.items():
        type_dir = os.path.join(cache_plat_dir, folder_name, "screenscraper")
        os.makedirs(type_dir, exist_ok=True)
        dest_file = os.path.join(type_dir, "fake-rom")

        b64_data = resources_b64.get(res_type)
        if b64_data and "," in b64_data:
            b64_data = b64_data.split(",", 1)[1]
        
        if b64_data:
            try:
                img_bytes = base64.b64decode(b64_data)
                with open(dest_file, "wb") as f:
                    f.write(img_bytes)
                db_lines.append(f'    <resource id="0849f893a38c10e4cd26aeda6a5cc6c501f206f1" type="{res_type}" source="screenscraper" timestamp="1742663472468">{folder_name}/screenscraper/fake-rom</resource>')
            except Exception as e:
                print(f"Error decoding {res_type}: {e}")
        else:
            # Un-uploaded layers use a transparent 1x1 placeholder (no fake ROM images!)
            with open(dest_file, "wb") as f:
                f.write(TRANSPARENT_1X1_PNG)
            db_lines.append(f'    <resource id="0849f893a38c10e4cd26aeda6a5cc6c501f206f1" type="{res_type}" source="screenscraper" timestamp="1742663472468">{folder_name}/screenscraper/fake-rom</resource>')

    db_lines.append('</resources>')
    with open(os.path.join(cache_plat_dir, "db.xml"), "w") as f:
        f.write("\n".join(db_lines))

    config_ini = os.path.join(SANDBOX_DIR, "config.ini")
    with open(config_ini, "w") as f:
        f.write(f'''[main]
cacheFolder="{os.path.join(SANDBOX_DIR, 'cache')}"
gameListFolder="{output_dir}"
artworkXml="{template_path}"
''')

    cmd = [
        sky_bin,
        "-p", "megadrive",
        "-s", "cache",
        "-i", input_dir,
        "-c", config_ini,
        "--flags", "unattend,forcefilename",
        "-f", "pegasus"
    ]
    
    env = os.environ.copy()
    env["QT_QPA_PLATFORM"] = "offscreen"
    env["NO_COLOR"] = "1"
    
    res = subprocess.run(cmd, capture_output=True, text=True, env=env, cwd=SANDBOX_DIR)
    
    for fld in ["covers", "screenshots", "wheels", "marquees", "textures"]:
        out_png = os.path.join(output_dir, "megadrive", "media", fld, "fake-rom.png")
        if os.path.isfile(out_png):
            with open(out_png, "rb") as f:
                raw_bytes = f.read()
            return {
                "success": True,
                "png_b64": "data:image/png;base64," + base64.b64encode(raw_bytes).decode("ascii"),
                "raw_bytes": raw_bytes
            }

    return {
        "success": False,
        "error": f"Composite not generated. Skyscraper output:\n{res.stdout}\n{res.stderr}"
    }


def get_logo_b64(path):
    if not path or not os.path.exists(path):
        return ""
    try:
        with open(path, "rb") as f:
            return base64.b64encode(f.read()).decode("utf-8")
    except:
        return ""


class FolderArtHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(204)
        self.end_headers()

    def send_json(self, data, status=200):
        body = json.dumps(data).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        qs = urllib.parse.parse_qs(parsed.query)

        if path == "/":
            self.serve_app_html()
        elif path == "/api/templates":
            self.api_get_templates()
        elif path == "/api/template-info":
            name = qs.get("name", [""])[0]
            self.api_get_template_info(name)
        elif path == "/api/folders":
            self.api_get_folders()
        elif path.startswith("/api/sample/"):
            res_type = path[12:]
            self.api_get_sample(res_type)
        else:
            self.send_error(404, "Not Found")

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        content_len = int(self.headers.get("Content-Length", 0))
        post_body = self.rfile.read(content_len) if content_len > 0 else b"{}"
        try:
            data = json.loads(post_body.decode("utf-8"))
        except Exception:
            data = {}

        if path == "/api/preview":
            self.api_post_preview(data)
        elif path == "/api/save":
            self.api_post_save(data)
        else:
            self.send_error(404, "Not Found")

    def api_get_templates(self):
        templates_dir = os.path.join(SERVER_ARGS.work_dir, "templates")
        items = []
        if os.path.isdir(templates_dir):
            for f in sorted(os.listdir(templates_dir)):
                if f.endswith(".xml") and not f.startswith("."):
                    name = f[:-4]
                    full = os.path.join(templates_dir, f)
                    info = parse_template_xml(full)
                    items.append({
                        "name": name,
                        "filename": f,
                        "width": info["width"],
                        "height": info["height"],
                        "layers": info["layers"],
                        "has_text": info["has_text"]
                    })
        self.send_json({"templates": items})

    def api_get_template_info(self, name):
        templates_dir = os.path.join(SERVER_ARGS.work_dir, "templates")
        target = os.path.join(templates_dir, name if name.endswith(".xml") else (name + ".xml"))
        if not os.path.isfile(target):
            self.send_json({"error": "Template not found"}, 404)
            return
        info = parse_template_xml(target)
        info["name"] = name
        self.send_json(info)

    def api_get_folders(self):
        folders = scan_rom_folders(SERVER_ARGS.work_dir)
        self.send_json({"folders": folders})

    def api_get_sample(self, res_type):
        sample_path = os.path.join(SERVER_ARGS.work_dir, "sample", "presets", "Streets of Rage", f"{res_type}.png")
        if os.path.isfile(sample_path):
            with open(sample_path, "rb") as f:
                data = f.read()
            self.send_response(200)
            self.send_header("Content-Type", "image/png")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        else:
            self.send_error(404, "Sample image not found")

    def api_post_preview(self, data):
        template_name = data.get("template", "Three Mix Layout.xml")
        if not template_name.endswith(".xml"):
            template_name += ".xml"
        
        templates_dir = os.path.join(SERVER_ARGS.work_dir, "templates")
        tpl_path = os.path.join(templates_dir, template_name)
        if not os.path.isfile(tpl_path):
            self.send_json({"success": False, "error": f"Template '{template_name}' not found"}, 400)
            return

        resources = data.get("resources", {})
        title = data.get("title", "Folder Artwork")
        desc = data.get("description", "")

        res = render_composite(SERVER_ARGS.work_dir, tpl_path, resources, title, desc)
        resp_data = {
            "success": res.get("success", False),
            "png_b64": res.get("png_b64"),
            "error": res.get("error")
        }
        self.send_json(resp_data)

    def api_post_save(self, data):
        folder_name = data.get("folder_name", "").strip()
        if not folder_name:
            self.send_json({"success": False, "error": "Folder name cannot be empty"}, 400)
            return

        safe_name = os.path.basename(folder_name.replace("\\", "/"))
        template_name = data.get("template", "Three Mix Layout.xml")
        if not template_name.endswith(".xml"):
            template_name += ".xml"

        tpl_path = os.path.join(SERVER_ARGS.work_dir, "templates", template_name)
        resources = data.get("resources", {})
        title = data.get("title", safe_name)
        desc = data.get("description", "").strip()

        res = render_composite(SERVER_ARGS.work_dir, tpl_path, resources, title, desc)
        if not res.get("success"):
            self.send_json(res, 500)
            return

        png_bytes = res["raw_bytes"]
        saved_paths = []

        catalogue_dirs = get_catalogue_paths()
        if not catalogue_dirs:
            catalogue_dirs = [os.path.join(SERVER_ARGS.work_dir, "catalogue", "Folder")]

        for cat_folder in catalogue_dirs:
            box_dir = os.path.join(cat_folder, "box")
            text_dir = os.path.join(cat_folder, "text")
            
            os.makedirs(box_dir, exist_ok=True)
            box_target = os.path.join(box_dir, f"{safe_name}.png")
            with open(box_target, "wb") as f:
                f.write(png_bytes)
            saved_paths.append(box_target)

            if desc:
                os.makedirs(text_dir, exist_ok=True)
                text_target = os.path.join(text_dir, f"{safe_name}.txt")
                with open(text_target, "w", encoding="utf-8") as f:
                    f.write(desc + "\n")
                saved_paths.append(text_target)

        self.send_json({
            "success": True,
            "folder": safe_name,
            "saved_paths": saved_paths
        })

    def serve_app_html(self):
        logo_b64 = get_logo_b64(SERVER_ARGS.logo or os.path.join(SERVER_ARGS.work_dir, "assets", "scrappy_logo.png"))
        html = build_material_html(
            theme=SERVER_ARGS.theme,
            accent=SERVER_ARGS.accent,
            logo_b64=logo_b64
        )
        body = html.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<title>Folder Artwork Studio - Scrappy</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Roboto:wght@400;500;700&display=swap" rel="stylesheet">
<link href="https://fonts.googleapis.com/css2?family=Material+Symbols+Rounded:opsz,wght,FILL,GRAD@20..48,100..700,0..1,-50..200" rel="stylesheet">
<style>
:root {
    --bg: %%BG%%;
    --card-bg: %%CARD_BG%%;
    --card-border: %%CARD_BORDER%%;
    --text-primary: %%TEXT_PRIMARY%%;
    --text-secondary: %%TEXT_SECONDARY%%;
    --accent: %%ACCENT%%;
    --input-bg: %%INPUT_BG%%;
    --header-bg: %%HEADER_BG%%;
    --panel-bg: %%PANEL_BG%%;
    --hover-bg: %%HOVER_BG%%;
    --logo-filter: %%LOGO_FILTER%%;
    --danger: #e85555;
    --success: #4ade80;
    --accent-glow: color-mix(in srgb, var(--accent) 25%, transparent);

    --md-surface-container: color-mix(in srgb, var(--bg) 90%, var(--text-primary) 10%);
    --md-surface-container-high: color-mix(in srgb, var(--bg) 85%, var(--text-primary) 15%);
    --md-elevation-1: 0px 1px 3px rgba(0, 0, 0, 0.3);
    --md-elevation-2: 0px 2px 6px rgba(0, 0, 0, 0.35);
    --md-shape-sm: 8px;
    --md-shape-md: 12px;
    --md-shape-lg: 16px;
    --md-shape-full: 9999px;
}

* { box-sizing: border-box; margin: 0; padding: 0; }

body {
    background: var(--bg);
    color: var(--text-primary);
    font-family: 'Roboto', system-ui, sans-serif;
    font-size: 14px;
    line-height: 20px;
    letter-spacing: 0.25px;
    min-height: 100vh;
    display: flex;
    flex-direction: column;
    accent-color: var(--accent);
}

/* ─── Top App Bar ─── */
header {
    background: var(--header-bg);
    backdrop-filter: blur(12px);
    padding: 12px 20px;
    border-bottom: 1px solid var(--card-border);
    display: flex;
    align-items: center;
    justify-content: space-between;
    position: sticky;
    top: 0;
    z-index: 100;
}

.header-brand {
    display: flex;
    align-items: center;
    gap: 10px;
    flex-shrink: 0;
}

.logo-img {
    height: 28px;
    width: auto;
    display: block;
    filter: var(--logo-filter);
}

.header-title {
    font-size: 16px;
    font-weight: 500;
    letter-spacing: 0;
    line-height: 1;
    display: flex;
    align-items: center;
    color: var(--text-primary);
    transform: translateY(2px);
}

.status-badge {
    display: flex;
    align-items: center;
    gap: 6px;
    background: color-mix(in srgb, var(--accent) 15%, transparent);
    color: var(--accent);
    border: 1px solid color-mix(in srgb, var(--accent) 30%, transparent);
    padding: 4px 12px;
    border-radius: var(--md-shape-full);
    font-size: 12px;
    font-weight: 500;
}

.status-dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--accent);
    box-shadow: 0 0 8px var(--accent);
}

/* ─── Layout ─── */
main {
    flex: 1;
    max-width: 1400px;
    margin: 0 auto;
    width: 100%;
    padding: 24px;
    display: grid;
    grid-template-columns: 1.15fr 0.85fr;
    gap: 24px;
}

@media (max-width: 960px) {
    main { grid-template-columns: 1fr; }
}

/* ─── Cards ─── */
.m3-card {
    background: var(--card-bg);
    border: 1px solid var(--card-border);
    border-radius: var(--md-shape-lg);
    padding: 20px;
    margin-bottom: 20px;
    box-shadow: var(--md-elevation-1);
}

.card-header {
    display: flex;
    align-items: center;
    gap: 10px;
    font-size: 16px;
    font-weight: 600;
    margin-bottom: 16px;
    color: var(--text-primary);
}

.card-header .material-symbols-rounded {
    color: var(--accent);
    font-size: 22px;
}

/* ─── Templates Grid ─── */
.template-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
    gap: 12px;
    max-height: 260px;
    overflow-y: auto;
    padding-right: 6px;
}

.template-item {
    background: var(--panel-bg);
    border: 1px solid var(--card-border);
    border-radius: var(--md-shape-md);
    padding: 12px 14px;
    cursor: pointer;
    transition: all 0.2s ease;
    display: flex;
    flex-direction: column;
    gap: 6px;
}

.template-item:hover {
    border-color: var(--accent);
    background: color-mix(in srgb, var(--accent) 8%, var(--panel-bg));
    transform: translateY(-1px);
}

.template-item.active {
    border-color: var(--accent);
    background: color-mix(in srgb, var(--accent) 15%, var(--panel-bg));
    box-shadow: 0 0 0 1px var(--accent);
}

.tpl-name {
    font-weight: 500;
    font-size: 13px;
    color: var(--text-primary);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
}

.tpl-meta {
    font-size: 11px;
    color: var(--text-secondary);
    display: flex;
    gap: 4px;
    flex-wrap: wrap;
}

.m3-chip {
    background: var(--md-surface-container);
    border: 1px solid var(--card-border);
    padding: 2px 6px;
    border-radius: var(--md-shape-sm);
    font-size: 10px;
    text-transform: uppercase;
    font-weight: 500;
}

/* ─── Upload Dropzones ─── */
.dropzones-container {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(190px, 1fr));
    gap: 14px;
}

.dropzone-box {
    background: var(--panel-bg);
    border: 2px dashed var(--card-border);
    border-radius: var(--md-shape-md);
    padding: 16px 12px;
    text-align: center;
    cursor: pointer;
    transition: all 0.2s ease;
    position: relative;
    min-height: 160px;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 8px;
}

.dropzone-box:hover, .dropzone-box.dragover {
    border-color: var(--accent);
    background: color-mix(in srgb, var(--accent) 8%, var(--panel-bg));
}

.dz-icon-wrap .material-symbols-rounded {
    font-size: 32px;
    color: var(--accent);
}

.dz-title {
    font-size: 12px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    color: var(--text-primary);
}

.dz-hint {
    font-size: 11px;
    color: var(--text-secondary);
}

.dz-preview {
    max-width: 100%;
    max-height: 80px;
    object-fit: contain;
    border-radius: var(--md-shape-sm);
    display: none;
}

.dz-actions {
    display: none;
    gap: 6px;
    margin-top: 4px;
}

.dz-btn {
    background: var(--md-surface-container);
    border: 1px solid var(--card-border);
    border-radius: var(--md-shape-sm);
    color: var(--text-primary);
    padding: 4px 8px;
    font-size: 11px;
    font-weight: 500;
    display: flex;
    align-items: center;
    gap: 4px;
    cursor: pointer;
    transition: all 0.2s ease;
}

.dz-btn:hover {
    border-color: var(--accent);
    background: var(--hover-bg);
}

.dz-btn-danger:hover {
    border-color: var(--danger);
    color: var(--danger);
}

/* ─── Form Inputs ─── */
.form-group {
    margin-bottom: 16px;
}

label {
    display: block;
    font-size: 12px;
    font-weight: 500;
    color: var(--text-secondary);
    margin-bottom: 6px;
    text-transform: uppercase;
    letter-spacing: 0.5px;
}

input[type="text"], textarea, select {
    width: 100%;
    background: var(--input-bg);
    border: 1px solid var(--card-border);
    border-radius: var(--md-shape-sm);
    padding: 10px 14px;
    color: var(--text-primary);
    font-size: 14px;
    font-family: inherit;
    outline: none;
    transition: all 0.2s ease;
}

input[type="text"]:focus, textarea:focus, select:focus {
    border-color: var(--accent);
    box-shadow: 0 0 0 2px var(--accent-glow);
}

textarea {
    resize: vertical;
    min-height: 80px;
}

/* ─── Sticky Preview Panel ─── */
.preview-sticky {
    position: sticky;
    top: 72px;
}

.preview-stage {
    background: #000000;
    border: 1px solid var(--card-border);
    border-radius: var(--md-shape-md);
    min-height: 320px;
    display: flex;
    align-items: center;
    justify-content: center;
    position: relative;
    overflow: hidden;
}

.preview-img {
    max-width: 100%;
    max-height: 380px;
    object-fit: contain;
    display: block;
    border-radius: var(--md-shape-sm);
}

.preview-loading {
    position: absolute;
    inset: 0;
    background: rgba(0, 0, 0, 0.7);
    backdrop-filter: blur(4px);
    display: none;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 12px;
    color: var(--text-primary);
    z-index: 10;
}

.preview-loading.active {
    display: flex;
}

.m3-spinner {
    width: 32px;
    height: 32px;
    border: 3px solid color-mix(in srgb, var(--accent) 30%, transparent);
    border-top-color: var(--accent);
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
}

@keyframes spin {
    to { transform: rotate(360deg); }
}

/* ─── Buttons ─── */
.btn-filled {
    background: var(--accent);
    color: #000000;
    border: none;
    border-radius: var(--md-shape-full);
    padding: 12px 24px;
    font-size: 14px;
    font-weight: 600;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    cursor: pointer;
    width: 100%;
    margin-top: 16px;
    transition: all 0.2s ease;
}

.btn-filled:hover {
    filter: brightness(1.1);
    box-shadow: 0 2px 10px var(--accent-glow);
}

.btn-filled:active {
    transform: scale(0.98);
}

.btn-outlined {
    background: transparent;
    color: var(--text-primary);
    border: 1px solid var(--card-border);
    border-radius: var(--md-shape-full);
    padding: 8px 18px;
    font-size: 13px;
    font-weight: 500;
    cursor: pointer;
    transition: all 0.2s ease;
}

.btn-outlined:hover {
    border-color: var(--text-primary);
    background: var(--hover-bg);
}

.btn-text {
    background: transparent;
    border: none;
    color: var(--text-secondary);
    font-size: 13px;
    font-weight: 500;
    cursor: pointer;
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 8px 12px;
    border-radius: var(--md-shape-sm);
}

.btn-text:hover {
    color: var(--text-primary);
    background: var(--hover-bg);
}

.btn-icon {
    background: transparent;
    border: none;
    color: var(--text-secondary);
    cursor: pointer;
    width: 32px;
    height: 32px;
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
}

.btn-icon:hover {
    color: var(--text-primary);
    background: var(--hover-bg);
}

/* ─── Modal & Image Editor ─── */
.m3-modal-overlay {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.75);
    backdrop-filter: blur(8px);
    z-index: 1000;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 20px;
}

.m3-modal {
    background: var(--card-bg);
    border: 1px solid var(--card-border);
    border-radius: var(--md-shape-lg);
    width: 100%;
    max-width: 980px;
    max-height: 92vh;
    display: flex;
    flex-direction: column;
    box-shadow: 0 10px 40px rgba(0, 0, 0, 0.6);
    overflow: hidden;
}

.modal-header {
    padding: 16px 20px;
    border-bottom: 1px solid var(--card-border);
    display: flex;
    align-items: center;
    justify-content: space-between;
}

.modal-body {
    padding: 20px;
    overflow-y: auto;
    display: grid;
    grid-template-columns: 1.35fr 1fr;
    gap: 20px;
    flex: 1;
}

@media (max-width: 768px) {
    .modal-body { grid-template-columns: 1fr; }
}

.editor-workspace {
    background: #08080c;
    border: 1px solid var(--card-border);
    border-radius: var(--md-shape-md);
    position: relative;
    min-height: 380px;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    overflow: hidden;
    user-select: none;
}

.canvas-container {
    position: relative;
    max-width: 100%;
    max-height: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
}

#cropCanvas {
    display: block;
    max-width: 100%;
    max-height: 340px;
    cursor: move;
}

.workspace-hint {
    position: absolute;
    bottom: 8px;
    left: 12px;
    font-size: 11px;
    color: var(--text-secondary);
    background: rgba(0, 0, 0, 0.6);
    padding: 2px 8px;
    border-radius: var(--md-shape-sm);
    pointer-events: none;
}

.editor-sidebar {
    display: flex;
    flex-direction: column;
    gap: 14px;
}

.tool-section {
    background: var(--panel-bg);
    border: 1px solid var(--card-border);
    border-radius: var(--md-shape-md);
    padding: 12px 14px;
}

.tool-section-title {
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    color: var(--text-secondary);
    margin-bottom: 8px;
    display: flex;
    align-items: center;
    gap: 6px;
}

.tool-slider-row {
    margin-bottom: 8px;
}

.tool-slider-row:last-child {
    margin-bottom: 0;
}

.tool-slider-row label {
    display: flex;
    justify-content: space-between;
    font-size: 11px;
    text-transform: none;
    margin-bottom: 3px;
}

.tool-slider-row input[type="range"] {
    width: 100%;
    accent-color: var(--accent);
}

.aspect-grid {
    display: flex;
    gap: 6px;
    flex-wrap: wrap;
}

.aspect-btn {
    background: var(--md-surface-container);
    border: 1px solid var(--card-border);
    border-radius: var(--md-shape-sm);
    color: var(--text-primary);
    padding: 5px 10px;
    font-size: 11px;
    font-weight: 500;
    cursor: pointer;
    transition: all 0.2s ease;
}

.aspect-btn:hover {
    border-color: var(--accent);
}

.aspect-btn.active {
    background: var(--accent);
    color: #000000;
    border-color: var(--accent);
}

.btn-group-row {
    display: flex;
    gap: 6px;
}

.tool-action-btn {
    flex: 1;
    background: var(--md-surface-container);
    border: 1px solid var(--card-border);
    border-radius: var(--md-shape-sm);
    color: var(--text-primary);
    padding: 6px 0;
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    transition: all 0.2s ease;
}

.tool-action-btn:hover {
    border-color: var(--accent);
    color: var(--accent);
}

.dpad-container {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 4px;
    max-width: 140px;
    margin: 6px auto 0;
}

.dpad-btn {
    background: var(--md-surface-container);
    border: 1px solid var(--card-border);
    border-radius: var(--md-shape-sm);
    color: var(--text-primary);
    height: 28px;
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
}

.dpad-btn:hover {
    border-color: var(--accent);
    color: var(--accent);
}

.modal-footer {
    padding: 14px 20px;
    border-top: 1px solid var(--card-border);
    display: flex;
    align-items: center;
    justify-content: space-between;
    background: var(--panel-bg);
}

/* ─── Toast Notification ─── */
.m3-snackbar {
    position: fixed;
    bottom: 24px;
    right: 24px;
    padding: 14px 20px;
    background: var(--card-bg);
    border: 1px solid var(--accent);
    border-radius: var(--md-shape-md);
    color: var(--text-primary);
    box-shadow: var(--md-elevation-2);
    display: flex;
    align-items: center;
    gap: 12px;
    transform: translateY(100px);
    opacity: 0;
    transition: all 0.3s cubic-bezier(0.2, 0, 0, 1);
    z-index: 1000;
}

.m3-snackbar.show {
    transform: translateY(0);
    opacity: 1;
}

.m3-snackbar .material-symbols-rounded {
    color: var(--accent);
    font-size: 24px;
}
</style>
</head>
<body>

<header>
    <div class="header-brand">
        %%LOGO_HTML%%
        <div class="header-title">Folder Artwork Studio</div>
    </div>
    <div class="status-badge">
        <div class="status-dot"></div>
        <span>Ready</span>
    </div>
</header>

<main>
    <!-- Left Column: Controls -->
    <div class="left-col">
        <!-- Step 1: Template Selection -->
        <div class="m3-card">
            <div class="card-header">
                <span class="material-symbols-rounded">palette</span>
                <span>Select Artwork Template</span>
            </div>
            <div class="template-grid" id="templateGrid">
                <div style="color:var(--text-secondary); font-size:13px;">Loading templates...</div>
            </div>
        </div>

        <!-- Step 2: Layer Uploads -->
        <div class="m3-card">
            <div class="card-header">
                <span class="material-symbols-rounded">layers</span>
                <span>Template Media Inputs</span>
            </div>
            <p style="color:var(--text-secondary); font-size:12px; margin-bottom:14px;">
                Upload custom artwork for required layers, or leave blank to omit.
            </p>
            <div class="dropzones-container" id="dropzonesContainer"></div>
        </div>

        <!-- Step 3: Target Folder Selection -->
        <div class="m3-card">
            <div class="card-header">
                <span class="material-symbols-rounded">folder_open</span>
                <span>Target Folder in muOS</span>
            </div>
            <div class="form-group">
                <label>Select ROM Folder / Subfolder</label>
                <select id="folderSelect">
                    <option value="">-- Choose ROM folder --</option>
                </select>
            </div>
            <div class="form-group">
                <label>Or Custom Folder Name</label>
                <input type="text" id="folderInput" placeholder="e.g. Game Boy Advance or Capcom">
            </div>
            <div class="form-group">
                <label>System / Folder Description (Optional text file)</label>
                <textarea id="descInput" placeholder="Saved to catalogue/Folder/text/<Folder>.txt"></textarea>
            </div>
        </div>
    </div>

    <!-- Right Column: Live Sticky Preview -->
    <div class="right-col">
        <div class="m3-card preview-sticky">
            <div class="card-header">
                <span class="material-symbols-rounded">preview</span>
                <span>Real-Time Composite Preview</span>
            </div>

            <div class="preview-stage" id="previewStage">
                <img class="preview-img" id="previewImg" alt="Preview" style="display:none;">
                <div id="previewPlaceholder" style="color:var(--text-secondary); font-size:13px; text-align:center; display:flex; flex-direction:column; align-items:center; justify-content:center; gap:8px; padding:20px;">
                    <span class="material-symbols-rounded" style="font-size:36px; opacity:0.35;">add_photo_alternate</span>
                    <div style="font-weight:500; color:var(--text-primary);">Upload artwork layers to see live preview</div>
                    <div style="font-size:11px; opacity:0.7;">Drop or select an image on the left</div>
                </div>
                <div class="preview-loading" id="previewLoading">
                    <div class="m3-spinner"></div>
                    <div style="font-size:13px; font-weight:500;">Compositing Layout...</div>
                </div>
            </div>

            <div style="margin-top:14px; font-size:12px; color:var(--text-secondary); display:flex; justify-content:space-between;">
                <span>Target: <strong id="destPathLabel" style="color:var(--text-primary);">catalogue/Folder/box/</strong></span>
                <span id="canvasDimLabel">320 × 240</span>
            </div>

            <button class="btn-filled" id="btnSave">
                <span class="material-symbols-rounded">save</span>
                <span>Save to muOS Catalogue</span>
            </button>
        </div>
    </div>
</main>

<!-- Image Editor Modal -->
<div class="m3-modal-overlay" id="editorModal" style="display:none;">
    <div class="m3-modal">
        <div class="modal-header">
            <div style="display:flex; align-items:center; gap:8px;">
                <span class="material-symbols-rounded" style="color:var(--accent);">tune</span>
                <span id="editorTitle" style="font-weight:600; font-size:16px;">Adjust Layer Image</span>
            </div>
            <button class="btn-icon" id="btnCloseEditor" title="Close"><span class="material-symbols-rounded">close</span></button>
        </div>
        <div class="modal-body">
            <div class="editor-workspace">
                <div class="canvas-container">
                    <canvas id="cropCanvas"></canvas>
                </div>
                <div class="workspace-hint">Drag image to position &bull; Drag corners to crop</div>
            </div>
            <div class="editor-sidebar">
                <!-- Move & Reposition -->
                <div class="tool-section">
                    <div class="tool-section-title">
                        <span class="material-symbols-rounded" style="font-size:18px;">open_with</span>
                        <span>Move & Reposition</span>
                    </div>
                    <div class="tool-slider-row">
                        <label><span>Position X (Horizontal)</span><span id="posXVal">0px</span></label>
                        <input type="range" id="posXSlider" min="-300" max="300" value="0">
                    </div>
                    <div class="tool-slider-row">
                        <label><span>Position Y (Vertical)</span><span id="posYVal">0px</span></label>
                        <input type="range" id="posYSlider" min="-300" max="300" value="0">
                    </div>
                    <div class="dpad-container">
                        <div></div>
                        <button class="dpad-btn" id="btnNudgeUp" title="Nudge Up"><span class="material-symbols-rounded" style="font-size:18px;">keyboard_arrow_up</span></button>
                        <div></div>
                        <button class="dpad-btn" id="btnNudgeLeft" title="Nudge Left"><span class="material-symbols-rounded" style="font-size:18px;">keyboard_arrow_left</span></button>
                        <button class="dpad-btn" id="btnCenterPos" title="Center Position"><span class="material-symbols-rounded" style="font-size:16px;">filter_center_focus</span></button>
                        <button class="dpad-btn" id="btnNudgeRight" title="Nudge Right"><span class="material-symbols-rounded" style="font-size:18px;">keyboard_arrow_right</span></button>
                        <div></div>
                        <button class="dpad-btn" id="btnNudgeDown" title="Nudge Down"><span class="material-symbols-rounded" style="font-size:18px;">keyboard_arrow_down</span></button>
                        <div></div>
                    </div>
                </div>

                <!-- Scale Slider -->
                <div class="tool-section">
                    <div class="tool-section-title">
                        <span class="material-symbols-rounded" style="font-size:18px;">zoom_in</span>
                        <span>Scale & Resize</span>
                    </div>
                    <div class="tool-slider-row">
                        <label><span>Zoom / Size</span><span id="scaleVal">100%</span></label>
                        <input type="range" id="scaleSlider" min="20" max="300" value="100">
                    </div>
                </div>

                <!-- Crop Presets -->
                <div class="tool-section">
                    <div class="tool-section-title">
                        <span class="material-symbols-rounded" style="font-size:18px;">crop</span>
                        <span>Crop Framing</span>
                    </div>
                    <div class="aspect-grid" id="aspectGrid">
                        <button class="aspect-btn active" data-ratio="free">Free</button>
                        <button class="aspect-btn" data-ratio="1">1:1</button>
                        <button class="aspect-btn" data-ratio="1.3333">4:3</button>
                        <button class="aspect-btn" data-ratio="1.7777">16:9</button>
                        <button class="aspect-btn" data-ratio="0.75">3:4</button>
                    </div>
                </div>

                <!-- Rotate & Flip -->
                <div class="tool-section">
                    <div class="tool-section-title">
                        <span class="material-symbols-rounded" style="font-size:18px;">transform</span>
                        <span>Orientation & Flip</span>
                    </div>
                    <div class="btn-group-row">
                        <button class="tool-action-btn" id="btnRotateCCW" title="Rotate Left 90°">
                            <span class="material-symbols-rounded">rotate_left</span>
                        </button>
                        <button class="tool-action-btn" id="btnRotateCW" title="Rotate Right 90°">
                            <span class="material-symbols-rounded">rotate_right</span>
                        </button>
                        <button class="tool-action-btn" id="btnFlipH" title="Flip Horizontal">
                            <span class="material-symbols-rounded">flip</span>
                        </button>
                        <button class="tool-action-btn" id="btnFlipV" title="Flip Vertical">
                            <span class="material-symbols-rounded" style="transform:rotate(90deg);">flip</span>
                        </button>
                    </div>
                </div>

                <!-- Color Adjustments -->
                <div class="tool-section">
                    <div class="tool-section-title">
                        <span class="material-symbols-rounded" style="font-size:18px;">contrast</span>
                        <span>Image Enhancements</span>
                    </div>
                    <div class="tool-slider-row">
                        <label><span>Brightness</span><span id="brightVal">0%</span></label>
                        <input type="range" id="brightSlider" min="-50" max="50" value="0">
                    </div>
                    <div class="tool-slider-row">
                        <label><span>Contrast</span><span id="contrastVal">0%</span></label>
                        <input type="range" id="contrastSlider" min="-50" max="50" value="0">
                    </div>
                    <div class="tool-slider-row">
                        <label><span>Saturation</span><span id="satVal">0%</span></label>
                        <input type="range" id="satSlider" min="-100" max="100" value="0">
                    </div>
                </div>
            </div>
        </div>
        <div class="modal-footer">
            <button class="btn-text" id="btnResetEditor">
                <span class="material-symbols-rounded">restart_alt</span>
                <span>Reset Original</span>
            </button>
            <div style="display:flex; gap:10px;">
                <button class="btn-outlined" id="btnCancelEditor">Cancel</button>
                <button class="btn-filled" id="btnApplyEditor" style="margin-top:0; width:auto;">
                    <span class="material-symbols-rounded">check</span>
                    <span>Apply to Preview</span>
                </button>
            </div>
        </div>
    </div>
</div>

<div class="m3-snackbar" id="snackbar">
    <span class="material-symbols-rounded">check_circle</span>
    <div>
        <div style="font-weight:700; font-size:13px;" id="toastTitle">Success</div>
        <div style="font-size:12px; color:var(--text-secondary);" id="toastMsg">Saved to muOS Folder catalogue!</div>
    </div>
</div>

<script>
const state = {
    templates: [],
    selectedTemplate: null,
    templateInfo: null,
    resources: {},
    originalResources: {},
    folders: [],
    debounceTimer: null,
    editor: {
        layer: null,
        img: null,
        posX: 0,
        posY: 0,
        scale: 1,
        rotation: 0,
        flipH: false,
        flipV: false,
        brightness: 0,
        contrast: 0,
        saturation: 0,
        crop: { x: 0, y: 0, w: 100, h: 100 },
        aspectRatio: "free",
        isDragging: false,
        dragMode: null, // "pan" or "nw", "ne", "sw", "se", "crop_move"
        dragStart: { x: 0, y: 0 },
        posStart: { x: 0, y: 0 },
        cropStart: { x: 0, y: 0, w: 0, h: 0 }
    }
};

const layerIcons = {
    cover: "photo_library",
    screenshot: "photo_camera",
    wheel: "token",
    marquee: "view_carousel",
    texture: "memory",
    fanart: "wallpaper"
};

const layerTitles = {
    cover: "Box / Cover Art",
    screenshot: "Gameplay Screenshot",
    wheel: "Logo / Wheel Art",
    marquee: "Marquee / Header",
    texture: "Texture / Cartridge"
};

async function init() {
    await Promise.all([loadTemplates(), loadFolders()]);
    setupEventListeners();
    setupEditorEventListeners();
}

async function loadTemplates() {
    try {
        const res = await fetch("/api/templates");
        const data = await res.json();
        state.templates = data.templates || [];
        renderTemplateGrid();
        if (state.templates.length > 0) {
            const defaultTpl = state.templates.find(t => t.name.includes("Three Mix")) || state.templates[0];
            selectTemplate(defaultTpl.filename);
        }
    } catch (e) {
        console.error("Failed to load templates", e);
    }
}

async function loadFolders() {
    try {
        const res = await fetch("/api/folders");
        const data = await res.json();
        state.folders = data.folders || [];
        const select = document.getElementById("folderSelect");
        select.innerHTML = '<option value="">-- Choose ROM folder --</option>';
        state.folders.forEach(f => {
            const opt = document.createElement("option");
            opt.value = f;
            opt.textContent = f;
            select.appendChild(opt);
        });
    } catch (e) {
        console.error("Failed to load folders", e);
    }
}

function renderTemplateGrid() {
    const grid = document.getElementById("templateGrid");
    grid.innerHTML = "";
    state.templates.forEach(t => {
        const div = document.createElement("div");
        div.className = "template-item" + (state.selectedTemplate === t.filename ? " active" : "");
        div.onclick = () => selectTemplate(t.filename);
        
        div.innerHTML = `
            <div class="tpl-name">${t.name}</div>
            <div class="tpl-meta">
                <span>${t.width}×${t.height}</span>
                ${t.layers.map(l => `<span class="m3-chip">${l}</span>`).join("")}
            </div>
        `;
        grid.appendChild(div);
    });
}

async function selectTemplate(filename) {
    state.selectedTemplate = filename;
    renderTemplateGrid();
    
    try {
        const res = await fetch("/api/template-info?name=" + encodeURIComponent(filename));
        state.templateInfo = await res.json();
        document.getElementById("canvasDimLabel").textContent = `${state.templateInfo.width} × ${state.templateInfo.height}`;
        renderDropzones();
        triggerPreview();
    } catch (e) {
        console.error("Failed to get template info", e);
    }
}

function renderDropzones() {
    const container = document.getElementById("dropzonesContainer");
    container.innerHTML = "";
    
    const layers = (state.templateInfo && state.templateInfo.layers) || ["cover", "screenshot", "wheel"];
    
    layers.forEach(layer => {
        const box = document.createElement("div");
        box.className = "dropzone-box";
        box.dataset.layer = layer;

        const iconName = layerIcons[layer] || "image";
        const title = layerTitles[layer] || (layer.toUpperCase() + " Image");
        const existing = state.resources[layer];

        box.innerHTML = `
            <div class="dz-icon-wrap" style="display:${existing ? "none" : "block"};">
                <span class="material-symbols-rounded">${iconName}</span>
            </div>
            <div class="dz-title">${title}</div>
            <img class="dz-preview" src="${existing || ""}" style="display:${existing ? "block" : "none"};">
            <div class="dz-hint" style="display:${existing ? "none" : "block"};">Click or drop image</div>
            <div class="dz-actions" style="display:${existing ? "flex" : "none"};">
                <button class="dz-btn dz-btn-edit" title="Crop & Adjust Image">
                    <span class="material-symbols-rounded" style="font-size:16px;">crop</span>
                    <span>Crop / Move</span>
                </button>
                <button class="dz-btn dz-btn-danger dz-btn-reset" title="Remove custom image">
                    <span class="material-symbols-rounded" style="font-size:16px;">close</span>
                </button>
            </div>
            <input type="file" accept="image/png, image/jpeg" style="display:none;">
        `;

        const fileInput = box.querySelector('input[type="file"]');
        const editBtn = box.querySelector(".dz-btn-edit");
        const resetBtn = box.querySelector(".dz-btn-reset");

        box.onclick = (e) => {
            if (e.target.closest(".dz-actions")) return;
            if (existing) {
                openImageEditor(layer);
            } else {
                fileInput.click();
            }
        };

        if (editBtn) {
            editBtn.onclick = (e) => {
                e.stopPropagation();
                openImageEditor(layer);
            };
        }

        if (resetBtn) {
            resetBtn.onclick = (e) => {
                e.stopPropagation();
                delete state.resources[layer];
                delete state.originalResources[layer];
                fileInput.value = "";
                renderDropzones();
                triggerPreview();
            };
        }

        fileInput.onchange = (e) => {
            if (e.target.files && e.target.files[0]) {
                handleFile(e.target.files[0], layer);
            }
        };

        box.ondragover = (e) => { e.preventDefault(); box.classList.add("dragover"); };
        box.ondragleave = () => box.classList.remove("dragover");
        box.ondrop = (e) => {
            e.preventDefault();
            box.classList.remove("dragover");
            if (e.dataTransfer.files && e.dataTransfer.files[0]) {
                handleFile(e.dataTransfer.files[0], layer);
            }
        };

        container.appendChild(box);
    });
}

function handleFile(file, layer) {
    const reader = new FileReader();
    reader.onload = (e) => {
        state.originalResources[layer] = e.target.result;
        state.resources[layer] = e.target.result;
        renderDropzones();
        triggerPreview();
    };
    reader.readAsDataURL(file);
}

function setupEventListeners() {
    const folderSelect = document.getElementById("folderSelect");
    const folderInput = document.getElementById("folderInput");
    const descInput = document.getElementById("descInput");
    const destLabel = document.getElementById("destPathLabel");

    folderSelect.onchange = () => {
        if (folderSelect.value) {
            folderInput.value = folderSelect.value;
            destLabel.textContent = `catalogue/Folder/box/${folderSelect.value}.png`;
            triggerPreview();
        }
    };

    folderInput.oninput = () => {
        const val = folderInput.value.trim();
        destLabel.textContent = `catalogue/Folder/box/${val || "..."}.png`;
        triggerPreview();
    };

    descInput.oninput = () => triggerPreview();

    document.getElementById("btnSave").onclick = saveArtwork;
}

function triggerPreview() {
    clearTimeout(state.debounceTimer);
    state.debounceTimer = setTimeout(runPreview, 250);
}

async function runPreview() {
    if (!state.selectedTemplate) return;
    const loading = document.getElementById("previewLoading");
    const img = document.getElementById("previewImg");
    const placeholder = document.getElementById("previewPlaceholder");

    const hasAnyLayers = Object.keys(state.resources).length > 0;
    if (!hasAnyLayers) {
        img.src = "";
        img.style.display = "none";
        placeholder.style.display = "flex";
        loading.classList.remove("active");
        return;
    }

    loading.classList.add("active");

    const payload = {
        template: state.selectedTemplate,
        resources: state.resources,
        title: document.getElementById("folderInput").value.trim() || "Folder Artwork",
        description: document.getElementById("descInput").value.trim()
    };

    try {
        const res = await fetch("/api/preview", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(payload)
        });
        const data = await res.json();
        if (data.success && data.png_b64) {
            img.src = data.png_b64;
            img.style.display = "block";
            placeholder.style.display = "none";
        } else {
            console.error("Preview error", data.error);
        }
    } catch (e) {
        console.error("Preview fetch failed", e);
    } finally {
        loading.classList.remove("active");
    }
}

async function saveArtwork() {
    const folder = document.getElementById("folderInput").value.trim();
    if (!folder) {
        alert("Please choose or enter a target folder name first.");
        document.getElementById("folderInput").focus();
        return;
    }

    const payload = {
        folder_name: folder,
        template: state.selectedTemplate,
        resources: state.resources,
        title: folder,
        description: document.getElementById("descInput").value.trim()
    };

    const btn = document.getElementById("btnSave");
    const origHTML = btn.innerHTML;
    btn.innerHTML = '<span class="material-symbols-rounded">hourglass_top</span><span>Saving...</span>';
    btn.disabled = true;

    try {
        const res = await fetch("/api/save", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(payload)
        });
        const data = await res.json();
        if (data.success) {
            showSnackbar("Saved Successfully", `Deployed to catalogue/Folder/box/${data.folder}.png`);
        } else {
            alert("Failed to save: " + (data.error || "Unknown error"));
        }
    } catch (e) {
        alert("Error connecting to server: " + e);
    } finally {
        btn.innerHTML = origHTML;
        btn.disabled = false;
    }
}

function showSnackbar(title, msg) {
    const snack = document.getElementById("snackbar");
    document.getElementById("toastTitle").textContent = title;
    document.getElementById("toastMsg").textContent = msg;
    snack.classList.add("show");
    setTimeout(() => snack.classList.remove("show"), 4000);
}

/* ─── Image Editor Engine ─── */
function openImageEditor(layer) {
    const src = state.originalResources[layer] || state.resources[layer];
    if (!src) return;

    state.editor.layer = layer;
    state.editor.posX = 0;
    state.editor.posY = 0;
    state.editor.scale = 1;
    state.editor.rotation = 0;
    state.editor.flipH = false;
    state.editor.flipV = false;
    state.editor.brightness = 0;
    state.editor.contrast = 0;
    state.editor.saturation = 0;
    state.editor.aspectRatio = "free";

    document.getElementById("posXSlider").value = 0;
    document.getElementById("posXVal").textContent = "0px";
    document.getElementById("posYSlider").value = 0;
    document.getElementById("posYVal").textContent = "0px";

    document.getElementById("scaleSlider").value = 100;
    document.getElementById("scaleVal").textContent = "100%";
    document.getElementById("brightSlider").value = 0;
    document.getElementById("brightVal").textContent = "0%";
    document.getElementById("contrastSlider").value = 0;
    document.getElementById("contrastVal").textContent = "0%";
    document.getElementById("satSlider").value = 0;
    document.getElementById("satVal").textContent = "0%";

    document.querySelectorAll(".aspect-btn").forEach(b => {
        b.classList.toggle("active", b.dataset.ratio === "free");
    });

    const title = layerTitles[layer] || layer.toUpperCase();
    document.getElementById("editorTitle").textContent = `Adjust & Crop: ${title}`;

    const img = new Image();
    img.onload = () => {
        state.editor.img = img;
        state.editor.crop = { x: 0, y: 0, w: img.width, h: img.height };
        document.getElementById("editorModal").style.display = "flex";
        drawEditorCanvas();
    };
    img.src = src;
}

function closeImageEditor() {
    document.getElementById("editorModal").style.display = "none";
    state.editor.layer = null;
    state.editor.img = null;
}

function drawEditorCanvas() {
    const canvas = document.getElementById("cropCanvas");
    const ctx = canvas.getContext("2d");
    const img = state.editor.img;
    if (!img) return;

    const maxW = 520, maxH = 340;
    let dispW = img.width, dispH = img.height;
    const ratio = Math.min(maxW / dispW, maxH / dispH, 1);
    dispW = Math.round(dispW * ratio);
    dispH = Math.round(dispH * ratio);

    canvas.width = dispW;
    canvas.height = dispH;
    state.editor.dispScale = ratio;

    ctx.clearRect(0, 0, dispW, dispH);

    // Apply color filters & position transforms
    ctx.save();
    const centerX = (dispW / 2) + (state.editor.posX * ratio);
    const centerY = (dispH / 2) + (state.editor.posY * ratio);
    ctx.translate(centerX, centerY);
    ctx.rotate((state.editor.rotation * Math.PI) / 180);
    ctx.scale(state.editor.flipH ? -1 : 1, state.editor.flipV ? -1 : 1);
    ctx.scale(state.editor.scale, state.editor.scale);

    const b = 100 + state.editor.brightness;
    const c = 100 + state.editor.contrast;
    const s = 100 + state.editor.saturation;
    ctx.filter = `brightness(${b}%) contrast(${c}%) saturate(${s}%)`;

    ctx.drawImage(img, -dispW / 2, -dispH / 2, dispW, dispH);
    ctx.restore();

    // Draw dark overlay outside crop
    const crop = state.editor.crop;
    const cx = Math.round(crop.x * ratio);
    const cy = Math.round(crop.y * ratio);
    const cw = Math.round(crop.w * ratio);
    const ch = Math.round(crop.h * ratio);

    ctx.fillStyle = "rgba(0, 0, 0, 0.55)";
    ctx.fillRect(0, 0, dispW, cy);
    ctx.fillRect(0, cy + ch, dispW, dispH - (cy + ch));
    ctx.fillRect(0, cy, cx, ch);
    ctx.fillRect(cx + cw, cy, dispW - (cx + cw), ch);

    // Draw crop border
    ctx.strokeStyle = "#cbaa0f";
    ctx.lineWidth = 2;
    ctx.strokeRect(cx, cy, cw, ch);

    // Draw corner handles
    const handleSize = 8;
    ctx.fillStyle = "#ffffff";
    const handles = [
        { x: cx, y: cy },
        { x: cx + cw - handleSize, y: cy },
        { x: cx, y: cy + ch - handleSize },
        { x: cx + cw - handleSize, y: cy + ch - handleSize }
    ];
    handles.forEach(h => {
        ctx.fillRect(h.x, h.y, handleSize, handleSize);
    });
}

function applyImageEditor() {
    const layer = state.editor.layer;
    const img = state.editor.img;
    if (!layer || !img) return;

    const crop = state.editor.crop;
    const outCanvas = document.createElement("canvas");
    outCanvas.width = Math.max(10, Math.round(crop.w));
    outCanvas.height = Math.max(10, Math.round(crop.h));
    const outCtx = outCanvas.getContext("2d");

    outCtx.save();
    const b = 100 + state.editor.brightness;
    const c = 100 + state.editor.contrast;
    const s = 100 + state.editor.saturation;
    outCtx.filter = `brightness(${b}%) contrast(${c}%) saturate(${s}%)`;

    // Center image in the cropped output with position offsets
    const cropCenterX = crop.x + (crop.w / 2);
    const cropCenterY = crop.y + (crop.h / 2);
    const imgCenterX = img.width / 2;
    const imgCenterY = img.height / 2;

    const shiftX = (outCanvas.width / 2) + state.editor.posX - (cropCenterX - imgCenterX);
    const shiftY = (outCanvas.height / 2) + state.editor.posY - (cropCenterY - imgCenterY);

    outCtx.translate(shiftX, shiftY);
    outCtx.rotate((state.editor.rotation * Math.PI) / 180);
    outCtx.scale(state.editor.flipH ? -1 : 1, state.editor.flipV ? -1 : 1);
    outCtx.scale(state.editor.scale, state.editor.scale);

    outCtx.drawImage(
        img,
        -img.width / 2, -img.height / 2, img.width, img.height
    );
    outCtx.restore();

    state.resources[layer] = outCanvas.toDataURL("image/png");
    closeImageEditor();
    renderDropzones();
    triggerPreview();
    showSnackbar("Layer Updated", `Applied adjustments to ${layerTitles[layer] || layer}`);
}

function setupEditorEventListeners() {
    document.getElementById("btnCloseEditor").onclick = closeImageEditor;
    document.getElementById("btnCancelEditor").onclick = closeImageEditor;
    document.getElementById("btnApplyEditor").onclick = applyImageEditor;

    document.getElementById("btnResetEditor").onclick = () => {
        if (!state.editor.layer) return;
        const origSrc = state.originalResources[state.editor.layer];
        if (origSrc) {
            openImageEditor(state.editor.layer);
        }
    };

    // Position Sliders & D-Pad
    const posXSlider = document.getElementById("posXSlider");
    posXSlider.oninput = () => {
        state.editor.posX = parseInt(posXSlider.value);
        document.getElementById("posXVal").textContent = `${posXSlider.value}px`;
        drawEditorCanvas();
    };

    const posYSlider = document.getElementById("posYSlider");
    posYSlider.oninput = () => {
        state.editor.posY = parseInt(posYSlider.value);
        document.getElementById("posYVal").textContent = `${posYSlider.value}px`;
        drawEditorCanvas();
    };

    document.getElementById("btnNudgeUp").onclick = () => {
        state.editor.posY -= 10;
        posYSlider.value = state.editor.posY;
        document.getElementById("posYVal").textContent = `${state.editor.posY}px`;
        drawEditorCanvas();
    };
    document.getElementById("btnNudgeDown").onclick = () => {
        state.editor.posY += 10;
        posYSlider.value = state.editor.posY;
        document.getElementById("posYVal").textContent = `${state.editor.posY}px`;
        drawEditorCanvas();
    };
    document.getElementById("btnNudgeLeft").onclick = () => {
        state.editor.posX -= 10;
        posXSlider.value = state.editor.posX;
        document.getElementById("posXVal").textContent = `${state.editor.posX}px`;
        drawEditorCanvas();
    };
    document.getElementById("btnNudgeRight").onclick = () => {
        state.editor.posX += 10;
        posXSlider.value = state.editor.posX;
        document.getElementById("posXVal").textContent = `${state.editor.posX}px`;
        drawEditorCanvas();
    };
    document.getElementById("btnCenterPos").onclick = () => {
        state.editor.posX = 0;
        state.editor.posY = 0;
        posXSlider.value = 0;
        posYSlider.value = 0;
        document.getElementById("posXVal").textContent = "0px";
        document.getElementById("posYVal").textContent = "0px";
        drawEditorCanvas();
    };

    // Scale / Zoom
    const scaleSlider = document.getElementById("scaleSlider");
    scaleSlider.oninput = () => {
        state.editor.scale = scaleSlider.value / 100;
        document.getElementById("scaleVal").textContent = `${scaleSlider.value}%`;
        drawEditorCanvas();
    };

    // Filters
    const brightSlider = document.getElementById("brightSlider");
    brightSlider.oninput = () => {
        state.editor.brightness = parseInt(brightSlider.value);
        document.getElementById("brightVal").textContent = `${brightSlider.value}%`;
        drawEditorCanvas();
    };

    const contrastSlider = document.getElementById("contrastSlider");
    contrastSlider.oninput = () => {
        state.editor.contrast = parseInt(contrastSlider.value);
        document.getElementById("contrastVal").textContent = `${contrastSlider.value}%`;
        drawEditorCanvas();
    };

    const satSlider = document.getElementById("satSlider");
    satSlider.oninput = () => {
        state.editor.saturation = parseInt(satSlider.value);
        document.getElementById("satVal").textContent = `${satSlider.value}%`;
        drawEditorCanvas();
    };

    // Rotate / Flip
    document.getElementById("btnRotateCW").onclick = () => {
        state.editor.rotation = (state.editor.rotation + 90) % 360;
        drawEditorCanvas();
    };
    document.getElementById("btnRotateCCW").onclick = () => {
        state.editor.rotation = (state.editor.rotation - 90 + 360) % 360;
        drawEditorCanvas();
    };
    document.getElementById("btnFlipH").onclick = () => {
        state.editor.flipH = !state.editor.flipH;
        drawEditorCanvas();
    };
    document.getElementById("btnFlipV").onclick = () => {
        state.editor.flipV = !state.editor.flipV;
        drawEditorCanvas();
    };

    // Aspect buttons
    document.querySelectorAll(".aspect-btn").forEach(btn => {
        btn.onclick = () => {
            document.querySelectorAll(".aspect-btn").forEach(b => b.classList.remove("active"));
            btn.classList.add("active");
            state.editor.aspectRatio = btn.dataset.ratio;
            if (state.editor.aspectRatio !== "free") {
                const r = parseFloat(state.editor.aspectRatio);
                const crop = state.editor.crop;
                crop.h = Math.min(state.editor.img.height - crop.y, crop.w / r);
            }
            drawEditorCanvas();
        };
    });

    // Canvas Cropping & Direct Pan Mouse / Touch Interactions
    const canvas = document.getElementById("cropCanvas");
    
    function getCanvasCoords(e) {
        const rect = canvas.getBoundingClientRect();
        const clientX = e.touches ? e.touches[0].clientX : e.clientX;
        const clientY = e.touches ? e.touches[0].clientY : e.clientY;
        const r = state.editor.dispScale || 1;
        return {
            x: (clientX - rect.left) / r,
            y: (clientY - rect.top) / r
        };
    }

    canvas.onmousedown = (e) => {
        const pt = getCanvasCoords(e);
        const crop = state.editor.crop;
        const pad = 15;

        // Check corner handles for crop resizing
        if (Math.abs(pt.x - crop.x) < pad && Math.abs(pt.y - crop.y) < pad) {
            state.editor.dragMode = "nw";
        } else if (Math.abs(pt.x - (crop.x + crop.w)) < pad && Math.abs(pt.y - crop.y) < pad) {
            state.editor.dragMode = "ne";
        } else if (Math.abs(pt.x - crop.x) < pad && Math.abs(pt.y - (crop.y + crop.h)) < pad) {
            state.editor.dragMode = "sw";
        } else if (Math.abs(pt.x - (crop.x + crop.w)) < pad && Math.abs(pt.y - (crop.y + crop.h)) < pad) {
            state.editor.dragMode = "se";
        } else if (pt.x >= crop.x && pt.x <= crop.x + crop.w && pt.y >= crop.y && pt.y <= crop.y + crop.h) {
            state.editor.dragMode = "crop_move";
        } else {
            // Dragging outside crop box pans / moves the picture
            state.editor.dragMode = "pan";
        }

        state.editor.isDragging = true;
        state.editor.dragStart = pt;
        state.editor.posStart = { x: state.editor.posX, y: state.editor.posY };
        state.editor.cropStart = { ...crop };
    };

    window.onmousemove = (e) => {
        if (!state.editor.isDragging || !state.editor.img) return;
        const pt = getCanvasCoords(e);
        const dx = pt.x - state.editor.dragStart.x;
        const dy = pt.y - state.editor.dragStart.y;
        const crop = state.editor.crop;
        const img = state.editor.img;

        if (state.editor.dragMode === "pan") {
            state.editor.posX = Math.round(state.editor.posStart.x + dx);
            state.editor.posY = Math.round(state.editor.posStart.y + dy);
            posXSlider.value = state.editor.posX;
            posYSlider.value = state.editor.posY;
            document.getElementById("posXVal").textContent = `${state.editor.posX}px`;
            document.getElementById("posYVal").textContent = `${state.editor.posY}px`;
        } else if (state.editor.dragMode === "crop_move") {
            const start = state.editor.cropStart;
            crop.x = Math.max(0, Math.min(img.width - crop.w, start.x + dx));
            crop.y = Math.max(0, Math.min(img.height - crop.h, start.y + dy));
        } else if (state.editor.dragMode === "se") {
            const start = state.editor.cropStart;
            crop.w = Math.max(20, Math.min(img.width - crop.x, start.w + dx));
            crop.h = (state.editor.aspectRatio === "free") ?
                Math.max(20, Math.min(img.height - crop.y, start.h + dy)) :
                crop.w / parseFloat(state.editor.aspectRatio);
        } else if (state.editor.dragMode === "nw") {
            const start = state.editor.cropStart;
            const newX = Math.max(0, Math.min(start.x + start.w - 20, start.x + dx));
            const newY = Math.max(0, Math.min(start.y + start.h - 20, start.y + dy));
            crop.w = start.x + start.w - newX;
            crop.h = (state.editor.aspectRatio === "free") ?
                start.y + start.h - newY :
                crop.w / parseFloat(state.editor.aspectRatio);
            crop.x = newX;
            crop.y = (state.editor.aspectRatio === "free") ? newY : start.y + start.h - crop.h;
        }
        drawEditorCanvas();
    };

    window.onmouseup = () => {
        state.editor.isDragging = false;
    };
}

window.onload = init;
</script>

</body>
</html>
"""


def build_material_html(theme="dark", accent="cbaa0f", logo_b64=""):
    """Render Material Design 3 HTML with dynamic theme and accent."""
    is_dark = "light" not in theme.lower()
    
    if logo_b64:
        logo_html = f'<img class="logo-img" src="data:image/png;base64,{logo_b64}" alt="Scrappy" onerror="this.style.display=\'none\'">'
    else:
        logo_html = '<span class="material-symbols-rounded" style="color:var(--accent); font-size:24px;">folder</span>'

    replacements = {
        "%%BG%%": "#0a0a0f" if is_dark else "#f4f4f9",
        "%%CARD_BG%%": "#16161e" if is_dark else "#ffffff",
        "%%CARD_BORDER%%": "#2a2a35" if is_dark else "#c5c5d2",
        "%%TEXT_PRIMARY%%": "#e4e4e8" if is_dark else "#1a1a2e",
        "%%TEXT_SECONDARY%%": "#9a9aa8" if is_dark else "#5c5c6d",
        "%%INPUT_BG%%": "#1e1e28" if is_dark else "#f5f5f8",
        "%%HEADER_BG%%": "rgba(10, 10, 15, 0.95)" if is_dark else "rgba(255, 255, 255, 0.95)",
        "%%PANEL_BG%%": "#12121a" if is_dark else "#f8f8fc",
        "%%HOVER_BG%%": "#2a2a38" if is_dark else "#e8e8f0",
        "%%ACCENT%%": f"#{accent.lstrip('#')}",
        "%%LOGO_FILTER%%": "none" if is_dark else "invert(1)",
        "%%LOGO_HTML%%": logo_html
    }

    result = HTML_TEMPLATE
    for key, val in replacements.items():
        result = result.replace(key, val)
    return result


def main():
    global SERVER_ARGS
    parser = argparse.ArgumentParser(description="Folder Artwork Studio Web Server")
    parser.add_argument("--work-dir", default=os.getcwd(), help="Root directory of Scrappy")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="Port to listen on")
    parser.add_argument("--theme", default="dark", help="Theme name (dark/light)")
    parser.add_argument("--accent", default="cbaa0f", help="Accent color in hex")
    parser.add_argument("--logo", help="Path to logo icon")
    SERVER_ARGS = parser.parse_args()

    class ThreadedHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
        daemon_threads = True

    server = ThreadedHTTPServer(("0.0.0.0", SERVER_ARGS.port), FolderArtHandler)
    print(f"Folder Artwork Studio listening on http://0.0.0.0:{SERVER_ARGS.port} (theme={SERVER_ARGS.theme}, accent=#{SERVER_ARGS.accent})")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping Folder Artwork Studio...")
        server.server_close()


if __name__ == "__main__":
    main()

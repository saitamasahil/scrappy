#!/usr/bin/env python3
import json
import os
import ssl
import sys
import tempfile
import urllib.request
import zipfile

def get_ssl_context():
    try:
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        return ctx
    except Exception:
        return ssl._create_unverified_context()

def find_target_dir():
    # Detect the actual persistent application folder Scrappy is running from
    script_dir = os.path.dirname(os.path.abspath(__file__))
    
    # On device: script is located at [APP_DIR]/Scrappy/.scrappy/scripts/update.py
    if os.path.basename(os.path.abspath(os.path.join(script_dir, ".."))) == ".scrappy":
        parent_app_dir = os.path.abspath(os.path.join(script_dir, "../../.."))
        if os.path.isdir(parent_app_dir) and os.access(parent_app_dir, os.W_OK):
            return parent_app_dir
            
    candidates = [
        "/mnt/sdcard/MUOS/application",
        "/mnt/mmc/MUOS/application",
        "/run/muos/storage/application"
    ]
    for path in candidates:
        if os.path.isdir(path) and os.access(path, os.W_OK):
            return path
            
    return os.path.abspath(os.path.join(script_dir, "../.."))

def update():
    repo_url = "https://api.github.com/repos/saitamasahil/scrappy/releases/latest"
    print("Checking for latest Scrappy release...")
    sys.stdout.flush()

    req = urllib.request.Request(
        repo_url,
        headers={
            "User-Agent": "Mozilla/5.0 (Scrappy-Updater; Linux)",
            "Accept": "application/vnd.github.v3+json"
        }
    )

    try:
        ctx = get_ssl_context()
        with urllib.request.urlopen(req, context=ctx, timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except Exception as e:
        print(f"Error fetching release data: {e}")
        sys.exit(1)

    tag = data.get("tag_name")
    if not tag:
        print("Error: Could not determine latest release tag.")
        sys.exit(1)

    print(f"Latest release found: {tag}")
    sys.stdout.flush()

    assets = data.get("assets", [])
    download_url = None
    asset_name = None

    # Look for update package first (Scrappy_vX.Y.Z_update.muxapp)
    for a in assets:
        name = a.get("name", "")
        if name.endswith("_update.muxapp") or name.endswith("_update.zip"):
            download_url = a.get("browser_download_url")
            asset_name = name
            break

    # Fallback to full package if update package not present
    if not download_url:
        for a in assets:
            name = a.get("name", "")
            if name.endswith(".muxapp") or name.endswith(".zip"):
                download_url = a.get("browser_download_url")
                asset_name = name
                break

    if not download_url or not asset_name:
        print(f"Error: No suitable update asset found for release {tag}.")
        sys.exit(1)

    target_dir = find_target_dir()
    print(f"Target directory: {target_dir}")
    print(f"Downloading {asset_name}...")
    sys.stdout.flush()

    with tempfile.TemporaryDirectory() as tmpdir:
        dest_zip = os.path.join(tmpdir, asset_name)
        dl_req = urllib.request.Request(
            download_url,
            headers={"User-Agent": "Mozilla/5.0 (Scrappy-Updater; Linux)"}
        )
        try:
            with urllib.request.urlopen(dl_req, context=ctx, timeout=60) as resp, open(dest_zip, "wb") as out_file:
                while True:
                    chunk = resp.read(65536)
                    if not chunk:
                        break
                    out_file.write(chunk)
        except Exception as e:
            print(f"Error downloading update asset: {e}")
            sys.exit(1)

        print(f"Extracting {asset_name} to {target_dir}...")
        sys.stdout.flush()

        try:
            with zipfile.ZipFile(dest_zip, "r") as zip_ref:
                zip_ref.extractall(target_dir)
        except Exception as e:
            print(f"Error extracting update zip: {e}")
            sys.exit(1)

    print(f"Success: Scrappy updated to {tag}!")
    print("Please restart Scrappy to apply the update.")
    sys.stdout.flush()
    sys.exit(0)

if __name__ == "__main__":
    update()

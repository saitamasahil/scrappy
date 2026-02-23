#!/usr/bin/env python3
"""
Clear local artwork cache for a ROM after single scrape.
When Skyscraper fetches new data from thegamesdb/screenscraper, any previously
uploaded local artwork for that ROM should be removed so only the latest source exists.
"""
import argparse
import os
import xml.etree.ElementTree as ET
from pathlib import Path


MEDIA_TYPES = ("covers", "screenshots", "wheels", "marquees", "videos", "textures")


def get_gid_from_quickid(quickid_path: Path, rom: str):
    """Resolve ROM filename to game id from quickid.xml."""
    if not quickid_path.exists():
        return None
    try:
        tree = ET.parse(quickid_path)
        for q in tree.findall("quickid"):
            filepath = q.get("filepath")
            gid = q.get("id")
            if filepath and gid:
                filename = os.path.basename(filepath)
                if filename == rom:
                    return gid
    except Exception:
        pass
    return None


def clear_local_files(cache_root: Path, platform: str, gid: str) -> None:
    """Remove all local media files for the given gid across media type folders."""
    for folder in MEDIA_TYPES:
        local_dir = cache_root / platform / folder / "local"
        if not local_dir.exists():
            continue
        for p in local_dir.iterdir():
            if p.is_file() and p.stem == gid:
                try:
                    p.unlink()
                except OSError:
                    pass


def remove_local_resources_from_db(db_path: Path, gid: str) -> bool:
    """Remove all <resource source='local'> entries for gid from db.xml."""
    if not db_path.exists():
        return False
    try:
        tree = ET.parse(db_path)
        root = tree.getroot()
        to_remove = [
            r for r in root.findall("resource")
            if r.get("id") == gid and (r.get("source") or "").lower() == "local"
        ]
        for r in to_remove:
            root.remove(r)
        tree.write(str(db_path), encoding="utf-8", xml_declaration=True)
        return True
    except Exception:
        return False


def main() -> None:
    parser = argparse.ArgumentParser(description="Clear local artwork cache for a ROM")
    parser.add_argument("--cache", required=True, help="Skyscraper cache root")
    parser.add_argument("--platform", required=True, help="Platform folder (e.g. ports)")
    parser.add_argument("--rom", required=True, help="ROM filename")
    args = parser.parse_args()

    cache_root = Path(args.cache)
    platform = args.platform
    rom = args.rom

    quickid_path = cache_root / platform / "quickid.xml"
    gid = get_gid_from_quickid(quickid_path, rom)
    if not gid:
        return

    clear_local_files(cache_root, platform, gid)
    db_path = cache_root / platform / "db.xml"
    remove_local_resources_from_db(db_path, gid)


if __name__ == "__main__":
    main()

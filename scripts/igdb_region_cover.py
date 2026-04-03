#!/usr/bin/env python3
"""
Fetch a region-priority IGDB cover and write it to an output PNG path.

This script is intentionally dependency-free (stdlib only) for muOS.
"""

from __future__ import annotations

import argparse
import json
import os
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request


def _post_json(url: str, headers: dict[str, str], body: str):
    req = urllib.request.Request(url, data=body.encode("utf-8"), headers=headers, method="POST")
    with _urlopen(req, timeout=20) as resp:
        payload = resp.read().decode("utf-8", errors="replace")
        return json.loads(payload)


def _get_binary(url: str) -> bytes:
    req = urllib.request.Request(url, method="GET")
    with _urlopen(req, timeout=20) as resp:
        return resp.read()


def _urlopen(req: urllib.request.Request, timeout: int = 20):
    """
    Try default SSL verification first.
    If the device trust store is missing CA certs (common on embedded images),
    fallback to an unverified SSL context so IGDB calls still work.
    """
    try:
        return urllib.request.urlopen(req, timeout=timeout)
    except Exception as exc:
        ssl_verify_error = False

        if isinstance(exc, ssl.SSLCertVerificationError):
            ssl_verify_error = True
        elif isinstance(exc, urllib.error.URLError):
            reason = getattr(exc, "reason", None)
            if isinstance(reason, ssl.SSLCertVerificationError):
                ssl_verify_error = True
            else:
                text = str(reason or exc).lower()
                if "certificate verify failed" in text or "ssl" in text:
                    ssl_verify_error = True
        else:
            text = str(exc).lower()
            if "certificate verify failed" in text:
                ssl_verify_error = True

        if ssl_verify_error:
            unverified = ssl._create_unverified_context()
            return urllib.request.urlopen(req, timeout=timeout, context=unverified)

        raise


def _get_token(client_id: str, client_secret: str) -> str:
    query = urllib.parse.urlencode(
        {
            "client_id": client_id,
            "client_secret": client_secret,
            "grant_type": "client_credentials",
        }
    )
    url = f"https://id.twitch.tv/oauth2/token?{query}"
    req = urllib.request.Request(url, method="POST")
    with _urlopen(req, timeout=20) as resp:
        data = json.loads(resp.read().decode("utf-8", errors="replace"))
    token = data.get("access_token")
    if not token:
        raise RuntimeError("Missing IGDB access token")
    return token


def _aliases_for_region_code(code: str) -> list[str]:
    code = code.lower().strip()
    aliases = {
        "eu": ["europe", "eu"],
        "us": ["north-america", "north_america", "usa", "united-states", "united_states", "us"],
        "wor": ["worldwide", "world"],
        "jp": ["japan", "jp"],
        "uk": ["united-kingdom", "united_kingdom", "uk", "great-britain", "great_britain"],
        "au": ["australia", "au"],
        "ame": ["north-america", "south-america", "latin-america", "america", "americas"],
        "de": ["germany", "de"],
        "fr": ["france", "fr"],
        "it": ["italy", "it"],
        "es": ["spain", "es", "sp"],
        "sp": ["spain", "es", "sp"],
        "br": ["brazil", "br"],
        "kr": ["korea", "south-korea", "south_korea", "kr"],
        "cn": ["china", "cn"],
        "tw": ["taiwan", "tw"],
        "ca": ["canada", "ca"],
        "nl": ["netherlands", "nl"],
        "se": ["sweden", "se"],
        "pl": ["poland", "pl"],
        "ru": ["russia", "ru"],
    }
    return aliases.get(code, [code])


def _select_game(games: list[dict], title: str) -> dict | None:
    if not games:
        return None
    title_l = title.lower().strip()
    exact = [g for g in games if (g.get("name") or "").lower().strip() == title_l]
    return exact[0] if exact else games[0]


def _build_cover_url(cover: dict) -> str | None:
    image_id = cover.get("image_id")
    if image_id:
        return f"https://images.igdb.com/igdb/image/upload/t_cover_big/{image_id}.png"
    raw_url = cover.get("url")
    if not raw_url:
        return None
    if raw_url.startswith("//"):
        raw_url = "https:" + raw_url
    return raw_url.replace("/t_thumb/", "/t_cover_big/")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--client-id", required=True)
    parser.add_argument("--client-secret", required=True)
    parser.add_argument("--game-title", required=True)
    parser.add_argument("--platform", default="")
    parser.add_argument("--region-prios", default="eu,wor,us")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    try:
        token = _get_token(args.client_id, args.client_secret)
    except Exception as exc:
        print(f"IGDB token error: {exc}", file=sys.stderr)
        return 2

    headers = {
        "Client-ID": args.client_id,
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
    }

    # Search game candidates
    title = args.game_title.replace('"', "")
    search_body = (
        f'search "{title}"; '
        "fields id,name,cover,game_localizations; "
        "where version_parent = null; "
        "limit 10;"
    )
    try:
        games = _post_json("https://api.igdb.com/v4/games", headers, search_body)
    except Exception as exc:
        print(f"IGDB game query error: {exc}", file=sys.stderr)
        return 3

    game = _select_game(games or [], title)
    if not game:
        return 4

    # Build region priority ID list from /regions
    region_priority_ids: list[int] = []
    try:
        regions = _post_json(
            "https://api.igdb.com/v4/regions",
            headers,
            "fields id,identifier,name; limit 500;",
        )
        ident_to_id = {}
        for r in regions or []:
            ident = (r.get("identifier") or "").lower().strip()
            if ident:
                ident_to_id[ident] = r.get("id")

        for code in [c.strip() for c in args.region_prios.split(",") if c.strip()]:
            for alias in _aliases_for_region_code(code):
                rid = ident_to_id.get(alias)
                if rid and rid not in region_priority_ids:
                    region_priority_ids.append(rid)
    except Exception:
        # Non-fatal: fallback to default game cover
        pass

    selected_cover_id = None
    localization_ids = game.get("game_localizations") or []
    if localization_ids and region_priority_ids:
        ids_str = ",".join(str(x) for x in localization_ids)
        try:
            glocs = _post_json(
                "https://api.igdb.com/v4/game_localizations",
                headers,
                f"fields id,region,cover; where id = ({ids_str}); limit 500;",
            )
            by_region_cover = {}
            for loc in glocs or []:
                region_id = loc.get("region")
                cover_id = loc.get("cover")
                if region_id and cover_id and region_id not in by_region_cover:
                    by_region_cover[region_id] = cover_id
            for rid in region_priority_ids:
                if rid in by_region_cover:
                    selected_cover_id = by_region_cover[rid]
                    break
        except Exception:
            pass

    if not selected_cover_id:
        selected_cover_id = game.get("cover")
    if not selected_cover_id:
        return 5

    try:
        covers = _post_json(
            "https://api.igdb.com/v4/covers",
            headers,
            f"fields id,image_id,url; where id = {int(selected_cover_id)}; limit 1;",
        )
    except Exception as exc:
        print(f"IGDB cover query error: {exc}", file=sys.stderr)
        return 6

    if not covers:
        return 7

    cover_url = _build_cover_url(covers[0])
    if not cover_url:
        return 8

    try:
        image_bytes = _get_binary(cover_url)
        os.makedirs(os.path.dirname(args.output), exist_ok=True)
        with open(args.output, "wb") as f:
            f.write(image_bytes)
    except Exception as exc:
        print(f"IGDB cover download/write error: {exc}", file=sys.stderr)
        return 9

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

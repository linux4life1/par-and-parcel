#!/usr/bin/env python3
"""Download the photographic materials the game uses from Poly Haven.

Every file is CC0 (public domain). Each download is checked against the
checksum Poly Haven publishes. Run from the project folder:

    python3 -I tools/fetch_textures.py
"""
import hashlib
import json
import os
import sys
import urllib.request

ASSETS = [
    # the ground
    "forrest_ground_01", "grass_ground", "sand_01", "cliff_side", "gravel_floor_02",
    "sparse_grass", "burned_ground_01", "dry_ground_01", "red_sand", "dark_rock",
    # bark
    "bark_brown_02", "pine_bark", "palm_tree_bark",
    # buildings
    "painted_plaster_wall", "red_brick_03", "clay_roof_tiles_02", "roof_slates_02", "brown_planks_03", "stone_pathway",
]
MAPS = {"Diffuse": "diff", "nor_gl": "nor"}
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "textures")


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "sim-golf-asset-fetch"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def main():
    os.makedirs(OUT, exist_ok=True)
    failed = 0
    for asset in ASSETS:
        info = json.loads(get("https://api.polyhaven.com/files/" + asset))
        for key, short in MAPS.items():
            entry = info[key]["1k"]["jpg"]
            path = os.path.join(OUT, "%s_%s.jpg" % (asset, short))
            if os.path.exists(path) and hashlib.md5(open(path, "rb").read()).hexdigest() == entry["md5"]:
                continue
            data = get(entry["url"])
            if hashlib.md5(data).hexdigest() != entry["md5"]:
                print("checksum mismatch:", asset, key)
                failed += 1
                continue
            with open(path, "wb") as f:
                f.write(data)
            print("got %-24s %-4s %5d KB" % (asset, short, len(data) // 1024))
    print("done, %d failed" % failed)
    return failed


if __name__ == "__main__":
    sys.exit(main())

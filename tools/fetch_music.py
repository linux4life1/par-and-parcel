#!/usr/bin/env python3
"""Download the game's background music from OpenGameArt as Ogg Vorbis.

Every track is CC0 (public domain), written by the composers named below.
Five of them were published as Ogg Vorbis by their composers and are used
exactly as published. Two were published in other formats and are encoded
to Ogg Vorbis here, once, by the reference encoder at the quality the
others use:

  Sunset Plains   published as WAV (lossless): one clean encode.
  Another August  published only as a 320 kbps MP3: this is a second lossy
                  generation. If its composer ever publishes a lossless
                  file, point this at that instead.

Each download is checked against a checksum recorded when the track was
first chosen. Run from the project folder:

    brew install vorbis-tools ffmpeg     # once: oggenc, and ffmpeg to read the MP3
    python3 -I tools/fetch_music.py

To add a track: put it in TRACKS with an empty checksum, run this once, and
paste in the checksum it prints. Then list it in data/music.json.
"""
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zlib

BASE = "https://opengameart.org/sites/default/files/"
QUALITY = "8"          # oggenc's scale; 8 is what the composers' own Ogg files use
# file to save as, file on the site, sha256 of the download, page, title and composer
TRACKS = [
    ("bluebonnet.ogg", "bluebonnet_in_b_major_2.ogg", "81d1846539834543d9a64a6b3e50b52885f9ca2b57aa96c5b54be533aaab2266", "bluebonnet", "Bluebonnet", "Kistol"),
    ("forget_me_not.ogg", "forget_me_not_in_f_major_0.ogg", "615761e410e828e344bbc94755c385f32e337f771f108e23710c3011ca4da874", "forget-me-not", "Forget Me Not", "Kistol"),
    ("catmint.ogg", "catmint_in_c_major_3.ogg", "7c7d6000c9849da9d0fbe382f153eb90a355acb4f5a2f112203478dba4f9318e", "catmint", "Catmint", "Kistol"),
    ("daisy.ogg", "daisy_0.ogg", "8a43bbce3a552d9c7b78a520ef22a1955238abdc212a4d9d7198ca305d730bc6", "daisy", "Daisy", "Kistol"),
    ("morning_sky.ogg", "morning_2d.2_0.ogg", "73fc1726c884255259a46f2e8ac0085bd1b730da99b5a228e1e1c03ae9c6cf22", "morning-sky", "Morning Sky", "Centurion_of_war"),
    ("another_august.ogg", "013_Another_August_0.mp3", "6de6e4f770cda4d34db433e4df982deccb6877a8fcc5e32b48eeb57f770dec3b", "another-august", "Another August", "cynicmusic"),
    ("sunset_plains.ogg", "sunset_plains.wav", "f3750f8eda8bf42662b12f5726404675689b50f05ccaa968c5cb2e33d9172a62", "sunset-plains", "Sunset Plains", "Yoiyami"),
]
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "music")
# Downloads that have to be encoded wait here, so a second run does not fetch them again.
CACHE = os.path.join(tempfile.gettempdir(), "parandparcel-music-downloads")


def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def tool(name):
    path = shutil.which(name) or os.path.join("/opt/homebrew/bin", name)
    if not os.path.exists(path):
        sys.exit("%s is missing. Install it with:  brew install vorbis-tools ffmpeg" % name)
    return path


def download(remote, want, path):
    """Fetch one file, unless a copy with the right checksum is already there."""
    if os.path.exists(path) and want != "" and digest(path) == want:
        return True
    req = urllib.request.Request(BASE + remote, headers={"User-Agent": "sim-golf-asset-fetch"})
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            data = r.read()
    except Exception as e:
        print("could not get %s: %s" % (remote, e))
        return False
    got = hashlib.sha256(data).hexdigest()
    if want == "":
        print('checksum for %-28s "%s"' % (remote, got))
    elif got != want:
        print("checksum mismatch: %s" % remote)
        return False
    with open(path, "wb") as f:
        f.write(data)
    return True


def encode(src, dst, name, page, title, composer):
    """To Ogg Vorbis with the reference encoder. An MP3 is first unpacked to plain audio."""
    wav = src
    if not src.lower().endswith(".wav"):
        wav = src + ".wav"
        # 24 bits, so nothing is rounded away between the decoder and the encoder
        subprocess.run([tool("ffmpeg"), "-v", "error", "-y", "-i", src, "-map_metadata", "-1", "-fflags", "+bitexact", "-c:a", "pcm_s24le", wav], check=True)
    subprocess.run([tool("oggenc"), "-Q", "-q", QUALITY, "-s", str(zlib.crc32(name.encode()) & 0x7fffffff),
                    "-t", title, "-a", composer, "-c", "LICENSE=CC0 1.0", "-c", "CONTACT=https://opengameart.org/content/" + page,
                    "-o", dst, wav], check=True)
    if wav != src:
        os.remove(wav)


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(CACHE, exist_ok=True)
    failed = 0
    for name, remote, want, page, title, composer in TRACKS:
        path = os.path.join(OUT, name)
        as_published = remote.lower().endswith(".ogg")
        if as_published:
            if os.path.exists(path) and digest(path) == want:
                continue
            if not download(remote, want, path):
                failed += 1
                continue
            print("got %-20s %6d KB  as published" % (name, os.path.getsize(path) // 1024))
            continue
        if os.path.exists(path) and "--again" not in sys.argv[1:]:
            continue
        src = os.path.join(CACHE, remote)
        if not download(remote, want, src):
            failed += 1
            continue
        encode(src, path, name, page, title, composer)
        print("got %-20s %6d KB  encoded from %s (%d KB)  sha256 %s" % (
            name, os.path.getsize(path) // 1024, remote, os.path.getsize(src) // 1024, digest(path)))
    print("done, %d failed" % failed)
    return failed


if __name__ == "__main__":
    sys.exit(main())

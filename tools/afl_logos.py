#!/usr/bin/env python3
"""
AFL Logo Downloader for Jellyfin Backdrops
Downloads club logos from footyalmanac.com.au (direct PNG links, no auth)
and renders 1920x1080 backdrop images for Jellyfin's backdrop slideshow.

Usage:
  python3 afl_logos.py                             # downloads to ./afl_logos/
  python3 afl_logos.py --jellyfin /srv/Videos/AFL  # installs directly into Jellyfin
  python3 afl_logos.py --render-only ./my_logos/   # skip download, just render existing PNGs/SVGs

Requirements:
  pip install pillow
  # NixOS: nix shell nixpkgs#python3Packages.pillow
"""

import io, subprocess, sys, tempfile, time
import urllib.request, argparse, shutil
from pathlib import Path

try:
    from PIL import Image, ImageDraw
    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False
    print("[WARN] Pillow not installed — logos saved as-is, no backdrop generation.")
    print("       pip install pillow\n")

# ---------------------------------------------------------------------------
# Direct PNG URLs from footyalmanac.com.au — no auth, no scraping needed
# Note: logos are circa 2021; good enough for backdrops
# ---------------------------------------------------------------------------
CLUBS = [
    ("Adelaide Crows",            "https://i0.wp.com/www.footyalmanac.com.au/wp-content/uploads/Adelaide.png"),
    ("Brisbane Lions",            "https://i0.wp.com/www.footyalmanac.com.au/wp-content/uploads/Brisbane.png"),
    ("Carlton Blues",             "https://i0.wp.com/www.footyalmanac.com.au/wp-content/uploads/Carlton1.png"),
    ("Collingwood Magpies",       "https://i0.wp.com/www.footyalmanac.com.au/wp-content/uploads/Collingwood.png"),
    ("Essendon Bombers",          "https://i0.wp.com/www.footyalmanac.com.au/wp-content/uploads/Essendon1.png"),
    ("Fremantle Dockers",         "https://i0.wp.com/www.footyalmanac.com.au/wp-content/uploads/Fremantle.png"),
    ("Geelong Cats",              "https://i0.wp.com/www.footyalmanac.com.au/wp-content/uploads/Geelong1.png"),
    ("Gold Coast Suns",           "https://i0.wp.com/www.footyalmanac.com.au/wp-content/uploads/Gold-Coast.png"),
    ("GWS Giants",                "https://i0.wp.com/www.footyalmanac.com.au/wp-content/uploads/GWS.png"),
    ("Hawthorn Hawks",            "https://i0.wp.com/www.footyalmanac.com.au/wp-content/uploads/Hawthorn.jpg"),
    ("Melbourne Demons",          "https://i0.wp.com/www.footyalmanac.com.au/wp-content/uploads/Melbourne1.png"),
    ("North Melbourne Kangaroos", "https://i0.wp.com/www.footyalmanac.com.au/wp-content/uploads/North-Melbourne.png"),
    ("Port Adelaide Power",       "https://i0.wp.com/www.footyalmanac.com.au/wp-content/uploads/Port-Adelaide.jpg"),
    ("Richmond Tigers",           "https://i0.wp.com/www.footyalmanac.com.au/wp-content/uploads/Richmond.jpg"),
    ("St Kilda Saints",           "https://i0.wp.com/www.footyalmanac.com.au/wp-content/uploads/St.-Kilda1.png"),
    ("Sydney Swans",              "https://i0.wp.com/www.footyalmanac.com.au/wp-content/uploads/Sydney1.png"),
    ("West Coast Eagles",         "https://i0.wp.com/www.footyalmanac.com.au/wp-content/uploads/West-Coast1.png"),
    ("Western Bulldogs",          "https://i0.wp.com/www.footyalmanac.com.au/wp-content/uploads/Bulldogs1.png"),
]

HEADERS = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"}

BACKDROP_W, BACKDROP_H = 1920, 1080


def download_bytes(url: str) -> bytes | None:
    req = urllib.request.Request(url, headers=HEADERS)
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.read()
    except Exception as e:
        print(f"    [WARN] Download failed: {e}")
        return None


def strip_xml_entities(svg_bytes: bytes) -> bytes:
    """
    Remove DOCTYPE/entity declarations AND their inline references.
    Illustrator SVGs define custom entities like &ns_extend; in a DOCTYPE block
    then reference them in the SVG body — cairosvg rejects both.
    """
    import re
    text = svg_bytes.decode("utf-8", errors="ignore")
    # Extract entity name→value mappings before stripping
    entity_map = {}
    for m in re.finditer(r'<!ENTITY\s+(\w+)\s+"([^"]*)"', text):
        entity_map[m.group(1)] = m.group(2)
    # Strip the entire DOCTYPE block including internal subset
    text = re.sub(r'<!DOCTYPE[^>[]*(?:\[.*?\])?\s*>', '', text, flags=re.DOTALL)
    # Replace entity references with their values (or empty string if unknown)
    def replace_entity(m):
        name = m.group(1)
        return entity_map.get(name, "")
    text = re.sub(r'&(\w+);', replace_entity, text)
    return text.encode("utf-8")


def svg_to_png(svg_bytes: bytes, size: int = 700) -> bytes | None:
    # Always strip DOCTYPE/entity blocks before converting — fixes Illustrator
    # exports (Carlton, Port Adelaide) that cairosvg rejects as EntitiesForbidden
    svg_bytes = strip_xml_entities(svg_bytes)
    try:
        import cairosvg
        return cairosvg.svg2png(bytestring=svg_bytes, output_width=size, output_height=size)
    except ImportError:
        pass
    except Exception as e:
        print(f"    [WARN] cairosvg: {e}")
    with tempfile.NamedTemporaryFile(suffix=".svg", delete=False) as f:
        f.write(svg_bytes)
        svg_path = f.name
    png_path = svg_path.replace(".svg", ".png")
    try:
        r = subprocess.run(
            ["inkscape", "--export-type=png", f"--export-filename={png_path}",
             f"--export-width={size}", svg_path],
            capture_output=True, timeout=20)
        if r.returncode == 0 and Path(png_path).exists():
            return Path(png_path).read_bytes()
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    finally:
        Path(svg_path).unlink(missing_ok=True)
        Path(png_path).unlink(missing_ok=True)
    try:
        r = subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size)],
                           input=svg_bytes, capture_output=True, timeout=20)
        if r.returncode == 0 and r.stdout:
            return r.stdout
    except FileNotFoundError:
        pass
    return None


def dominant_colour(logo: "Image.Image") -> tuple:
    """
    Sample the most vivid colour from the logo's non-transparent pixels,
    then boost it to a usable glow brightness.
    """
    from collections import Counter
    small = logo.convert("RGBA").resize((120, 120), Image.LANCZOS)
    buckets = Counter()
    for r, g, b, a in small.getdata():
        if a < 128:
            continue
        brightness = (r + g + b) / 3
        if brightness < 10 or brightness > 245:
            continue
        spread = max(r, g, b) - min(r, g, b)
        if spread < 8:          # skip near-grey
            continue
        buckets[(r // 24 * 24, g // 24 * 24, b // 24 * 24)] += 1
    if not buckets:
        return (0, 40, 120)    # fallback: AFL blue
    # Pick most common colour weighted by saturation
    best = max(buckets, key=lambda k: buckets[k] * (max(k) - min(k) + 1))
    r, g, b = best
    # Boost to ensure the glow is actually visible — scale so brightest channel = 180
    peak = max(r, g, b, 1)
    scale = 180 / peak
    return (min(255, int(r * scale)), min(255, int(g * scale)), min(255, int(b * scale)))


def make_backdrop(logo_bytes: bytes) -> "Image.Image":
    logo = Image.open(io.BytesIO(logo_bytes)).convert("RGBA")

    # Pull dominant club colour from logo pixels
    cr, cg, cb = dominant_colour(logo)

    # Background: very dark tint of club colour
    bg = Image.new("RGB", (BACKDROP_W, BACKDROP_H), (max(6, cr//8), max(6, cg//8), max(6, cb//8)))

    # Radial glow: club colour blooms from centre outward
    cx, cy = BACKDROP_W // 2, BACKDROP_H // 2
    glow = Image.new("RGB", (BACKDROP_W, BACKDROP_H), (0, 0, 0))
    draw = ImageDraw.Draw(glow)
    steps = 80
    for i in range(steps, 0, -1):
        t = (i / steps) ** 2          # quadratic ease — bright centre, dark edge
        radius = int(900 * (1 - i / steps) + 50)
        fill = (int(cr * t * 0.6), int(cg * t * 0.6), int(cb * t * 0.6))
        draw.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=fill)
    bg = Image.blend(bg, glow, 1.0)

    # Logo — large, centred
    logo.thumbnail((880, 880), Image.LANCZOS)
    lx = (BACKDROP_W - logo.width) // 2
    ly = (BACKDROP_H - logo.height) // 2
    bg.paste(logo, (lx, ly), logo)

    return bg


def render_file(src: Path, out_dir: Path) -> "Path | None":
    """Render a single existing image file into a backdrop JPG."""
    raw = src.read_bytes()
    is_svg = src.suffix.lower() == ".svg" or raw[:5] in (b"<svg ", b"<?xml")
    png_bytes = svg_to_png(raw) if is_svg else raw
    if not png_bytes:
        print(f"    [WARN] Could not convert {src.name}")
        return None
    try:
        backdrop = make_backdrop(png_bytes)
        out = out_dir / f"{src.stem}.jpg"
        backdrop.save(out, "JPEG", quality=93)
        print(f"  {src.name} → {out.name} ({backdrop.width}×{backdrop.height})")
        return out
    except Exception as e:
        print(f"    [WARN] Render failed for {src.name}: {e}")
        return None


def process_club(club_name: str, url: str, out_dir: Path) -> "Path | None":
    print(f"  {club_name}")
    raw = download_bytes(url)
    if not raw:
        return None

    safe = club_name.replace(" ", "_")
    is_svg = raw[:5] in (b"<svg ", b"<?xml")
    png_bytes = svg_to_png(raw) if is_svg else raw

    if not png_bytes:
        ext = ".svg" if is_svg else Path(url).suffix
        out = out_dir / f"{safe}{ext}"
        out.write_bytes(raw)
        print(f"    → {out.name} (saved raw — install cairosvg for backdrop rendering)")
        return out

    if PIL_AVAILABLE:
        try:
            backdrop = make_backdrop(png_bytes)
            out = out_dir / f"{safe}.jpg"
            backdrop.save(out, "JPEG", quality=93)
            print(f"    → {out.name} ({backdrop.width}×{backdrop.height})")
            return out
        except Exception as e:
            print(f"    [WARN] Backdrop render failed ({e}), saving PNG")

    out = out_dir / f"{safe}.png"
    out.write_bytes(png_bytes)
    print(f"    → {out.name}")
    return out


def install_to_jellyfin(logos: list, jellyfin_root: Path):
    show_dirs = list(jellyfin_root.glob("AFL (*)")) or [jellyfin_root]
    for show_dir in show_dirs:
        print(f"\n  Installing into: {show_dir}")
        for i, logo in enumerate(logos):
            suffix = "" if i == 0 else str(i)
            dest = show_dir / f"backdrop{suffix}{logo.suffix}"
            shutil.copy2(logo, dest)
            print(f"    {dest.name}")
    print("\n  Done. Trigger a library refresh in Jellyfin to apply.")


def main():
    parser = argparse.ArgumentParser(description="Download AFL logos for Jellyfin backdrops")
    parser.add_argument("--out", default="./afl_logos", help="Output directory (default: ./afl_logos)")
    parser.add_argument("--jellyfin", help="AFL Videos root — installs backdrops into AFL (*) folders")
    parser.add_argument("--render-only", metavar="DIR",
                        help="Skip download; render all images in DIR into backdrops")
    parser.add_argument("--install-from", metavar="DIR",
                        help="Install already-rendered JPGs from DIR directly into Jellyfin (no rendering)")
    args = parser.parse_args()

    downloaded = []

    if args.install_from:
        # Just install pre-rendered backdrops — no download, no render
        src_dir = Path(args.install_from)
        exts = {".jpg", ".jpeg", ".png"}
        downloaded = sorted(f for f in src_dir.iterdir() if f.suffix.lower() in exts)
        print(f"Found {len(downloaded)} backdrops in {src_dir}/")
        if not args.jellyfin:
            print("\nSpecify --jellyfin to install them, e.g.:")
            print(f"  python3 {Path(sys.argv[0]).name} --install-from {src_dir} --jellyfin /srv/Videos/AFL")
            return
    elif args.render_only:
        out_dir = Path(args.out)
        out_dir.mkdir(parents=True, exist_ok=True)
        src_dir = Path(args.render_only)
        exts = {".png", ".jpg", ".jpeg", ".svg"}
        files = sorted(f for f in src_dir.iterdir() if f.suffix.lower() in exts)
        print(f"Rendering {len(files)} images from {src_dir}...\n")
        for f in files:
            result = render_file(f, out_dir)
            if result:
                downloaded.append(result)
        print(f"\n{len(downloaded)} backdrops ready → {out_dir}/")
    else:
        out_dir = Path(args.out)
        out_dir.mkdir(parents=True, exist_ok=True)
        print(f"Downloading {len(CLUBS)} AFL club logos from footyalmanac.com.au...\n")
        for club_name, url in CLUBS:
            result = process_club(club_name, url, out_dir)
            if result:
                downloaded.append(result)
            time.sleep(0.3)
        print(f"\n{len(downloaded)} backdrops ready → {out_dir}/")

    if args.jellyfin:
        install_to_jellyfin(downloaded, Path(args.jellyfin))
    else:
        print(f"\nTo install into Jellyfin:")
        print(f"  python3 {Path(sys.argv[0]).name} --jellyfin /srv/Videos/AFL")

if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Render terminal text captures as styled PNG screenshots.

Reads .txt files from an evidence directory and renders each as a terminal-style
PNG image with dark background, monospace font, and colored output.

Usage:
    python3 render-terminal-screenshot.py INPUT_DIR OUTPUT_DIR

    INPUT_DIR:  directory with .txt evidence captures
    OUTPUT_DIR: directory to write .png screenshots
"""

import sys
import os
import re
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    print("Installing Pillow...")
    os.system(f"{sys.executable} -m pip install Pillow -q")
    from PIL import Image, ImageDraw, ImageFont


# Terminal color scheme (dark theme)
BG_COLOR = (30, 30, 46)       # Dark blue-gray
FG_COLOR = (205, 214, 244)    # Light gray
HEADER_COLOR = (137, 180, 250) # Blue
PASS_COLOR = (166, 227, 161)   # Green
FAIL_COLOR = (243, 139, 168)   # Red
WARN_COLOR = (249, 226, 175)   # Yellow
CMD_COLOR = (180, 190, 254)    # Lavender (for $ commands)
BOX_COLOR = (108, 112, 134)    # Muted for box drawing

PADDING = 20
LINE_HEIGHT = 18
FONT_SIZE = 14


def get_font():
    """Find a monospace font."""
    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf",
        "/usr/share/fonts/truetype/ubuntu/UbuntuMono-R.ttf",
        "C:/Windows/Fonts/consola.ttf",
        "C:/Windows/Fonts/cour.ttf",
    ]
    for f in candidates:
        if os.path.exists(f):
            return ImageFont.truetype(f, FONT_SIZE)
    return ImageFont.load_default()


def color_for_line(line):
    """Pick color based on line content."""
    stripped = line.strip()
    if stripped.startswith("┌") or stripped.startswith("│") or stripped.startswith("└"):
        return HEADER_COLOR
    if stripped.startswith("$"):
        return CMD_COLOR
    if "PASS" in line or "[OK]" in line or "✓ ALLOWED" in line:
        return PASS_COLOR
    if "FAIL" in line or "✗ BLOCKED" in line or "decision" in line and "block" in line:
        return FAIL_COLOR
    if "WARN" in line or "[!!]" in line:
        return WARN_COLOR
    if stripped.startswith("━━━") or stripped.startswith("==="):
        return HEADER_COLOR
    if stripped.startswith(">>>"):
        return WARN_COLOR
    return FG_COLOR


def render_text_to_image(text, output_path):
    """Render text as a terminal-style PNG."""
    lines = text.rstrip().split("\n")

    font = get_font()

    # Calculate dimensions
    max_chars = max(len(line) for line in lines) if lines else 80
    char_width = font.getbbox("M")[2] if hasattr(font, "getbbox") else 8

    width = max(PADDING * 2 + max_chars * char_width, 900)
    height = PADDING * 2 + len(lines) * LINE_HEIGHT + 10

    # Create image
    img = Image.new("RGB", (width, height), BG_COLOR)
    draw = ImageDraw.Draw(img)

    # Title bar (fake terminal chrome)
    draw.rectangle([0, 0, width, 30], fill=(49, 50, 68))
    draw.ellipse([10, 8, 24, 22], fill=(243, 139, 168))  # Close
    draw.ellipse([30, 8, 44, 22], fill=(249, 226, 175))  # Minimize
    draw.ellipse([50, 8, 64, 22], fill=(166, 227, 161))  # Maximize

    # Render lines
    y = 35
    for line in lines:
        color = color_for_line(line)
        # Handle ANSI escape codes (strip them)
        clean = re.sub(r'\033\[[0-9;]*m', '', line)
        draw.text((PADDING, y), clean, fill=color, font=font)
        y += LINE_HEIGHT

    img.save(output_path)
    return output_path


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} INPUT_DIR OUTPUT_DIR")
        sys.exit(1)

    input_dir = Path(sys.argv[1])
    output_dir = Path(sys.argv[2])
    output_dir.mkdir(parents=True, exist_ok=True)

    txt_files = sorted(input_dir.glob("*.txt"))
    if not txt_files:
        print(f"No .txt files found in {input_dir}")
        sys.exit(1)

    for txt_file in txt_files:
        text = txt_file.read_text(encoding="utf-8", errors="replace")
        png_name = txt_file.stem + ".png"
        out_path = output_dir / png_name
        render_text_to_image(text, str(out_path))
        print(f"  Rendered: {out_path}")

    print(f"\n{len(txt_files)} screenshots rendered to {output_dir}")


if __name__ == "__main__":
    main()

#!/bin/bash
# Generate OpenFang OS wallpaper using Python + PIL or ImageMagick
# Called during build to create /usr/share/openfang/wallpaper.png

OUTPUT="${1:-/usr/share/openfang/wallpaper.png}"
mkdir -p "$(dirname "${OUTPUT}")"

# Try Python + PIL first
if python3 -c "from PIL import Image, ImageDraw, ImageFont; exit(0)" 2>/dev/null; then
    python3 << PYEOF
from PIL import Image, ImageDraw, ImageFont
import math

W, H = 1920, 1080

# Create dark gradient background
img = Image.new("RGB", (W, H))
draw = ImageDraw.Draw(img)

# Dark blue-to-purple gradient
for y in range(H):
    t = y / H
    r = int(10 + 20 * t)
    g = int(10 + 15 * t)
    b = int(40 + 60 * t)
    draw.line([(0, y), (W, y)], fill=(r, g, b))

# Draw grid lines (circuit board aesthetic)
for x in range(0, W, 80):
    draw.line([(x, 0), (x, H)], fill=(0, 255, 200, 15), width=1)
for y in range(0, H, 80):
    draw.line([(0, y), (W, y)], fill=(0, 255, 200, 15), width=1)

# Center glow
for r in range(200, 0, -1):
    alpha = int(3 * (1 - r/200))
    draw.ellipse([W//2-r, H//2-r, W//2+r, H//2+r],
                 fill=(0, 200, 255))
img2 = img.filter(__import__('PIL.ImageFilter', fromlist=['GaussianBlur']).ImageFilter.GaussianBlur(radius=50))

# Text: OpenFang OS
try:
    font_big = ImageFont.truetype("/usr/share/fonts/truetype/ubuntu/Ubuntu-B.ttf", 72)
    font_sub = ImageFont.truetype("/usr/share/fonts/truetype/ubuntu/Ubuntu-R.ttf", 28)
except:
    font_big = ImageFont.load_default()
    font_sub = ImageFont.load_default()

draw2 = ImageDraw.Draw(img2)

title = "OpenFang OS"
subtitle = "AI-Native Linux  ·  Ubuntu 24.04 LTS"

bbox = draw2.textbbox((0,0), title, font=font_big)
tw = bbox[2] - bbox[0]
draw2.text((W//2 - tw//2, H//2 - 60), title,
           fill=(0, 230, 255), font=font_big)

bbox2 = draw2.textbbox((0,0), subtitle, font=font_sub)
sw = bbox2[2] - bbox2[0]
draw2.text((W//2 - sw//2, H//2 + 30), subtitle,
           fill=(150, 200, 255), font=font_sub)

img2.save("${OUTPUT}", quality=95)
print(f"Wallpaper saved to ${OUTPUT}")
PYEOF

elif command -v convert >/dev/null 2>&1; then
    # Fall back to ImageMagick
    convert \
        -size 1920x1080 \
        gradient:"#0a0a28-#1a1a50" \
        -gravity Center \
        -fill "#00e0ff" \
        -font Ubuntu-Bold \
        -pointsize 72 \
        -annotate +0-30 "OpenFang OS" \
        -fill "#96c8ff" \
        -font Ubuntu \
        -pointsize 28 \
        -annotate +0+50 "AI-Native Linux  ·  Ubuntu 24.04 LTS" \
        "${OUTPUT}"
    echo "Wallpaper created: ${OUTPUT}"
else
    echo "Neither PIL nor ImageMagick available — using placeholder"
    # Create a minimal solid-color PNG with Python's built-in
    python3 -c "
import struct, zlib

def png(w, h, r, g, b):
    def chunk(t, d):
        c = zlib.crc32(t+d) & 0xffffffff
        return struct.pack('>I', len(d)) + t + d + struct.pack('>I', c)
    raw = b''.join(b'\x00' + bytes([r,g,b]*w) for _ in range(h))
    return b'\x89PNG\r\n\x1a\n' + \
        chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + \
        chunk(b'IDAT', zlib.compress(raw)) + \
        chunk(b'IEND', b'')

with open('${OUTPUT}', 'wb') as f:
    f.write(png(1920, 1080, 10, 10, 40))
print('Minimal wallpaper created')
"
fi

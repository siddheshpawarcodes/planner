"""Generates every app icon from assets/icon/source.jpg.

The figure is cropped to its bounds, centred on black and scaled per target:
full icons (iOS, macOS, Android legacy, web) keep it at 78% of the canvas;
Android adaptive foregrounds and web maskable icons keep it inside the safe
zone (55% and 60%). Run from planner_app/: python3 tool/make_icons.py
"""
import json
import os

from PIL import Image, ImageFilter

SRC = 'assets/icon/source.jpg'
BG = (0, 0, 0)

src = Image.open(SRC).convert('RGB')
mask = src.convert('L').filter(ImageFilter.MedianFilter(5)).point(lambda v: 255 if v > 30 else 0)
figure = src.crop(mask.getbbox())
# JPEG noise in the black surround becomes pure black.
figure = Image.eval(figure, lambda v: v)
figure.putdata([(0, 0, 0) if max(p) < 14 else p for p in figure.getdata()])


def icon(size, fill):
    canvas = Image.new('RGB', (size, size), BG)
    k = size * fill / max(figure.size)
    fig = figure.resize((round(figure.width * k), round(figure.height * k)), Image.LANCZOS)
    canvas.paste(fig, ((size - fig.width) // 2, (size - fig.height) // 2))
    return canvas


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)


# iOS: every image listed in the asset catalogue (no alpha).
ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
for e in json.load(open(f'{ios}/Contents.json'))['images']:
    px = round(float(e['size'].split('x')[0]) * int(e['scale'][0]))
    save(icon(px, 0.78), f"{ios}/{e['filename']}")

# macOS.
mac = 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
for px in (16, 32, 64, 128, 256, 512, 1024):
    save(icon(px, 0.78), f'{mac}/app_icon_{px}.png')

def silhouette(size, fill):
    """White figure on transparent, alpha from brightness (themed icons)."""
    g = icon(size, fill).convert('L')
    alpha = g.point(lambda v: max(0, min(255, (v - 24) * 4)))
    out = Image.new('RGBA', (size, size), (255, 255, 255, 0))
    out.putalpha(alpha)
    return out


# Android: legacy launcher icons, plus adaptive foregrounds (108dp canvas).
res = 'android/app/src/main/res'
for d, px in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
    save(icon(px, 0.78), f'{res}/mipmap-{d}/ic_launcher.png')
    save(icon(round(px * 108 / 48), 0.55), f'{res}/mipmap-{d}/ic_launcher_foreground.png')
    save(silhouette(round(px * 108 / 48), 0.55), f'{res}/mipmap-{d}/ic_launcher_monochrome.png')
os.makedirs(f'{res}/mipmap-anydpi-v26', exist_ok=True)
with open(f'{res}/mipmap-anydpi-v26/ic_launcher.xml', 'w') as f:
    f.write('<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@color/ic_launcher_background"/>\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
            '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
            '</adaptive-icon>\n')
with open(f'{res}/values/ic_launcher_background.xml', 'w') as f:
    f.write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
            '    <color name="ic_launcher_background">#000000</color>\n</resources>\n')

# Web.
save(icon(32, 0.78), 'web/favicon.png')
for px in (192, 512):
    save(icon(px, 0.78), f'web/icons/Icon-{px}.png')
    save(icon(px, 0.60), f'web/icons/Icon-maskable-{px}.png')
print('icons written')

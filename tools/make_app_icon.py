import io
import struct
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SIZES = (16, 24, 32, 48, 64, 128, 256)
SCALE = 8
BASE = 256
TILE = (30, 30, 30)
GREY = (138, 143, 148)
GREEN_TOP = (127, 227, 160)
GREEN_BOTTOM = (46, 158, 91)

GREY_BUBBLE = (40, 52, 168, 138, 30)
GREY_TAIL = [(60, 130), (52, 166), (92, 136)]
GREEN_OUTLINE = 7
GREEN_BUBBLE = (88, 104, 216, 192, 32)
GREEN_TAIL = [(192, 186), (206, 224), (164, 190)]


def scaled(value):
    return value * SCALE


def bubble_mask(size, box, tail, grow=0):
    mask = Image.new('L', (size, size), 0)
    draw = ImageDraw.Draw(mask)
    left, top, right, bottom, radius = box
    draw.rounded_rectangle([scaled(left - grow), scaled(top - grow), scaled(right + grow), scaled(bottom + grow)], radius=scaled(radius + grow), fill=255)
    draw.polygon([(scaled(x), scaled(y)) for x, y in tail], fill=255)
    return mask


def gradient(size):
    image = Image.new('RGB', (size, size))
    pixels = image.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            pixels[x, y] = tuple(round(GREEN_TOP[i] + (GREEN_BOTTOM[i] - GREEN_TOP[i]) * t) for i in range(3))
    return image


def render():
    size = BASE * SCALE
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    tile = Image.new('L', (size, size), 0)
    ImageDraw.Draw(tile).rounded_rectangle([0, 0, size - 1, size - 1], radius=scaled(56), fill=255)
    canvas.paste(Image.new('RGBA', (size, size), TILE + (255,)), (0, 0), tile)
    canvas.paste(Image.new('RGBA', (size, size), GREY + (255,)), (0, 0), bubble_mask(size, GREY_BUBBLE, GREY_TAIL))
    outline = bubble_mask(size, GREEN_BUBBLE, GREEN_TAIL, GREEN_OUTLINE)
    canvas.paste(Image.new('RGBA', (size, size), TILE + (255,)), (0, 0), outline)
    canvas.paste(gradient(size).convert('RGBA'), (0, 0), bubble_mask(size, GREEN_BUBBLE, GREEN_TAIL))
    alpha = canvas.getchannel('A')
    clipped = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    clipped.paste(canvas, (0, 0), tile)
    clipped.putalpha(Image.composite(alpha, Image.new('L', (size, size), 0), tile))
    return clipped


def png_bytes(image):
    out = io.BytesIO()
    image.save(out, 'PNG', optimize=True)
    return out.getvalue()


def ico_bytes(master):
    frames = [png_bytes(master.resize((size, size), Image.LANCZOS)) for size in SIZES]
    header = struct.pack('<HHH', 0, 1, len(SIZES))
    offset = 6 + 16 * len(SIZES)
    entries = b''
    for size, data in zip(SIZES, frames):
        entries += struct.pack('<BBBBHHII', size % 256, size % 256, 0, 0, 1, 32, len(data), offset)
        offset += len(data)
    return header + entries + b''.join(frames)


def svg_text():
    def poly(points):
        return ' '.join(f'{x},{y}' for x, y in points)

    def rect(box, grow=0):
        left, top, right, bottom, radius = box
        return f'<rect x="{left - grow}" y="{top - grow}" width="{right - left + 2 * grow}" height="{bottom - top + 2 * grow}" rx="{radius + grow}"/>'

    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
  <defs>
    <clipPath id="tile"><rect width="256" height="256" rx="56"/></clipPath>
    <linearGradient id="green" gradientUnits="userSpaceOnUse" x1="88" y1="104" x2="216" y2="224">
      <stop stop-color="#7FE3A0"/>
      <stop offset="1" stop-color="#2E9E5B"/>
    </linearGradient>
  </defs>
  <g clip-path="url(#tile)">
    <rect width="256" height="256" fill="#1E1E1E"/>
    <g fill="#8A8F94">{rect(GREY_BUBBLE)}<polygon points="{poly(GREY_TAIL)}"/></g>
    <g fill="#1E1E1E" stroke="#1E1E1E" stroke-width="{2 * GREEN_OUTLINE}" stroke-linejoin="round">{rect(GREEN_BUBBLE)}<polygon points="{poly(GREEN_TAIL)}"/></g>
    <g fill="url(#green)">{rect(GREEN_BUBBLE)}<polygon points="{poly(GREEN_TAIL)}"/></g>
  </g>
</svg>
'''


def main():
    master = render()
    (ROOT / 'assets/messages.ico').write_bytes(ico_bytes(master))
    (ROOT / 'assets/postbox-icon.png').write_bytes(png_bytes(master.resize((256, 256), Image.LANCZOS)))
    (ROOT / 'assets/postbox-icon.svg').write_text(svg_text())


if __name__ == '__main__':
    main()

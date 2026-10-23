import argparse
import json
from pathlib import Path
import struct
import zlib


IDS = ['slack:fixture-amber:channel-alpha', 'slack:fixture-cobalt:channel-beta',
       'whatsapp:fixture:contact-delta', 'slack:fixture-empty:channel-gamma']
COLOURS = {'amber': (240, 160, 32), 'cobalt': (48, 112, 240), 'whatsapp': (37, 211, 102)}


def read_png(path):
    raw = path.read_bytes()
    assert raw[:8] == b'\x89PNG\r\n\x1a\n', path
    offset, compressed, header = 8, bytearray(), None
    while offset < len(raw):
        length = struct.unpack_from('>I', raw, offset)[0]
        kind = raw[offset + 4:offset + 8]
        data = raw[offset + 8:offset + 8 + length]
        crc = struct.unpack_from('>I', raw, offset + 8 + length)[0]
        assert zlib.crc32(kind + data) == crc, path
        if kind == b'IHDR':
            header = struct.unpack('>IIBBBBB', data)
        elif kind == b'IDAT':
            compressed.extend(data)
        offset += length + 12
        if kind == b'IEND':
            break
    assert header is not None, path
    width, height, depth, colour, compression, filtering, interlace = header
    assert depth == 8 and colour in (2, 6) and compression == filtering == interlace == 0, header
    assert 0 < width <= 16384 and 0 < height <= 16384, header
    channels = 3 if colour == 2 else 4
    stride = width * channels
    decoded = zlib.decompress(compressed)
    assert len(decoded) == (stride + 1) * height, path
    rows, previous = [], bytearray(stride)
    for y in range(height):
        start = y * (stride + 1)
        mode = decoded[start]
        assert 0 <= mode <= 4, mode
        row = bytearray(decoded[start + 1:start + 1 + stride])
        if mode:
            for x in range(stride):
                left = row[x - channels] if x >= channels else 0
                above = previous[x]
                upper_left = previous[x - channels] if x >= channels else 0
                if mode == 1:
                    predictor = left
                elif mode == 2:
                    predictor = above
                elif mode == 3:
                    predictor = (left + above) // 2
                else:
                    predict = left + above - upper_left
                    distances = (abs(predict - left), abs(predict - above), abs(predict - upper_left))
                    predictor = (left, above, upper_left)[distances.index(min(distances))]
                row[x] = (row[x] + predictor) & 255
        rows.append([tuple(row[x:x + 3]) for x in range(0, stride, channels)])
        previous = row
    return width, height, rows


def write_png(path, rows):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))

    height, width = len(rows), len(rows[0])
    pixels = b''.join(b'\x00' + bytes(channel for pixel in row for channel in pixel) for row in rows)
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b''))


def measure(rows, colour):
    pixels = [pixel for row in rows for pixel in row]
    return sum(max(abs(a - b) for a, b in zip(pixel, colour)) <= 12 for pixel in pixels) / len(pixels)


def check_pixels(folder, capture=False):
    layout = json.loads((folder / 'workspace-icons-layout.json').read_text(encoding='utf-8-sig'))
    assert layout['ids'] == IDS
    dpi = layout['dpi']
    assert 96 <= dpi <= 192

    def px(value):
        return (value * dpi + 48) // 96

    assert layout['row_height'] == px(64)
    assert layout['client_height'] >= 4 * px(64) and layout['client_width'] > px(66)
    width, height, screenshot = read_png(folder / 'workspace-icons-list.png')
    metrics = {}
    for index, name in enumerate(['amber', 'cobalt', 'whatsapp', 'empty']):
        left = layout['list_x'] + px(12) + px(27)
        top = layout['list_y'] + index * px(64) + px(10) + px(28)
        right = layout['list_x'] + px(12) + px(48)
        bottom = layout['list_y'] + index * px(64) + px(10) + px(46)
        assert 0 <= left < right <= width and 0 <= top < bottom <= height
        rows = [row[left:right] for row in screenshot[top:bottom]]
        crop = folder / f'badge-icon-{name}.png'
        if capture:
            write_png(crop, rows)
        crop_width, crop_height, actual = read_png(crop)
        assert crop_width == right - left and crop_height == bottom - top and actual == rows, name
        white = measure(rows, (255, 255, 255))
        if name == 'empty':
            fraction = measure(rows, (51, 51, 51))
            assert fraction > 0.55 and white > 0.015, (name, fraction, white)
            assert all(measure(rows, colour) < 0.03 for colour in COLOURS.values()), name
        else:
            fraction = measure(rows, COLOURS[name])
            assert fraction > (0.50 if name == 'whatsapp' else 0.55), (name, fraction)
            assert white > 0.015, (name, 'missing letter or handset')
            assert all(measure(rows, colour) < 0.03 for other, colour in COLOURS.items() if other != name), name
        metrics[name] = dict(rect=[left, top, right, bottom], colour_fraction=fraction, white_fraction=white)
    if capture:
        (folder / 'workspace-icons-pixels.json').write_text(json.dumps(metrics, indent=2), encoding='utf-8')
    else:
        assert json.loads((folder / 'workspace-icons-pixels.json').read_text(encoding='utf-8')) == metrics
    return metrics


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('folder', type=Path)
    parser.add_argument('--capture', action='store_true')
    args = parser.parse_args()
    check_pixels(args.folder, args.capture)
    print('WORKSPACE ICON PIXELS VERIFIED: distinct team colours, letter fallback and green WhatsApp handset')

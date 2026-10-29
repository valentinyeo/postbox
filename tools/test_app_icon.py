import struct
import unittest
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SIZES = {16, 24, 32, 48, 64, 128, 256}


def png_pixels(data, size):
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    assert struct.unpack_from('>IIBBBBB', data, 16) == (size, size, 8, 6, 0, 0, 0)
    compressed = bytearray()
    offset = 8
    while offset < len(data):
        length, kind = struct.unpack_from('>I4s', data, offset)
        if kind == b'IDAT':
            compressed.extend(data[offset + 8:offset + 8 + length])
        offset += length + 12
    raw = zlib.decompress(compressed)
    stride = size * 4
    assert len(raw) == size * (stride + 1)
    rows = []
    for y in range(size):
        mode = raw[y * (stride + 1)]
        assert mode in range(5)
        row = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for x in range(stride):
            left = row[x - 4] if x >= 4 else 0
            above = rows[-1][x] if rows else 0
            corner = rows[-1][x - 4] if rows and x >= 4 else 0
            prediction = left + above - corner
            distances = [abs(prediction - value) for value in (left, above, corner)]
            paeth = (left, above, corner)[distances.index(min(distances))]
            row[x] = (row[x] + (0, left, above, (left + above) // 2, paeth)[mode]) % 256
        rows.append(row)
    return lambda x, y: rows[y][x * 4:x * 4 + 4]


def check_icon(data):
    reserved, kind, count = struct.unpack_from('<HHH', data)
    assert (reserved, kind, count) == (0, 1, 7), 'Missing app icon sizes'
    sizes = set()
    for index in range(count):
        width, height, _, _, planes, bits, length, offset = struct.unpack_from('<BBBBHHII', data, 6 + index * 16)
        size = width or 256
        assert size == (height or 256) and size not in sizes
        sizes.add(size)
        assert planes in (0, 1) and bits == 32
        pixel = png_pixels(data[offset:offset + length], size)
        r, g, b, a = pixel(round(size * 0.65), round(size * 0.3))
        assert a > 245 and r > 210 and 90 < g < 170 and b < g, 'Approved red flag missing'
        r, g, b, a = pixel(round(size * 0.27), round(size * 0.75))
        assert a > 245 and max(r, g, b) - min(r, g, b) < 5 and 140 < r < 175, 'Flag pole missing'
        r, g, b, a = pixel(round(size * 0.7), round(size * 0.8))
        assert a > 245 and max(r, g, b) < 40, 'Dark tile missing'
        assert pixel(0, 0)[3] < 10, 'Tile corners are not transparent'
    assert sizes == SIZES


class AppIconTests(unittest.TestCase):
    def test_approved_flag_at_every_shell_size(self):
        check_icon((ROOT / 'assets/messages.ico').read_bytes())

    def test_resource_and_installer_share_app_icon(self):
        self.assertIn('1 ICON "messages.ico"', (ROOT / 'assets/app.rc').read_text())
        source = (ROOT / 'src/main.zig').read_text()
        self.assertIn('LoadImageW(instance, 1, win.IMAGE_ICON', source)
        self.assertIn('icon.hIcon = LoadAppIcon(a.instance, 16, 16', source)
        installer = (ROOT / 'assets/installer.wxs').read_text()
        self.assertIn('Target="[INSTALLDIR]Messages.exe"', installer)


if __name__ == '__main__':
    unittest.main()

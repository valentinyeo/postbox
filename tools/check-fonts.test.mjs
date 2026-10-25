import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { checkFonts, sourcePaths, verifySources } from './check-fonts.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const sources = Object.fromEntries(sourcePaths.map(file => [file, fs.readFileSync(path.join(root, file), 'utf8')]));
const exists = file => fs.existsSync(path.join(root, file));

test('WAZI-161 real bundled fonts and all delivery paths pass', () => checkFonts(root));

for (const [label, file, change] of [
  ['build install', 'build.zig', source => source.replace(/^.*b\.installFile\("assets\/IBMPlexSans-Medium\.ttf".*\n/m, '')],
  ['MSI', 'assets/installer.wxs', source => source.replace(/      <Component Id="PlexMedium"[\s\S]*?<\/Component>\n/, '')],
  ['MSI reference', 'assets/installer.wxs', source => source.replace('      <ComponentRef Id="PlexMedium" />', '')],
  ['x64 release zip', '.github/workflows/release.yml', source => source.replace(' IBMPlexSans-Medium.ttf', '')],
  ['ARM64 release zip', '.github/workflows/release.yml', source => source.replace(/(Messages_arm64[^\n]+) IBMPlexSans-Medium\.ttf/, '$1')],
  ['install smoke', '.github/workflows/release.yml', source => source.replace(", 'IBMPlexSans-Medium.ttf'", '')],
  ['private load list', 'src/font_config.zig', source => source.replace('    "IBMPlexSans-Medium.ttf",\n', '')],
  ['smoke private load', 'src/main.zig', source => source.replace('const font_files = @import("font_config.zig").files;', 'const font_files = .{"IBMPlexSans-Regular.ttf", "IBMPlexSans-SemiBold.ttf", "IBMPlexSans-Bold.ttf"};')],
  ['startup private load', 'src/main.zig', source => source.replace(/(pub fn main[\s\S]*?)const font_files = @import\("font_config\.zig"\)\.files;/, '$1const font_files = .{"IBMPlexSans-Regular.ttf", "IBMPlexSans-SemiBold.ttf", "IBMPlexSans-Bold.ttf"};')],
  ['body weight', 'src/font_config.zig', source => source.replace('body_weight: i32 = 400', 'body_weight: i32 = 500')],
  ['body font size', 'src/main.zig', source => source.replace('a.font = win.CreateFontW(scaledFontHeight(17,', 'a.font = win.CreateFontW(scaledFontHeight(18,')],
]) {
  test(`WAZI-161 rejects missing or incorrect ${label}`, () => {
    verifySources(sources, exists);
    const changed = change(sources[file]);
    assert.notEqual(changed, sources[file], 'negative control must alter the intended source');
    assert.throws(() => verifySources({ ...sources, [file]: changed }, exists));
  });
}

test('WAZI-161 rejects a missing Medium asset', () => {
  verifySources(sources, exists);
  assert.throws(() => verifySources(sources, file => file !== 'assets/IBMPlexSans-Medium.ttf' && exists(file)), /missing assets\/IBMPlexSans-Medium\.ttf/);
});

test('IGSH-466 OLE initialization preserves both private font-loader boundaries', () => {
  const main = sources['src/main.zig'].replaceAll('_ = win.CoInitializeEx(null, win.COINIT_APARTMENTTHREADED);', 'if (win.OleInitialize(null) < 0) return error.OleInitializeFailed;');
  assert.notEqual(main, sources['src/main.zig']);
  verifySources({ ...sources, 'src/main.zig': main }, exists);
  const changed = main.replace('fonts_loaded[i] = win.AddFontResourceExW(font_path.ptr(), win.FR_PRIVATE, null) > 0;', 'fonts_loaded[i] = false;');
  assert.notEqual(changed, main);
  assert.throws(() => verifySources({ ...sources, 'src/main.zig': changed }, exists));
});

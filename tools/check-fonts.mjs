#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const expectedFonts = ['Regular', 'Medium', 'SemiBold', 'Bold'].map(weight => `IBMPlexSans-${weight}.ttf`).sort();
export const sourcePaths = ['build.zig', 'assets/installer.wxs', '.github/workflows/release.yml', 'src/main.zig', 'src/font_config.zig'];
const names = source => [...new Set(source.match(/IBMPlexSans-[A-Za-z]+\.ttf/g) ?? [])].sort();
const section = (source, start, end) => {
  const first = source.indexOf(start);
  assert.notEqual(first, -1, `missing section ${start}`);
  const last = source.indexOf(end, first + start.length);
  assert.notEqual(last, -1, `missing section end ${end}`);
  return source.slice(first, last);
};

export function verifySources(sources, exists) {
  const same = (label, actual) => assert.deepEqual(actual, expectedFonts, `${label}: bundled font set differs`);
  const config = section(sources['src/font_config.zig'], 'pub const files =', '\n};');
  same('font config', names(config));
  const installCalls = [...sources['build.zig'].matchAll(/b\.installFile\("assets\/(IBMPlexSans-[A-Za-z]+\.ttf)", "bin\/([^"\n]+)"\);/g)];
  same('build install', installCalls.map(match => match[1]).sort());
  for (const match of installCalls) assert.equal(match[1], match[2], 'build install destination differs');
  const installer = sources['assets/installer.wxs'];
  const components = [...installer.matchAll(/<Component Id="([^"]+)" Guid="([^"]+)">\s*<File [^>]*Name="(IBMPlexSans-[A-Za-z]+\.ttf)"[^>]*Source="\$\(var.BinDir\)([^"]+)"[^>]*KeyPath="yes"/g)];
  same('MSI', components.map(match => match[3]).sort());
  assert.equal(new Set(components.map(match => match[2])).size, components.length, 'MSI GUIDs must be distinct');
  for (const match of components) {
    assert.equal(match[3], match[4], 'MSI source differs');
    assert.match(match[2], /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i, 'invalid component GUID');
    assert.ok(installer.includes(`<ComponentRef Id="${match[1]}" />`), `missing MSI component reference ${match[1]}`);
  }
  const workflow = sources['.github/workflows/release.yml'];
  const packages = workflow.split('\n').filter(line => /zip -r .*Messages.*\.zip/.test(line));
  assert.equal(packages.length, 2, 'both CPU release zips must include fonts');
  packages.forEach((line, index) => same(`release zip ${index}`, names(line)));
  const smoke = section(workflow, '- name: Verify install', '- name: Headless Telegram smoke');
  same('install smoke', names(smoke));
  assert.match(smoke, /foreach \(\$font in @\(/);
  assert.match(smoke, /Test-Path "\$env:LOCALAPPDATA\\Programs\\Messages\\\$font"/);
  assert.match(smoke, /throw "missing bundled font \$font"/);
  const main = sources['src/main.zig'];
  const loads = [...main.matchAll(/const font_files = @import\("font_config\.zig"\)\.files;([\s\S]*?)(?=\n    _ = win\.CoInitializeEx)/g)];
  assert.equal(loads.length, 2, 'both private font loaders must use the full font list');
  for (const load of loads) {
    assert.match(load[1], /inline for \(font_files(?:, 0\.\.)?\)/);
    assert.match(load[1], /bundledFilePath\(file\)/);
    assert.match(load[1], /win\.AddFontResourceExW\(font_path\.ptr\(\), win\.FR_PRIVATE, null\)/);
  }
  assert.match(loads[0][1], /plex_loaded == font_files\.len, plex_loaded, font_files\.len/);
  const recreate = section(main, 'fn recreateFonts(', '\nfn changeFontScale');
  assert.match(recreate, /body_weight = @import\("font_config\.zig"\)\.body_weight/);
  assert.match(recreate, /comptime std\.debug\.assert\(body_weight == win\.FW_MEDIUM\)/);
  assert.match(sources['src/font_config.zig'], /pub const body_weight: i32 = 500;/);
  const fontCalls = [...recreate.matchAll(/a\.(font(?:_small|_bold|_emoji|_underline)?) = win\.CreateFontW\(scaledFontHeight\((\d+), a\.font_scale, dpi\), 0, 0, 0, ([^,]+), 0, ([01]), 0, win\.DEFAULT_CHARSET, win\.OUT_DEFAULT_PRECIS, win\.CLIP_DEFAULT_PRECIS, win\.CLEARTYPE_NATURAL_QUALITY, win\.DEFAULT_PITCH, lit\("([^"]+)"\)\);/g)];
  assert.equal(fontCalls.length, 5, 'all five native fonts must use natural ClearType');
  const expected = {
    font: ['17', 'body_weight', '0', 'IBM Plex Sans'],
    font_small: ['13', 'body_weight', '0', 'IBM Plex Sans'],
    font_bold: ['16', 'win.FW_SEMIBOLD', '0', 'IBM Plex Sans'],
    font_emoji: ['16', 'win.FW_NORMAL', '0', 'Segoe UI Emoji'],
    font_underline: ['17', 'body_weight', '1', 'IBM Plex Sans'],
  };
  for (const call of fontCalls) assert.deepEqual(call.slice(2), expected[call[1]], `font role changed: ${call[1]}`);
  for (const font of expectedFonts) assert.ok(exists(`assets/${font}`), `missing assets/${font}`);
  assert.ok(exists('assets/IBM-Plex-LICENSE.txt'), 'missing font license');
}

export function fontMetadata(bytes) {
  const tables = new Map();
  for (let index = 0; index < bytes.readUInt16BE(4); index++) {
    const at = 12 + index * 16;
    tables.set(bytes.toString('ascii', at, at + 4), bytes.subarray(bytes.readUInt32BE(at + 8), bytes.readUInt32BE(at + 8) + bytes.readUInt32BE(at + 12)));
  }
  const table = tables.get('name');
  const versions = new Set();
  for (let index = 0; index < table.readUInt16BE(2); index++) {
    const at = 6 + index * 12;
    if (table.readUInt16BE(at + 6) !== 5) continue;
    const offset = table.readUInt16BE(4) + table.readUInt16BE(at + 10);
    const text = Buffer.from(table.subarray(offset, offset + table.readUInt16BE(at + 8)));
    versions.add(table.readUInt16BE(at) === 0 || table.readUInt16BE(at) === 3 ? text.swap16().toString('utf16le') : text.toString('latin1'));
  }
  return { revision: tables.get('head').readInt32BE(4), versions: [...versions].sort(), weight: tables.get('OS/2').readUInt16BE(4) };
}

export function checkFonts(root) {
  const sources = Object.fromEntries(sourcePaths.map(file => [file, fs.readFileSync(path.join(root, file), 'utf8')]));
  verifySources(sources, file => fs.existsSync(path.join(root, file)));
  const metadata = expectedFonts.map(file => [file, fontMetadata(fs.readFileSync(path.join(root, 'assets', file)))]);
  const weights = { Regular: 400, Medium: 500, SemiBold: 600, Bold: 700 };
  for (const [file, info] of metadata) {
    assert.equal(info.revision, metadata[0][1].revision, `${file}: font revision differs`);
    assert.deepEqual(info.versions, metadata[0][1].versions, `${file}: name table version differs`);
    assert.equal(info.versions.length, 1, `${file}: missing font version`);
    assert.equal(info.weight, weights[file.match(/-([A-Za-z]+)\.ttf$/)[1]], `${file}: wrong weight`);
    console.log(`${file}: ${info.versions.join(', ')}, head.fontRevision=${info.revision}/65536, weight=${info.weight}`);
  }
  assert.match(fs.readFileSync(path.join(root, 'assets/IBM-Plex-LICENSE.txt'), 'utf8'), /SIL OPEN FONT LICENSE Version 1\.1/);
  console.log('WAZI-161 font delivery check passed');
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    checkFonts(path.resolve(process.argv[2] ?? '.'));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}

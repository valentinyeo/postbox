const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { sourceContract, verifyMetrics, html } = require('./chrome-text.cjs');
const root = path.resolve(__dirname, '../..');
const read = name => fs.readFileSync(path.join(root, name), 'utf8');

function metrics() {
    const contract = sourceContract();
    const height = base => Math.trunc((base * contract.scale * 96 + 4800) / 9600);
    return {
        text: contract.fixture.data.messages[0].Text, dpi: 96, scale: contract.scale, directwrite: true,
        body: { px: height(contract.body), weight: contract.weight, line_height: 18 },
        heading: { px: height(contract.heading), weight: 600, line_height: 17 },
        paragraph: { x: 12, y: 12, width: 500, height: 72 }, foreground: 0xffffff, background: 0x1a1a1a, surface: 0
    };
}

test('ISSUE-462 Chrome fixture text, font files, sizes, weights and line heights match src', () => {
    const contract = sourceContract();
    const native = metrics();
    verifyMetrics(native, contract);
    const page = html(native, contract.fixture);
    assert.ok(page.includes(contract.fixture.data.messages[0].Text));
    for (const name of contract.fixture.chats) assert.ok(page.includes(name));
    for (const [file, weight] of [['Regular', 400], ['SemiBold', 600]]) {
        assert.ok(page.includes(`src:url('IBMPlexSans-${file}.ttf');font-weight:${weight}`));
        assert.ok(fs.existsSync(path.join(root, 'assets', `IBMPlexSans-${file}.ttf`)));
    }
    assert.ok(page.includes(`font-size:${native.body.px}px;font-weight:${native.body.weight};line-height:${native.body.line_height}px`));
    assert.ok(page.includes(`font-size:${native.heading.px}px;font-weight:${native.heading.weight};line-height:${native.heading.line_height}px`));
    const changed = structuredClone(native);
    changed.body.line_height++;
    assert.ok(html(changed, contract.fixture).includes(`line-height:${changed.body.line_height}px`));
});

test('ISSUE-462 parity check rejects fixture, source and runtime drift', () => {
    const main = read('src/main.zig');
    for (const [before, after] of [
        ['a.font = win.CreateFontW(scaledFontHeight(17,', 'a.font = win.CreateFontW(scaledFontHeight(18,'],
        ['a.font_bold = win.CreateFontW(scaledFontHeight(16,', 'a.font_bold = win.CreateFontW(scaledFontHeight(18,'],
        ['@embedFile("verify_text.json")', '"different fixture"'],
        ['.line_height = textLineHeight(hdc, a.font.?)', '.line_height = 20']
    ]) {
        assert.ok(main.includes(before));
        assert.throws(() => sourceContract(main.replace(before, after)));
    }
    assert.throws(() => sourceContract(main, read('src/font_config.zig').replace('= 400;', '= 500;')));
    for (const mutate of [
        value => { value.text += ' drift'; },
        value => { value.body.px++; },
        value => { value.heading.px++; },
        value => { value.body.weight = 500; },
        value => { value.heading.weight = 500; },
        value => { value.directwrite = false; },
        value => { value.dpi = 120; },
        value => { value.scale++; },
        value => { value.body.line_height = 0; }
    ]) {
        const value = metrics();
        mutate(value);
        assert.throws(() => verifyMetrics(value));
    }
});

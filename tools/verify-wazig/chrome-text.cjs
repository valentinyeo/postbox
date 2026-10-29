const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '../..');
const read = name => fs.readFileSync(path.join(root, name), 'utf8');

function sourceContract(main = read('src/main.zig'), config = read('src/font_config.zig'), fixture = JSON.parse(read('src/verify_text.json')), runner = read('tools/verify-wazig/run.ps1')) {
    const scale = Number(main.match(/font_scale: i32 = (\d+),/)[1]);
    const body = Number(read('src/theme.zig').match(/pub const type_body: i32 = (\d+);/)[1]);
    assert.match(main, /a\.font = win\.CreateFontW\(scaledFontHeight\(theme\.type_body,/);
    const heading = Number(read('src/theme.zig').match(/pub const type_chat_name: i32 = (\d+);/)[1]);
    assert.match(main, /a\.font_bold = win\.CreateFontW\(scaledFontHeight\(theme\.type_chat_name,/);
    const weight = Number(config.match(/body_weight: i32 = (\d+);/)[1]);
    assert.match(main, /if \(verification_text_comparison\) _ = applyMessageData\(a, @embedFile\("verify_text.json"\), false\);/);
    assert.match(main, /\.body = \.\{ \.px = -scaledFontHeight\(theme\.type_body, a.font_scale, dpi\), \.weight = @import\("font_config.zig"\)\.body_weight, \.line_height = @divTrunc\(-scaledFontHeight\(theme.type_body, a.font_scale, dpi\) \* 3 \+ 1, 2\) \}/);
    assert.match(main, /\.heading = \.\{ \.px = -scaledFontHeight\(theme\.type_chat_name, a.font_scale, dpi\), \.weight = win.FW_SEMIBOLD, \.line_height = textLineHeight\(hdc, a.font_bold\.\?\) \}/);
    assert.match(main, /return -@divTrunc\(base \* scale \* dpi \+ 4800, 9600\);/);
    assert.match(main, /saveVerificationTextMetrics\(a, hdc, message, left \+ px\(a, 14\), text_top, right - left - px\(a, 28\), text_height\);/);
    assert.equal(body, 15);
    assert.equal(heading, 15);
    assert.equal(weight, 400);
    assert.equal(fixture.data.messages.length, 1);
    assert.equal(fixture.data.messages[0].MsgID, 'ISSUE-462-PARAGRAPH');
    assert.equal(fixture.data.messages[0].SenderName, fixture.chats[0]);
    for (const name of fixture.chats) assert.ok(runner.includes(`name = '${name}'`));
    return { scale, body, heading, weight, fixture };
}

function verifyMetrics(metrics, contract = sourceContract()) {
    const height = base => Math.trunc((base * metrics.scale * metrics.dpi + 4800) / 9600);
    assert.equal(metrics.scale, contract.scale);
    assert.equal(metrics.dpi, 96, 'Comparison must use a 100% desktop scale');
    assert.equal(metrics.directwrite, true, 'Native text fell back from DirectWrite');
    assert.equal(metrics.text, contract.fixture.data.messages[0].Text);
    assert.equal(metrics.body.px, height(contract.body));
    assert.equal(metrics.heading.px, height(contract.heading));
    assert.equal(metrics.body.weight, contract.weight);
    assert.equal(metrics.heading.weight, 600);
    for (const role of [metrics.body, metrics.heading]) {
        assert.ok(Number.isInteger(role.line_height) && role.line_height >= role.px && role.line_height < role.px * 2);
    }
    assert.ok(metrics.paragraph.width > 200 && metrics.paragraph.height >= metrics.body.line_height * 2);
    return contract;
}

function html(metrics, fixture) {
    const color = value => `#${[value & 255, (value >> 8) & 255, (value >> 16) & 255].map(n => n.toString(16).padStart(2, '0')).join('')}`;
    const escape = text => text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
    return `<!doctype html><meta charset="utf-8"><title>ISSUE-462 Chrome fixture</title>
<style>
@font-face {font-family:Plex;src:url('IBMPlexSans-Regular.ttf');font-weight:400}
@font-face {font-family:Plex;src:url('IBMPlexSans-SemiBold.ttf');font-weight:600}
* {box-sizing:border-box}
body {margin:0;background:${color(metrics.surface)};color:${color(metrics.foreground)};font-family:Plex;font-size:${metrics.body.px}px;font-weight:${metrics.body.weight};line-height:${metrics.body.line_height}px;font-synthesis:none}
aside {position:absolute;left:0;top:0;width:260px;height:100%;border-right:1px solid #333;padding:24px}
.chat {font-size:${metrics.heading.px}px;font-weight:${metrics.heading.weight};line-height:${metrics.heading.line_height}px;padding:20px 0}
header {margin-left:260px;padding:24px;font-size:${metrics.heading.px}px;font-weight:${metrics.heading.weight};line-height:${metrics.heading.line_height}px;border-bottom:1px solid #333}
article {margin:48px 0 0 284px;padding:12px;background:${color(metrics.background)};width:${metrics.paragraph.width + 24}px;border-radius:12px}
p {margin:0;width:${metrics.paragraph.width}px}
</style>
<aside>${fixture.chats.map(name => `<div class="chat">${escape(name)}</div>`).join('')}</aside>
<header>${escape(fixture.chats[0])}</header>
<article><p id="paragraph">${escape(fixture.data.messages[0].Text)}</p></article>`;
}

async function capture(evidence, bin) {
    assert.equal(process.env.GITHUB_ACTIONS, 'true', 'Chrome capture is GitHub-only');
    assert.equal(process.platform, 'win32', 'Chrome capture requires the Windows runner');
    const metrics = JSON.parse(fs.readFileSync(path.join(evidence, 'text-metrics.json'), 'utf8'));
    const contract = verifyMetrics(metrics);
    for (const file of ['IBMPlexSans-Regular.ttf', 'IBMPlexSans-SemiBold.ttf', 'IBM-Plex-LICENSE.txt']) {
        fs.copyFileSync(path.join(bin, file), path.join(evidence, file));
    }
    const pagePath = path.resolve(evidence, 'chrome.html');
    fs.writeFileSync(pagePath, html(metrics, contract.fixture));
    const { chromium } = require(path.join(process.env.RUNNER_TEMP, 'text-compare/node_modules/playwright-core'));
    const browser = await chromium.launch({ channel: 'chrome', headless: false, args: ['--force-device-scale-factor=1'] });
    try {
        const native = JSON.parse(fs.readFileSync(path.join(evidence, 'native-capture.json'), 'utf8'));
        const page = await browser.newPage({ viewport: { width: native.width, height: native.height }, deviceScaleFactor: 1 });
        await page.goto(require('node:url').pathToFileURL(pagePath).href);
        await page.evaluate(() => document.fonts.ready);
        const observed = await page.evaluate(() => {
            const paragraph = document.querySelector('p');
            const rect = paragraph.getBoundingClientRect();
            const style = getComputedStyle(paragraph);
            const heading = getComputedStyle(document.querySelector('header'));
            return {
                text: paragraph.textContent, dpr: devicePixelRatio,
                body: { px: parseFloat(style.fontSize), weight: Number(style.fontWeight), line_height: parseFloat(style.lineHeight) },
                heading: { px: parseFloat(heading.fontSize), weight: Number(heading.fontWeight), line_height: parseFloat(heading.lineHeight) },
                fonts: [...document.fonts].map(font => ({ weight: font.weight, status: font.status })),
                paragraph: { x: rect.x, y: rect.y, width: rect.width, height: rect.height }
            };
        });
        assert.equal(observed.text, metrics.text);
        assert.equal(observed.dpr, 1);
        assert.deepEqual(observed.body, metrics.body);
        assert.deepEqual(observed.heading, metrics.heading);
        assert.deepEqual(observed.fonts, [{ weight: '400', status: 'loaded' }, { weight: '600', status: 'loaded' }]);
        await page.screenshot({ path: path.join(evidence, 'chrome.png') });
        observed.chrome_version = browser.version();
        observed.mode = 'installed Chrome, headed, device scale 1';
        fs.writeFileSync(path.join(evidence, 'chrome.json'), JSON.stringify(observed, null, 2));
    } finally {
        await browser.close();
    }
}

module.exports = { sourceContract, verifyMetrics, html };
if (require.main === module) capture(process.argv[2], process.argv[3]).catch(error => { console.error(error); process.exitCode = 1; });

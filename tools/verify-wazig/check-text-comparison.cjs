const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { sourceContract, verifyMetrics, html } = require('./chrome-text.cjs');
const folder = path.resolve(process.argv[2]);
const read = name => fs.readFileSync(path.join(folder, name));
const json = name => JSON.parse(read(name).toString('utf8').replace(/^\uFEFF/, ''));
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const png = name => {
    const bytes = read(name);
    assert.equal(bytes.subarray(0, 8).toString('hex'), '89504e470d0a1a0a', name);
    assert.ok(bytes.length > 1000, name);
    return { width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20) };
};
const metrics = json('text-metrics.json');
const contract = verifyMetrics(metrics);
const chrome = json('chrome.json');
const native = json('native-capture.json');
const session = json('session.json');
assert.equal(session.feature, 'text-comparison');
assert.match(session.commit, /^[a-f0-9]{40}$/);
assert.match(session.sha256, /^[A-Fa-f0-9]{64}$/);
assert.equal(chrome.text, metrics.text);
assert.deepEqual(chrome.body, metrics.body);
assert.deepEqual(chrome.heading, metrics.heading);
assert.equal(chrome.dpr, 1);
assert.equal(chrome.mode, 'installed Chrome, headed, device scale 1');
assert.ok(chrome.chrome_version);
assert.deepEqual(chrome.fonts, [{ weight: '400', status: 'loaded' }, { weight: '600', status: 'loaded' }]);
assert.equal(read('chrome.html').toString('utf8'), html(metrics, contract.fixture));
for (const file of ['IBMPlexSans-Regular.ttf', 'IBMPlexSans-SemiBold.ttf']) {
    assert.equal(hash(read(file)), hash(fs.readFileSync(path.resolve(__dirname, '../../assets', file))));
}
assert.equal(read('IBM-Plex-LICENSE.txt').toString('utf8').replaceAll('\r\n', '\n'), fs.readFileSync(path.resolve(__dirname, '../../assets/IBM-Plex-LICENSE.txt'), 'utf8').replaceAll('\r\n', '\n'));
assert.deepEqual(png('wazig.png'), { width: native.width, height: native.height });
assert.deepEqual(png('chrome.png'), png('wazig.png'));
for (const name of ['wazig', 'chrome']) {
    const crop = png(`${name}-paragraph.png`);
    const zoom = png(`${name}-paragraph-3x.png`);
    assert.deepEqual(zoom, { width: crop.width * 3, height: crop.height * 3 });
    const paragraph = name === 'wazig' ? metrics.paragraph : chrome.paragraph;
    assert.equal(crop.width, paragraph.width);
    assert.equal(crop.height, paragraph.height);
}
const combined = png('text-comparison.png');
assert.ok(combined.width >= native.width * 2 && combined.height > native.height);
assert.ok(read('comparison-result.txt').toString().includes('ISSUE-462 COMPARISON CAPTURED:'));
assert.ok(read('cleanup.txt').toString().includes('CLEANUP PASSED:'));
assert.ok(read('result.txt').toString().includes('JOURNEY PASSED: text-comparison'));
assert.equal(fs.existsSync(path.join(folder, 'failure.txt')), false);
const effects = json('side-effects.json');
assert.equal(effects.pending_sends, 0);
assert.equal(effects.pending_archives, 0);
assert.equal(effects.sync, 'stopped');
assert.ok(effects.production_preferences_absent && effects.whatsapp_store_absent && effects.telegram_store_absent);
console.log(`ISSUE-462 EVIDENCE VERIFIED: ${session.commit}, native and Chrome ${metrics.body.px}px/${metrics.body.weight}, line ${metrics.body.line_height}px, exact fixture and font hashes, paired PNGs and 3x crops`);

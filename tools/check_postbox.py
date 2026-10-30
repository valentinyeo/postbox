from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET


def check(root):
    title = (root / 'src/messenger_view.zig').read_text()
    assert '"{s} - Postbox v{s}"' in title and '"Postbox v{s}"' in title, 'Postbox window title missing'
    main = (root / 'src/main.zig').read_text()
    assert main.count('/repos/valentinyeo/postbox/releases') == 3, 'Update endpoints must use the renamed repository'
    assert '/repos/valentinyeo/wazig/releases' not in main, 'Old update endpoint remains'
    for required in ['"Postbox v{s}"', 'migrateProductName(init);', '"Postbox.lnk"', '"Messages.lnk"', 'win.IID_IShellLinkW', 'eqlWideIgnoreCase(target[0..target_len], exe[0..exe_len])']:
        assert required in main, required
    for name in ['main.zig', 'messenger_view.zig', 'wazigctl.zig', 'control.zig']:
        for literal in re.findall(r'"(?:[^"\\]|\\.)*"', (root / 'src' / name).read_text()):
            if '\\' not in literal and not literal.startswith('"WAZIG_') and literal not in ('"Wazig.lnk"', '"Wazig Messages.lnk"'):
                assert 'Wazig' not in literal, (name, literal)
    for stable in ['Software\\\\Messages', 'MessagesOutbox-', '\\\\Wazig\\\\update']:
        assert stable in main, ('Persistent identity changed', stable)
    ns = {'w': 'http://schemas.microsoft.com/wix/2006/wi'}
    product = ET.parse(root / 'assets/installer.wxs').find('w:Product', ns)
    assert product.attrib['Name'] == 'Postbox', 'Installer product name differs'
    assert product.attrib['UpgradeCode'] == 'E2C53374-5665-593B-94F8-38573F3164D2', 'MSI upgrade identity changed'
    shortcut = product.find('.//w:Shortcut', ns)
    assert shortcut.attrib['Name'] == 'Postbox' and shortcut.attrib['Target'] == '[INSTALLDIR]Messages.exe', 'Shortcut lost the existing installation'
    assert product.find('.//w:Directory[@Id="INSTALLDIR"]', ns).attrib['Name'] == 'Messages', 'Install directory changed'
    release = (root / '.github/workflows/release.yml').read_text()
    for required in ['cp "Messages-${GITHUB_REF_NAME}.zip" "Postbox-${GITHUB_REF_NAME}.zip"', 'cp "Messages_arm64-${GITHUB_REF_NAME}.zip" "Postbox_arm64-${GITHUB_REF_NAME}.zip"', 'Postbox-*.msi']:
        assert required in release, ('Release compatibility missing', required)
    proof = (root / '.github/workflows/release-proof.yml').read_text()
    assert 'Programs\\Postbox.lnk' in proof, 'Release compatibility smoke missing'
    updater = (root / 'src/update.zig').read_text()
    assert '"Messages_arm64-" else "Messages-"' in updater and '"Postbox_arm64-" else "Postbox-"' in updater, 'Old or new updater package selector missing'
    assert 'if (branded and !std.mem.startsWith(u8, name.string, zip_asset_prefix)) continue;' in updater, 'Branded and compatibility packages are ambiguous'
    print('BRAND_CONTRACT_PROVEN')


if __name__ == '__main__':
    check(Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1])

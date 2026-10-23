from pathlib import Path
import hashlib
import json
import re
import runpy
import subprocess
import sys

folder = Path(sys.argv[1])
session = json.loads((folder / 'session.json').read_text(encoding='utf-8-sig'))
for required in ['title.json', 'title-view-1.png', 'title-inbox.png', 'drained-alt1.png']:
    assert (folder / required).is_file(), required
runpy.run_path(str(Path(__file__).with_name('check-views-evidence.py')))['check_views'](folder)
raise SystemExit(0)

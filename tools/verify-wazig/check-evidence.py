from pathlib import Path
import json
import runpy
import sys

folder = Path(sys.argv[1])
session = json.loads((folder / 'session.json').read_text(encoding='utf-8-sig'))
registry = json.loads(Path(__file__).with_name('journeys.json').read_text(encoding='utf-8'))
journey = next((row for row in registry['journeys'] if row['name'] == session['feature']), None)
assert journey is not None, f"Unknown verification journey: {session['feature']}"
validator = journey['validator']
assert validator, f"No evidence validator for journey: {session['feature']}"
namespace = runpy.run_path(str(Path(__file__).with_name(validator['file'])))
if validator.get('function'):
    namespace[validator['function']](folder)

import json
from pathlib import Path
import sys


def check_views(folder):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    def keys(result, view):
        rows = result['chats']
        assert result['messenger'] == view, (view, 'wrong view')
        assert not result['archived'], (view, 'wrong archive mode')
        assert result['total'] == len(rows) > 0, (view, 'empty or truncated view')
        assert all(row['provider'] in ('slack', 'whatsapp') for row in rows), (view, 'unexpected fixture provider')
        assert view == 'all' or all(row['provider'] == view for row in rows), (view, 'provider leak')
        identities = {(row['provider'], row['account'], row['id']) for row in rows}
        assert len(identities) == len(rows), (view, 'duplicate chat')
        return identities

    baseline = None
    for name in ['provider-views.json', 'provider-unfiltered-views.json']:
        results = read(name)
        views = {view: keys(results[view], view) for view in ['slack', 'whatsapp', 'all']}
        assert views['slack'].isdisjoint(views['whatsapp']), 'overlapping providers'
        assert views['slack'] | views['whatsapp'] == views['all'], 'incomplete provider partition'
        assert results['slack']['total'] + results['whatsapp']['total'] == results['all']['total']
        assert baseline is None or views == baseline, 'default and --all disagree'
        baseline = views

    sidebar = read('provider-sidebar.json')
    for view in ['whatsapp', 'slack', 'all']:
        state = sidebar[view]['state']
        result = sidebar[view]['chats']
        assert state['view'] == view and state['chat_count'] == result['total'], (view, 'sidebar view mismatch')
        assert keys(result, view) == baseline[view], (view, 'sidebar differs from control view')


if __name__ == '__main__':
    check_views(Path(sys.argv[1]))
    print('HUB VIEWS VERIFIED: provider purity, complete partition, --all and keyboard sidebar parity')

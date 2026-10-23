"120363000000000001@g.us`t1`t2026-10-10T10:00:00Z" | Set-Content (Join-Path $messages 'archive-state.txt')
Copy-Item (Join-Path $messages 'archive-state.txt') (Join-Path $Evidence 'legacy-archive-state.txt')

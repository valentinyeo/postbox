$cache = Join-Path $messages "msg-cache-$tag"
New-Item $cache -ItemType Directory -Force | Out-Null
$payload = @{ data = @{ messages = @(@{ MsgID = 'verify-menu-message'; Text = 'Synthetic menu verification'; SenderName = 'Verification Alpha'; FromMe = $false; Timestamp = '2026-01-01T12:00:00Z' }) } } | ConvertTo-Json -Depth 6 -Compress
"wazig-msg-cache v2`n$tag`nverify-alpha`n$payload" | Set-Content (Join-Path $cache '82d67c3e0292bfc0.msg') -NoNewline

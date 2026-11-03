$provider = Join-Path $messages 'verification-provider.json'
$seed = @{ data = @(
    @{ jid = 'verify-alpha@s.whatsapp.net'; name = 'Verification Alpha'; kind = 'direct'; last_message_ts = ''; archived = $false; unread = $false; unread_count = 0 },
    @{ jid = 'verify-beta@s.whatsapp.net'; name = 'Verification Beta'; kind = 'direct'; last_message_ts = ''; archived = $false; unread = $false; unread_count = 0 }
); messages = @{} }
$seed | ConvertTo-Json -Depth 8 | Set-Content $provider
$seed | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $messages "chats-$tag.json")

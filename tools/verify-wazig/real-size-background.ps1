$counts = Invoke-RestMethod "$($session.bridge_url)/fixture/seed" -Headers @{ Authorization = 'Bearer fixture-key-not-a-secret' }
$counts | ConvertTo-Json | Set-Content (Join-Path $session.evidence 'seed.json')
Write-Output "seeded_chats=$($counts.chats) seeded_messages=$($counts.messages) seeded_voice=$($counts.voice) seeded_images=$($counts.images) seeded_groups=$($counts.groups)"
Assert-That ($counts.chats -ge 300 -and $counts.messages -ge 6000) 'Real-size background seed shrank below its required size'
Read-Control $session chats | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'before.chats.json')

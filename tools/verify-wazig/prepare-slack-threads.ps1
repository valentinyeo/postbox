$preferences = "HKCU:\Software\MessagesVerification\$id\Software\Messages"
New-Item $preferences -Force | Out-Null
New-ItemProperty $preferences -Name 'SlackThreads-fixture-fresh' -Value 'off' -PropertyType String -Force | Out-Null
@{ account = 'fixture-fresh'; key = 'SlackThreads-fixture-fresh'; value = 'off' } | ConvertTo-Json | Set-Content (Join-Path $Evidence 'legacy-account-threads.json')
$start.Environment['WAZIG_VERIFY_RESTART'] = $id

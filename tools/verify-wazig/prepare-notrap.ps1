$preferences = "HKCU:\Software\MessagesVerification\$id\Software\Messages"
New-Item $preferences -Force | Out-Null
New-ItemProperty $preferences -Name InboxView -Value 4 -PropertyType DWord -Force | Out-Null
New-ItemProperty $preferences -Name AccountView -Value 'signal' -PropertyType String -Force | Out-Null
$saved = Get-ItemProperty $preferences
@{ view = $saved.InboxView; account = $saved.AccountView; providers_without_rows = @('signal', 'telegram') } | ConvertTo-Json | Set-Content (Join-Path $Evidence 'startup-seed.json')
$start.Environment['WAZIG_VERIFY_RESTART'] = $id

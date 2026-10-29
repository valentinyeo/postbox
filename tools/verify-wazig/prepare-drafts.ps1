$preferences = "HKCU:\Software\MessagesVerification\$id\Software\Messages"
New-Item $preferences -Force | Out-Null
New-ItemProperty $preferences -Name ComposeMinHeight -Value 80 -PropertyType DWord -Force | Out-Null
New-ItemProperty $preferences -Name ComposeDpi -Value 96 -PropertyType DWord -Force | Out-Null
$start.Environment['WAZIG_VERIFY_RESTART'] = $id

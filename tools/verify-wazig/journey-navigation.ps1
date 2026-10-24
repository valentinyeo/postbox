Send-Keys $session '^{TAB}'
$null = Wait-Until { (Read-Control $session status).selected.name -eq 'Verification Beta' } 'next chat'
Save-Screen $session after
Send-Keys $session '^+{TAB}'
$null = Wait-Until { (Read-Control $session status).selected.name -eq 'Verification Alpha' } 'previous chat'

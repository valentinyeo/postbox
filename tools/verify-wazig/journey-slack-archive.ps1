. "$PSScriptRoot/slack-archive.ps1"
$restarted = @(Invoke-SlackArchiveJourney $session $messages $start)
Assert-That ($restarted.Count -eq 1 -and $restarted[0] -is [Diagnostics.Process] -and
    $restarted[0].Id -eq $session.pid) 'Slack archive journey did not return the restarted process'
$app = $restarted[0]

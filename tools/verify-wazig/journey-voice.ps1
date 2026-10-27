. "$PSScriptRoot/voice.ps1"
Invoke-VoiceJourney $session $messages
. "$PSScriptRoot/transcript-copy.ps1"
Invoke-TranscriptCopyJourney $session $messages

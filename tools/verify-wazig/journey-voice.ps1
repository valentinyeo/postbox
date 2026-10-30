if ($env:VOICE_LANGUAGE_RESULTS) {
    . "$PSScriptRoot/journey-voice-language.ps1"
} else {
    . "$PSScriptRoot/voice.ps1"
    Invoke-VoiceJourney $session $messages
    . "$PSScriptRoot/transcript-copy.ps1"
    Invoke-TranscriptCopyJourney $session $messages
    . "$PSScriptRoot/voice-download.ps1"
    Invoke-VoiceDownloadJourney $session
}

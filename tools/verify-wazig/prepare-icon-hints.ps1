$pcm = [byte[]]::new(48000)
for ($index = 0; $index -lt 24000; $index++) {
    $sample = if (($index % 96) -lt 48) { [int16]8000 } else { [int16]-8000 }
    $bytes = [BitConverter]::GetBytes($sample)
    $pcm[$index * 2] = $bytes[0]
    $pcm[$index * 2 + 1] = $bytes[1]
}
[IO.File]::WriteAllBytes((Join-Path $messages 'voice.pcm'), $pcm)
. "$PSScriptRoot/prepare-dictation.ps1"

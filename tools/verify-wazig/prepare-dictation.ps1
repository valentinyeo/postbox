$pcm = [byte[]]::new(6400)
for ($index = 0; $index -lt 3200; $index++) {
    $sample = if (($index % 64) -lt 32) { [int16]8000 } else { [int16]-8000 }
    $bytes = [BitConverter]::GetBytes($sample)
    $pcm[$index * 2] = $bytes[0]
    $pcm[$index * 2 + 1] = $bytes[1]
}
[IO.File]::WriteAllBytes((Join-Path $messages 'dictation.pcm'), $pcm)
$transcript = 'Gr' + [char]0x00fc + [char]0x00df + 'e ' + [char]0x4e16 + [char]0x754c + "`r`nZweite Zeile"
$response = @{ results = @{ channels = @(@{ alternatives = @(@{ transcript = $transcript }) }) } } | ConvertTo-Json -Depth 8 -Compress
[IO.File]::WriteAllText((Join-Path $messages 'dictation-response.json'), $response, [Text.UTF8Encoding]::new($false))

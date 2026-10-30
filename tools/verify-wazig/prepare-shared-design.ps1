Copy-Item (Join-Path $PSScriptRoot '../fixtures/IGSH-1182/goforward.pcm') (Join-Path $messages 'dictation.pcm')
Copy-Item (Join-Path $PSScriptRoot '../fixtures/IGSH-1182/response.json') (Join-Path $messages 'dictation-response.json')

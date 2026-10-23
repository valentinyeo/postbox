function Get-EmojiPixels($Session, [string]$Name, $Rect) {
    $bounds = (Get-Edit (Get-Window $Session) '1024').Current.BoundingRectangle
    $screen = [Windows.Forms.SystemInformation]::VirtualScreen
    $cx = [int]$bounds.Left - $screen.Left
    $cy = [int]$bounds.Top - $screen.Top
    $image = [Drawing.Bitmap]::new((Join-Path $Session.evidence "$Name.png"))
    $amber = 0
    $cobalt = 0
    try {
        Assert-That ($Rect[2] -gt $Rect[0] -and $Rect[3] -gt $Rect[1]) 'Missing visible emoji or GIF bounds'
        Assert-That ($Rect[0] + $cx -ge 0 -and $Rect[1] + $cy -ge 0 -and $Rect[2] + $cx -le $image.Width -and $Rect[3] + $cy -le $image.Height) 'Emoji or GIF is outside screenshot'
        for ($y = [int]$Rect[1]; $y -lt [int]$Rect[3]; $y++) {
            for ($x = [int]$Rect[0]; $x -lt [int]$Rect[2]; $x++) {
                $pixel = $image.GetPixel($x + $cx, $y + $cy)
                if ($pixel.R -gt 210 -and $pixel.G -gt 130 -and $pixel.G -lt 190 -and $pixel.B -lt 65) { $amber++ }
                if ($pixel.B -gt 210 -and $pixel.R -lt 75 -and $pixel.G -gt 85 -and $pixel.G -lt 145) { $cobalt++ }
            }
        }
    } finally { $image.Dispose() }
    return @{ screenshot = "$Name.png"; rect = $Rect; canvas = @($cx, $cy); amber = $amber; cobalt = $cobalt }
}

function Invoke-SlackEmojiJourney($Session) {
    Send-Keys $Session '%0'
    Send-Keys $Session '^f'
    Send-Keys $Session '^a'
    Send-Keys $Session 'Verification Emoji'
    Click-Control $Session '1032'
    $null = Wait-Until { (Read-Control $Session messages).messages.Count -eq 3 } 'Slack emoji history'
    $null = Wait-Until {
        $shown = Read-Control $Session messages
        $standard = @($shown.messages | Where-Object id -eq 'EMOJI-STANDARD')[0]
        $custom = @($shown.messages | Where-Object id -eq 'EMOJI-CUSTOM')[0]
        $gif = @($shown.messages | Where-Object id -eq 'GIPHY')[0]
        $standard.text.Contains('💔') -and $standard.text.Contains('👍🏻') -and $custom.text -notmatch ':cat_alone:|:fixture_cat:' -and $gif.local -and $gif.gif_frames -eq 2 -and $gif.media[2] -gt $gif.media[0]
    } 'Resolved standard/custom emoji and decoded animated GIF'
    $shown = Read-Control $Session messages
    $standard = @($shown.messages | Where-Object id -eq 'EMOJI-STANDARD')[0]
    $custom = @($shown.messages | Where-Object id -eq 'EMOJI-CUSTOM')[0]
    $gif = @($shown.messages | Where-Object id -eq 'GIPHY')[0]
    Assert-That ($standard.text -eq '💔 ⏲️🧢 🤞 👍🏻 :unknown_fixture:') 'Standard shortcode, tone, adjacent pair or unknown fallback is wrong'
    Assert-That ($custom.text -match '^Custom [\uE000-\uF8FF] alias [\uE000-\uF8FF] 🍵 :cycle_a:$') 'Custom aliases or alias-cycle fallback are wrong'
    Assert-That ($standard.reaction -notmatch ':crycat:|:smiling_face_with_tear:|:tea:') 'Known reaction emoji stayed as text'
    Assert-That ($standard.reaction.Contains('🥲') -and $standard.reaction.Contains('🍵')) 'Missing standard reaction glyphs'
    $shown | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'emoji.messages.json')
    Save-Screen $Session emoji
    $body = Get-EmojiPixels $Session emoji $custom.bubble
    $reaction = Get-EmojiPixels $Session emoji $standard.reaction_chip
    Assert-That ($body.amber -gt 75 -and $reaction.amber -gt 75) 'Custom message/reaction image pixels were not drawn'
    Save-Screen $Session frame-a
    $first = Get-EmojiPixels $Session frame-a $gif.media
    $null = Wait-Until {
        Save-Screen $Session frame-b
        $second = Get-EmojiPixels $Session frame-b $gif.media
        ($first.amber -gt 500 -and $second.cobalt -gt 500) -or ($first.cobalt -gt 500 -and $second.amber -gt 500)
    } 'Two different rendered GIF frames'
    $second = Get-EmojiPixels $Session frame-b $gif.media
    @{ custom = $body; reaction = $reaction; frames = @($first, $second) } | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'emoji-pixels.json')
    $before = @(Read-BridgeRequests $Session | Where-Object { $_.wire_path -match '/slack/emoji|/media/.+/GIPHY' }).Count
    Send-Keys $Session '^f'
    Send-Keys $Session '^a'
    Send-Keys $Session 'Verification Other'
    $null = Wait-Until { (Read-Control $Session messages).messages[0].id -eq 'PLAIN' } 'other chat opened'
    Send-Keys $Session '^f'
    Send-Keys $Session '^a'
    Send-Keys $Session 'Verification Emoji'
    Click-Control $Session '1032'
    $null = Wait-Until { (Read-Control $Session messages).messages.Count -eq 3 } 'emoji chat reopened'
    Save-Screen $Session reopened
    $after = @(Read-BridgeRequests $Session | Where-Object { $_.wire_path -match '/slack/emoji|/media/.+/GIPHY' }).Count
    Assert-That ($before -eq $after -and $before -gt 0) 'Emoji or GIF was refetched on repaint/reopen'
    @{ before = $before; after = $after } | ConvertTo-Json | Set-Content (Join-Path $Session.evidence 'emoji-cache.json')
}

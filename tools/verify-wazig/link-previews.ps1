. "$PSScriptRoot/menus.ps1"

function Measure-LinkImage($Session, [string]$Name, $Rect, [string]$Colour) {
    $canvas = Get-Edit (Get-Window $Session) '1024'
    $bounds = $canvas.Current.BoundingRectangle
    $screen = [Windows.Forms.SystemInformation]::VirtualScreen
    $image = [Drawing.Bitmap]::new((Join-Path $Session.evidence "$Name.png"))
    $hits = 0
    $samples = 0
    try {
        for ($y = [int]$Rect[1] + 8; $y -lt [int]$Rect[3] - 8; $y += 3) {
            for ($x = [int]$Rect[0] + 8; $x -lt [int]$Rect[2] - 8; $x += 3) {
                $sx = [int]$bounds.Left + $x - $screen.Left
                $sy = [int]$bounds.Top + $y - $screen.Top
                Assert-That ($sx -ge 0 -and $sy -ge 0 -and $sx -lt $image.Width -and $sy -lt $image.Height) 'Preview is outside screenshot'
                $pixel = $image.GetPixel($sx, $sy)
                $match = if ($Colour -eq 'amber') { $pixel.R -gt 210 -and $pixel.G -gt 130 -and $pixel.G -lt 190 -and $pixel.B -lt 65 } else { $pixel.B -gt 210 -and $pixel.R -lt 75 -and $pixel.G -gt 85 -and $pixel.G -lt 145 }
                if ($match) { $hits++ }
                $samples++
            }
        }
    } finally { $image.Dispose() }
    Assert-That ($samples -gt 0 -and $hits / $samples -gt 0.1) "$Name missing rendered $Colour image pixels"
    return @{ screenshot = "$Name.png"; rect = $Rect; canvas = @([int]$bounds.Left - $screen.Left, [int]$bounds.Top - $screen.Top); colour = $Colour; hits = $hits; samples = $samples }
}

function Open-LinkChat($Session, [string]$Provider) {
    Send-Keys $Session '^f'
    Send-Keys $Session '^a'
    Send-Keys $Session "Verification Links $Provider"
    $null = Wait-Until { $shown = Read-Control $Session messages; $shown.chat.provider -eq $Provider -and $shown.messages.Count -eq 4 } "$Provider link history"
    Click-Control $Session '1032'
}

function Invoke-LinkPreviewsJourney($Session) {
    Send-Keys $Session '%0'
    $measurements = @()
    foreach ($provider in @('slack', 'whatsapp', 'telegram', 'signal')) {
        Open-LinkChat $Session $provider
        $shown = Read-Control $Session messages
        $shown | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence "$provider-initial.messages.json")
        Save-Screen $Session "$provider-initial"
        foreach ($message in $shown.messages) {
            Assert-That ($message.text -notmatch '<|\|>|&amp;') 'Raw Slack link markup is visible'
        }
        $null = Wait-Until {
            $rows = (Read-Control $Session messages).messages
            $inline = @($rows | Where-Object { $_.id -eq 'LINK-IMAGE' })[0]
            $card = @($rows | Where-Object { $_.id -eq 'LINK-PAGE' })[0]
            $inline.local -and $inline.media[2] -gt $inline.media[0] -and $card.preview.ready -and $card.preview.image -and $card.card[2] -gt $card.card[0]
        } "$provider inline image and Open Graph card"
        $shown = Read-Control $Session messages
        $shown | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence "$provider.messages.json")
        Save-Screen $Session $provider
        $inline = @($shown.messages | Where-Object { $_.id -eq 'LINK-IMAGE' })[0]
        $card = @($shown.messages | Where-Object { $_.id -eq 'LINK-PAGE' })[0]
        Assert-That ($card.preview.title -eq 'Synthetic preview' -and $card.preview.site -eq '127.0.0.1') 'Wrong page title or site'
        $measurements += Measure-LinkImage $Session $provider $inline.media amber
        $measurements += Measure-LinkImage $Session $provider $card.card cobalt
        if ($provider -eq 'slack') {
            $plain = @($shown.messages | Where-Object { $_.id -eq 'LINK-PLAIN' })[0]
            Assert-That ($plain.text -eq 'Clean page label' -and $plain.links.Count -eq 1) 'Image-free link must remain a clickable label'
            $canvas = (Get-Edit (Get-Window $Session) '1024').Current.BoundingRectangle
            $x = [int]($canvas.Left + ($inline.media[0] + $inline.media[2]) / 2)
            $y = [int]($canvas.Top + ($inline.media[1] + $inline.media[3]) / 2)
            [VerifyMenus]::Click($Session.pid, $x, $y, $false)
            Add-Content (Join-Path $Session.evidence 'actions.log') "SendInput: inline image x=$x y=$y"
            $viewer = Wait-Popup $Session 'MessagesImageViewer'
            Save-Screen $Session viewer
            @{ handle = $viewer.ToInt64(); class = 'MessagesImageViewer'; pid = $Session.pid } | ConvertTo-Json | Set-Content (Join-Path $Session.evidence 'viewer.json')
            Send-Keys $Session '{ESC}'
            $null = Wait-Until { (Find-Popup $Session 'MessagesImageViewer') -eq [IntPtr]::Zero } 'large image viewer closed'
        }
    }
    $measurements | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'image-pixels.json')
    $before = @(Read-BridgeRequests $Session | Where-Object { $_.wire_path -match '^/(pic.png|card.png|page|plain|query)' })
    Open-LinkChat $Session slack
    Save-Screen $Session reopened
    $after = @(Read-BridgeRequests $Session | Where-Object { $_.wire_path -match '^/(pic.png|card.png|page|plain|query)' })
    @{ before = $before.Count; after = $after.Count } | ConvertTo-Json | Set-Content (Join-Path $Session.evidence 'cache-requests.json')
    Assert-That ($before.Count -eq $after.Count) 'Reopening a chat refetched cached previews'
}

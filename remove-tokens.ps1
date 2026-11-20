<#
  Removes the challenge tokens shown on your League of Legends profile.

  How it works:
    1. Finds the running League client and reads its "lockfile", which holds
       the port and temporary password of the client's own local API.
    2. Asks that API (on 127.0.0.1 only) which tokens you have equipped.
    3. Sends your profile preferences back with an empty token list.
       Title, banner and crest are sent back unchanged.

  Nothing is installed, nothing leaves your machine, no admin rights needed.

  Usage:
    .\remove-tokens.ps1            remove the tokens
    .\remove-tokens.ps1 -DryRun    show what would be sent, change nothing
#>
param([switch]$DryRun)

# Everything runs inside this block so that nothing (variables, functions, the
# client password) is left behind in your PowerShell session afterwards.
& {
    param([bool]$DryRun)

    $ErrorActionPreference = 'Stop'
    $Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
    $SummaryPath = '/lol-challenges/v1/summary-player-data/local-player'
    $UpdatePath = '/lol-challenges/v1/update-player-preferences'

    function Find-Lockfile {
        $dirs = @()
        foreach ($p in Get-Process LeagueClientUx, LeagueClient -ErrorAction SilentlyContinue) {
            if ($p.Path) { $dirs += Split-Path $p.Path }
        }
        $dirs += 'C:\Riot Games\League of Legends'
        foreach ($d in $dirs | Select-Object -Unique) {
            $f = Join-Path $d 'lockfile'
            if (Test-Path -LiteralPath $f) { return $f }
        }
    }

    # Calls the League client's local API. Returns the HTTP status and body text.
    function Invoke-Lcu($Lcu, [string]$Method, [string]$Path, [string]$Body) {
        $url = "https://127.0.0.1:$($Lcu.Port)$Path"
        # -k: the client uses a self-signed certificate on localhost.
        $curlArgs = @('-s', '-k', '--max-time', '10', '-u', "riot:$($Lcu.Token)",
                      '-X', $Method, '-w', '\n%{http_code}')
        if ($Body) {
            # The body goes through a temporary file. Piping it would let PowerShell
            # add an invisible byte-order mark that the client rejects.
            $tmp = [IO.Path]::GetTempFileName()
            try {
                [IO.File]::WriteAllText($tmp, $Body, (New-Object Text.UTF8Encoding $false))
                $out = & $Curl @curlArgs -H 'Content-Type: application/json' -d "@$tmp" $url
            } finally {
                Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
            }
        } else {
            $out = & $Curl @curlArgs $url
        }
        $out = @($out)
        $status = 0
        if ($out.Count) { [void][int]::TryParse($out[-1], [ref]$status) }
        $text = if ($out.Count -gt 1) { $out[0..($out.Count - 2)] -join "`n" } else { '' }
        [pscustomobject]@{ Status = $status; Text = $text }
    }

    function Get-Profile($Lcu) {
        $r = Invoke-Lcu $Lcu GET $SummaryPath
        if ($r.Status -ne 200) { return $null }
        $r.Text | ConvertFrom-Json
    }

    function Count-Tokens($Profile) { @($Profile.topChallenges | Where-Object { $_ }).Count }

    # The parts of the profile that must NOT change, as the update request wants them.
    function Get-KeptSettings($Profile) {
        $title = ''
        if ($Profile.title -and [long]$Profile.title.itemId -gt 0) { $title = "$($Profile.title.itemId)" }
        [ordered]@{
            title                    = $title
            bannerAccent             = "$($Profile.bannerId)"
            crestBorder              = "$($Profile.crestId)"
            prestigeCrestBorderLevel = [int]$Profile.prestigeCrestBorderLevel
        }
    }

    if (-not (Test-Path -LiteralPath $Curl)) {
        Write-Host 'curl.exe was not found. This needs Windows 10 (1803) or newer.' -ForegroundColor Red
        return
    }

    $lockfile = Find-Lockfile
    if (-not $lockfile) {
        Write-Host 'League client not found. Open League of Legends, log in, then run this again.' -ForegroundColor Yellow
        return
    }

    # lockfile format: name:pid:port:password:protocol
    $parts = (Get-Content -LiteralPath $lockfile -Raw).Trim().Split(':')
    if ($parts.Count -lt 5 -or $parts[2] -notmatch '^\d+$') {
        Write-Host "Could not read the client lockfile at $lockfile." -ForegroundColor Red
        return
    }
    $lcu = @{ Port = $parts[2]; Token = $parts[3] }

    # Read the client's replies as UTF-8 so token names in any language display correctly.
    $oldEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [Text.Encoding]::UTF8

        # The client occasionally fails a request while it is busy, so try a few times.
        $before = $null
        for ($i = 0; $i -lt 3 -and -not $before; $i++) {
            if ($i -gt 0) { Start-Sleep -Seconds 1 }
            $before = Get-Profile $lcu
        }
        if (-not $before) {
            Write-Host 'Could not reach the League client. Make sure it is open and you are logged in.' -ForegroundColor Yellow
            return
        }

        $count = Count-Tokens $before
        if ($count -eq 0) {
            Write-Host 'No tokens are equipped on your profile. Nothing to do.' -ForegroundColor Green
            return
        }

        Write-Host "Tokens currently equipped ($count):"
        foreach ($t in $before.topChallenges) { Write-Host "  - $($t.name)" }

        $kept = Get-KeptSettings $before
        $request = [ordered]@{ challengeIds = @() } + $kept
        $body = $request | ConvertTo-Json -Compress

        if ($DryRun) {
            Write-Host "`nDry run. Would send to ${UpdatePath}:"
            Write-Host "  $body"
            return
        }

        $r = Invoke-Lcu $lcu POST $UpdatePath $body
        if ($r.Status -lt 200 -or $r.Status -ge 300) {
            Write-Host "The client rejected the request (HTTP $($r.Status)). Nothing was changed." -ForegroundColor Red
            if ($r.Text) { Write-Host $r.Text }
            return
        }

        # The client updates the profile a moment after accepting the request.
        $after = $null
        for ($i = 0; $i -lt 10; $i++) {
            Start-Sleep -Milliseconds 500
            $after = Get-Profile $lcu
            if ($after -and (Count-Tokens $after) -eq 0) { break }
        }

        if (-not $after -or (Count-Tokens $after) -gt 0) {
            Write-Host 'Request was accepted, but the profile still shows tokens. Reopen your profile to check.' -ForegroundColor Yellow
            return
        }

        Write-Host "`nDone. Your tokens have been removed." -ForegroundColor Green

        $now = Get-KeptSettings $after
        foreach ($key in $kept.Keys) {
            if ("$($kept[$key])" -ne "$($now[$key])") {
                Write-Host "Heads up: '$key' changed from '$($kept[$key])' to '$($now[$key])'. Re-select it on your profile." -ForegroundColor Yellow
            }
        }
    } finally {
        [Console]::OutputEncoding = $oldEncoding
    }
} $DryRun.IsPresent

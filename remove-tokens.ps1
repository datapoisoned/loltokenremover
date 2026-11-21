<#
  Token Remover
  Removes the three challenge tokens shown on your League of Legends profile.

  THE SHORT VERSION
    The League client on your PC has a built-in way to save your profile with
    no tokens on it. Riot just never added a button for it. This script asks
    the client to do that one thing.

  WHAT IT DOES, STEP BY STEP
    1. Finds the League client that is open on this PC.
    2. Reads the client's "lockfile". That is a small text file the client
       writes when it starts. It holds the port number and a temporary
       password for the client's own local control panel (its "local API").
       The client's own windows use the same thing to talk to it.
    3. Asks the client which tokens you have on your profile right now.
    4. Tells the client to save your profile with an empty token list.
       Your title, banner and crest are sent back exactly as they were.
    5. Asks the client again to confirm the tokens are really gone.

  WHAT IT DOES NOT DO
    - It does not install anything or need admin rights.
    - It does not touch any game files.
    - It does not see your Riot username or password.
    - It does not talk to the internet. Every request goes to 127.0.0.1,
      which always means "this same computer".

  USAGE
    .\remove-tokens.ps1            remove the tokens
    .\remove-tokens.ps1 -DryRun    show what would be sent, change nothing
#>

# -DryRun is an optional switch. With it, the script shows what it would send
# to the client and then stops without changing anything.
param([switch]$DryRun)

# Everything runs inside this block ( & { ... } ) so that nothing is left
# behind in your PowerShell window afterwards: no variables, no functions,
# and not the client's temporary password.
& {
    param([bool]$DryRun)

    # Stop at the first unexpected error instead of carrying on half-done.
    $ErrorActionPreference = 'Stop'

    # curl.exe is a small download tool that ships with Windows 10 and 11.
    # We use the copy inside the Windows folder, never one from somewhere else.
    $Curl = Join-Path $env:SystemRoot 'System32\curl.exe'

    # The two addresses inside the League client that this script uses.
    # These are the only two things it ever asks the client for.
    #   SummaryPath: "what does my profile look like right now?" (read only)
    #   UpdatePath:  "save my profile with these settings"
    $SummaryPath = '/lol-challenges/v1/summary-player-data/local-player'
    $UpdatePath = '/lol-challenges/v1/update-player-preferences'

    # ------------------------------------------------------------------
    # Find-Lockfile
    # Looks for the client's lockfile and returns its location.
    # Returns nothing if League is not open.
    # ------------------------------------------------------------------
    function Find-Lockfile {
        $dirs = @()

        # If the League client is running, look in the folder it runs from.
        # This works wherever League is installed.
        foreach ($p in Get-Process LeagueClientUx, LeagueClient -ErrorAction SilentlyContinue) {
            if ($p.Path) { $dirs += Split-Path $p.Path }
        }

        # Also try the default install folder, as a fallback.
        $dirs += 'C:\Riot Games\League of Legends'

        # Return the first lockfile that actually exists.
        foreach ($d in $dirs | Select-Object -Unique) {
            $f = Join-Path $d 'lockfile'
            if (Test-Path -LiteralPath $f) { return $f }
        }
    }

    # ------------------------------------------------------------------
    # Invoke-Lcu
    # Sends one request to the League client on this PC and returns its
    # reply: the status number (200 means OK) and the reply text.
    #   $Lcu     the port and temporary password from the lockfile
    #   $Method  GET (read something) or POST (change something)
    #   $Path    which address inside the client to call
    #   $Body    the data to send, if any
    # ------------------------------------------------------------------
    function Invoke-Lcu($Lcu, [string]$Method, [string]$Path, [string]$Body) {
        # 127.0.0.1 is this computer. The request never leaves your PC.
        $url = "https://127.0.0.1:$($Lcu.Port)$Path"

        # Options for curl:
        #   -s             quiet, no progress bar
        #   -k             accept the client's home-made security certificate.
        #                  The client makes its own for 127.0.0.1, so there is
        #                  no official one to check against.
        #   --max-time 10  give up after 10 seconds
        #   -u riot:...    log in to the client with its temporary password
        #   -X             GET or POST
        #   -w             print the status number on a last line of its own
        $curlArgs = @('-s', '-k', '--max-time', '10', '-u', "riot:$($Lcu.Token)",
                      '-X', $Method, '-w', '\n%{http_code}')
        if ($Body) {
            # The data goes through a temporary file. Piping it straight in
            # would let PowerShell add an invisible marker at the start that
            # the client rejects.
            $tmp = [IO.Path]::GetTempFileName()
            try {
                [IO.File]::WriteAllText($tmp, $Body, (New-Object Text.UTF8Encoding $false))
                $out = & $Curl @curlArgs -H 'Content-Type: application/json' -d "@$tmp" $url
            } finally {
                # Always delete the temporary file, even if something failed.
                Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
            }
        } else {
            $out = & $Curl @curlArgs $url
        }

        # curl gave back lines of text. The last line is the status number,
        # everything before it is the client's reply.
        $out = @($out)
        $status = 0
        if ($out.Count) { [void][int]::TryParse($out[-1], [ref]$status) }
        $text = if ($out.Count -gt 1) { $out[0..($out.Count - 2)] -join "`n" } else { '' }
        [pscustomobject]@{ Status = $status; Text = $text }
    }

    # ------------------------------------------------------------------
    # Get-Profile
    # Asks the client for your current profile (tokens, title, banner,
    # crest). Read only. Returns nothing if the client did not answer OK.
    # ------------------------------------------------------------------
    function Get-Profile($Lcu) {
        $r = Invoke-Lcu $Lcu GET $SummaryPath
        if ($r.Status -ne 200) { return $null }
        $r.Text | ConvertFrom-Json
    }

    # ------------------------------------------------------------------
    # Count-Tokens
    # How many tokens are on the profile (0 to 3).
    # ------------------------------------------------------------------
    function Count-Tokens($Profile) { @($Profile.topChallenges | Where-Object { $_ }).Count }

    # ------------------------------------------------------------------
    # Get-KeptSettings
    # The parts of your profile that must NOT change: title, banner and
    # crest. The client saves all of these together with the tokens, so we
    # read your current ones and send them straight back unchanged.
    # ------------------------------------------------------------------
    function Get-KeptSettings($Profile) {
        # An empty title means "no title equipped".
        $title = ''
        if ($Profile.title -and [long]$Profile.title.itemId -gt 0) { $title = "$($Profile.title.itemId)" }
        [ordered]@{
            title                    = $title
            bannerAccent             = "$($Profile.bannerId)"
            crestBorder              = "$($Profile.crestId)"
            prestigeCrestBorderLevel = [int]$Profile.prestigeCrestBorderLevel
        }
    }

    # ==================================================================
    # The script starts here.
    # ==================================================================

    # Check that Windows has curl.exe. Very old versions of Windows do not.
    if (-not (Test-Path -LiteralPath $Curl)) {
        Write-Host 'curl.exe was not found. This needs Windows 10 (1803) or newer.' -ForegroundColor Red
        return
    }

    # Step 1: find the League client. If it is not open, say so and stop.
    $lockfile = Find-Lockfile
    if (-not $lockfile) {
        Write-Host 'League client not found. Open League of Legends, log in, then run this again.' -ForegroundColor Yellow
        return
    }

    # Step 2: read the lockfile. It is one line that looks like this:
    #   name:pid:port:password:protocol
    # We only need the port (3rd part) and the temporary password (4th part).
    # The password is made up fresh every time League starts, and it only
    # works on this PC. It is not your Riot password.
    $parts = (Get-Content -LiteralPath $lockfile -Raw).Trim().Split(':')
    if ($parts.Count -lt 5 -or $parts[2] -notmatch '^\d+$') {
        Write-Host "Could not read the client lockfile at $lockfile." -ForegroundColor Red
        return
    }
    $lcu = @{ Port = $parts[2]; Token = $parts[3] }

    # Read the client's replies as UTF-8 so token names in any language show
    # up correctly. The old setting is put back at the very end.
    $oldEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [Text.Encoding]::UTF8

        # Step 3: ask the client for your current profile.
        # The client occasionally fails a request while it is busy, so try up
        # to three times, one second apart.
        $before = $null
        for ($i = 0; $i -lt 3 -and -not $before; $i++) {
            if ($i -gt 0) { Start-Sleep -Seconds 1 }
            $before = Get-Profile $lcu
        }
        if (-not $before) {
            Write-Host 'Could not reach the League client. Make sure it is open and you are logged in.' -ForegroundColor Yellow
            return
        }

        # If there are no tokens on the profile, there is nothing to do.
        $count = Count-Tokens $before
        if ($count -eq 0) {
            Write-Host 'No tokens are equipped on your profile. Nothing to do.' -ForegroundColor Green
            return
        }

        # Show which tokens are about to be removed.
        Write-Host "Tokens currently equipped ($count):"
        foreach ($t in $before.topChallenges) { Write-Host "  - $($t.name)" }

        # Build the message for the client: an empty token list, plus your
        # title, banner and crest exactly as they are now.
        $kept = Get-KeptSettings $before
        $request = [ordered]@{ challengeIds = @() } + $kept
        $body = $request | ConvertTo-Json -Compress

        # With -DryRun, show the message and stop here. Nothing is changed.
        if ($DryRun) {
            Write-Host "`nDry run. Would send to ${UpdatePath}:"
            Write-Host "  $body"
            return
        }

        # Step 4: send it. This is the one request that changes anything.
        $r = Invoke-Lcu $lcu POST $UpdatePath $body
        if ($r.Status -lt 200 -or $r.Status -ge 300) {
            # The client said no. Report it and stop. Nothing was changed.
            Write-Host "The client rejected the request (HTTP $($r.Status)). Nothing was changed." -ForegroundColor Red
            if ($r.Text) { Write-Host $r.Text }
            return
        }

        # Step 5: check that it worked. The client updates the profile a
        # moment after accepting the request, so look again every half second
        # for up to five seconds until the tokens are gone.
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

        # Last safety check: compare your title, banner and crest with what
        # they were before. If the client changed any of them, tell you so
        # you can pick it again.
        $now = Get-KeptSettings $after
        foreach ($key in $kept.Keys) {
            if ("$($kept[$key])" -ne "$($now[$key])") {
                Write-Host "Heads up: '$key' changed from '$($kept[$key])' to '$($now[$key])'. Re-select it on your profile." -ForegroundColor Yellow
            }
        }
    } finally {
        # Put the text setting of your PowerShell window back how it was.
        [Console]::OutputEncoding = $oldEncoding
    }
} $DryRun.IsPresent

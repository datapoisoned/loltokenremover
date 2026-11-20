# Builds index.html from site/page.html, site/hero.js and remove-tokens.ps1.
#
# index.html is one file that works two ways:
#   - a browser opening tokenremover.com sees the web page
#   - PowerShell running "irm tokenremover.com | iex" runs the script
#
# It works because PowerShell treats everything between <# and #> as a comment,
# so the web page is wrapped in a comment and the script sits in a hidden
# <script type="text/plain"> block that browsers do not show or run.

$ErrorActionPreference = 'Stop'
$page = [IO.File]::ReadAllText("$PSScriptRoot\site\page.html") -replace "`r`n", "`n"
$script = [IO.File]::ReadAllText("$PSScriptRoot\remove-tokens.ps1") -replace "`r`n", "`n"
$hero = [IO.File]::ReadAllText("$PSScriptRoot\site\hero.js") -replace "`r`n", "`n"
$page = $page.TrimEnd() + "`n<script type=`"module`">`n" + $hero.Trim() + "`n</script>"

if ($page.Contains('#>')) { throw 'site/page.html must not contain "#>" (it would end the PowerShell comment early).' }
if ($script -match '(?i)</script') { throw 'remove-tokens.ps1 must not contain "</script".' }
if (($page + $script) -match '[^\x00-\x7F]') { throw 'Keep both files plain ASCII.' }

$out = '<# ' + $page.TrimEnd() + "`n<script type=`"text/plain`"> #>`n" +
       $script.Trim() + "`n<# </script></body></html> #>`n"

[IO.File]::WriteAllText("$PSScriptRoot\index.html", $out, (New-Object Text.UTF8Encoding $false))
"Built index.html ($($out.Length) characters)"

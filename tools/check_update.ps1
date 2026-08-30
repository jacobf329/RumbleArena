# One line if a newer version exists, silence otherwise.
#
# Called by the play launcher, so it is bounded and never fails loudly: being
# offline, rate-limited, or behind a captive portal must cost a moment and then
# get out of the way of the game.
param([Parameter(Mandatory = $true)][string]$ProjectDir)

try {
	& (Join-Path $PSScriptRoot 'update.ps1') -ProjectDir $ProjectDir -CheckOnly -TimeoutSec 4
}
catch { }
exit 0

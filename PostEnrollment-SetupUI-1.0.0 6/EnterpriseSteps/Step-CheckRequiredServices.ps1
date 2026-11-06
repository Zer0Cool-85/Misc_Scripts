[CmdletBinding()]
param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string[]]$ServiceNames, [ValidateRange(0,300)][int]$WaitSeconds=45)
. (Join-Path $PSScriptRoot 'Enterprise.Common.ps1')
foreach ($name in $ServiceNames) { if ($name -notmatch '^[A-Za-z0-9._-]+$') { throw 'Specify exact service names, without wildcards.' } }
$watch=[Diagnostics.Stopwatch]::StartNew()
do {
    $missing=@()
    foreach ($name in $ServiceNames) {
        $s=Get-Service -Name $name -ErrorAction SilentlyContinue
        if (-not $s -or $s.Status -ne 'Running') { $missing+=$name }
    }
    if (-not $missing.Count) { Set-EnterpriseProgress ('Required services running: '+($ServiceNames -join ', ')); return }
    if ($watch.Elapsed.TotalSeconds -ge $WaitSeconds) { break }
    Start-Sleep -Seconds 2
} while ($true)
throw ('Expected running services missing or stopped: '+($missing -join ', '))

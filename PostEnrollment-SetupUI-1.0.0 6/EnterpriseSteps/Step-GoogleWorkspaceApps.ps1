[CmdletBinding()]
param([ValidateSet('Chrome','Drive')][string[]]$Apps=@('Chrome','Drive'),
      [string]$ChromeMsiRelativePath='', [string]$DriveExeRelativePath='',
      [ValidateRange(30,1800)][int]$UpdateTimeoutSeconds=600)
. (Join-Path $PSScriptRoot 'Enterprise.Common.ps1')
. (Join-Path $PSScriptRoot 'Provisioning.Common.ps1')
function Assert-GoogleFile {
    param([string]$Path)
    $s=Get-AuthenticodeSignature -LiteralPath $Path
    if ($s.Status -ne 'Valid' -or -not $s.SignerCertificate -or $s.SignerCertificate.Subject -notmatch '(?:^|,\s*)O=Google (LLC|Inc\.?)(?=,|$)') { throw "A valid Google Authenticode signature is required: $Path" }
}
function Get-MachineGoogleFile {
    param([ValidateSet('Chrome','Drive','Updater')]$App)
    $paths=@()
    foreach ($root in @($env:ProgramFiles,[Environment]::GetEnvironmentVariable('ProgramFiles(x86)')) | Where-Object { $_ } | Select-Object -Unique) {
        if ($App -eq 'Chrome') { $file=Join-Path $root 'Google\Chrome\Application\chrome.exe'; if (Test-Path -LiteralPath $file -PathType Leaf) { $paths += $file }; continue }
        $sub=if ($App -eq 'Drive') { 'Google\Drive File Stream' } else { 'Google\GoogleUpdater' }
        $exe=if ($App -eq 'Drive') { 'GoogleDriveFS.exe' } else { 'updater.exe' }
        $folder=Join-Path $root $sub
        if (Test-Path -LiteralPath $folder) {
            foreach ($v in Get-ChildItem -LiteralPath $folder -Directory -ErrorAction Stop | Where-Object Name -match '^\d+(?:\.\d+){1,3}$') {
                $file=Join-Path $v.FullName $exe; if (Test-Path -LiteralPath $file -PathType Leaf) { $paths+=$file }
            }
        }
    }
    foreach ($path in $paths) {
        $vi=[Diagnostics.FileVersionInfo]::GetVersionInfo($path)
        [pscustomobject]@{ Path=$path; Version=[version]::new($vi.FileMajorPart,$vi.FileMinorPart,$vi.FileBuildPart,$vi.FilePrivatePart) }
    }
}
function Get-GoogleProduct {
    param($App)
    $names=if ($App -eq 'Chrome') { @('Google Chrome') } else { @('Google Drive','Google Drive for desktop','Google Drive File Stream') }
    if (-not @(Get-ProvisionArp | Where-Object { $_.Name -in $names -and $_.Publisher -match '^Google (LLC|Inc\.?)$' }).Count) { return }
    $f=Get-MachineGoogleFile $App | Sort-Object Version -Descending | Select-Object -First 1
    if ($f) { Assert-GoogleFile $f.Path; if ($f.Version -le [version]'0.0.0.0') { throw "Cannot read $App version." }; return $f }
}
function Confirm-GoogleUpdate {
    param([string]$App,[int]$Timeout)
    $ids=@{Chrome='{8A69D345-D564-463C-AFF1-A69D9E530F96}';Drive='{6BBAE539-2232-434A-A4E5-9A33560C6283}'}
    $id=$ids[$App]
    $registered=@('HKLM:\SOFTWARE\Google\Update\Clients','HKLM:\SOFTWARE\WOW6432Node\Google\Update\Clients') | Where-Object { Test-Path -LiteralPath (Join-Path $_ $id) }
    if (-not $registered) { throw "No machine Google Updater registration for $App ($id)." }
    $watch=[Diagnostics.Stopwatch]::StartNew()
    # Each bundle contains exactly one app. 16 = no update; 14 = install
    # completed and requires a new check; 17 = failure. A client launch is not proof.
    foreach ($pass in 1..2) {
        $server=$null; $bundle=$null; $webapp=$null; $sent=$false; $ended=$false
        try {
            $server=New-Object -ComObject GoogleUpdate.Update3WebMachine -ErrorAction Stop
            $bundle=$server.createAppBundleWeb()
            [void]$bundle.initialize()
            [void]$bundle.createInstalledApp($id)
            $webapp=$bundle.appWeb(0)
            [void]$bundle.checkForUpdate()
            while ($watch.Elapsed.TotalSeconds -lt $Timeout) {
                $snapshot=$webapp.currentState
                try {
                    $value=[int]$snapshot.stateValue
                    if ($value -eq 16) { Write-EnterpriseLog "${App}: Google Updater reports no further update offered."; return }
                    if ($value -eq 17) { throw "Google Updater returned error $($snapshot.errorCode) for $App." }
                    if ($value -eq 14) { $ended=$true; break }
                    if ($value -in @(4,11) -and -not $sent) {
                        if ($pass -eq 2) { throw "Google still offers an update for $App after installation." }
                        Write-EnterpriseLog "Google offers $App version $($snapshot.availableVersion); applying."
                        [void]$bundle.install(); $sent=$true
                    }
                } finally { if ($snapshot -and [Runtime.InteropServices.Marshal]::IsComObject($snapshot)) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($snapshot) } }
                Start-Sleep -Seconds 1
            }
            if (-not $ended) { try { [void]$bundle.cancel() } catch {}; throw "$App update verification timed out. Inspect Google Updater logs before retrying." }
        } finally {
            foreach ($obj in @($webapp,$bundle,$server)) { if ($null -ne $obj -and [Runtime.InteropServices.Marshal]::IsComObject($obj)) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($obj) } }
        }
    }
    throw "No final no-update response for $App; cannot mark it current."
}
if (-not $Apps.Count) { throw 'Select at least one Google app.' }
if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') { throw 'This Google installer recipe targets native x64 Windows.' }
$selected=@($Apps | Select-Object -Unique)
$before=@{}
$cache=Join-Path $env:SETUP_RUN_DIRECTORY ('Google-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($cache)
try {
    foreach ($app in $selected) {
        $found=Get-GoogleProduct $app
        if ($found) { $before[$app]=$found.Version; Write-EnterpriseLog "$app already installed: $($found.Version). Will check for updates."; continue }
        Set-EnterpriseProgress "Installing $app for this device."
        if ($app -eq 'Chrome') { $url='https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi'; $name='Chrome.msi'; $staged=$ChromeMsiRelativePath }
        else { $url='https://dl.google.com/drive-file-stream/GoogleDriveSetup.exe'; $name='GoogleDriveSetup.exe'; $staged=$DriveExeRelativePath }
        if ($staged) { $installer=Resolve-EnterpriseFile $staged }
        else {
            $installer=Join-Path $cache $name
            [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $installer -TimeoutSec 300 -ErrorAction Stop
        }
        Assert-GoogleFile $installer
        if ($app -eq 'Chrome') {
            $log=Join-Path $env:SETUP_RUN_DIRECTORY ($env:SETUP_STEP_ID+'-ChromeMSI.log')
            Invoke-SetupProcess (Join-Path $env:SystemRoot 'System32\msiexec.exe') ('/i "{0}" /qn /norestart /L*v "{1}"' -f $installer,$log) | Out-Null
        } else { Invoke-SetupProcess $installer '--silent --skip_launch_new' | Out-Null }
        $found=Get-GoogleProduct $app
        if (-not $found) { throw "$app did not verify in a machine installation directory." }
        $before[$app]=$found.Version; Write-EnterpriseLog "$app installed: $($found.Version)."
    }
    $verified=@()
    foreach ($app in $selected) {
        Set-EnterpriseProgress "Checking Google's update offer for $app."
        Confirm-GoogleUpdate $app $UpdateTimeoutSeconds
        $after=Get-GoogleProduct $app
        if (-not $after -or $after.Version -lt $before[$app]) { throw "$app is missing or its version regressed after the update check." }
        $id=if ($app -eq 'Chrome') { '{8A69D345-D564-463C-AFF1-A69D9E530F96}' } else { '{6BBAE539-2232-434A-A4E5-9A33560C6283}' }
        $registered=@(foreach ($base in @('HKLM:\SOFTWARE\Google\Update\Clients','HKLM:\SOFTWARE\WOW6432Node\Google\Update\Clients')) {
            $key=Join-Path $base $id
            if (Test-Path -LiteralPath $key) {
                $version=[version]'0.0'
                if ([version]::TryParse([string](Get-Item -LiteralPath $key).GetValue('pv'),[ref]$version)) { $version }
            }
        })
        if ($after.Version -notin $registered) { throw "$app binary $($after.Version) does not match its machine updater registration. Check for a pending app restart or stale installation." }
        $verified+="$app $($after.Version)"
        Set-EnterpriseProgress ("{0}: {1} -> {2}. Google update check completed." -f $app,$before[$app],$after.Version)
    }
    $global:SetupUiStepSummary=($verified -join '; ')+'; no newer version offered.'
} finally { if (Test-Path -LiteralPath $cache) { Remove-Item -LiteralPath $cache -Force -Recurse } }

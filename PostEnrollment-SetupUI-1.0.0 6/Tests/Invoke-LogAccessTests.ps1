#Requires -Version 5.1
#Requires -RunAsAdministrator
<# Windows NTFS tests using a temporary directory and a synthetic reader SID.
   No application installs, production log ACLs or registry changes. #>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Core/Setup.Common.ps1')
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('SetupLogAcl-' + [Guid]::NewGuid().ToString('N'))
$readerSid = 'S-1-5-21-100-200-300-1001'
function Assert-LogTest {
    param([bool]$Pass, [string]$Message)
    if (-not $Pass) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}
function Get-ReaderRules {
    param([string]$Path)
    (Get-Acl -LiteralPath $Path).GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]) |
        Where-Object { $_.IdentityReference.Value -eq $readerSid }
}
try {
    [void][IO.Directory]::CreateDirectory($testRoot)
    Set-SetupDirectorySecurity -Path $testRoot -ReaderSids @($readerSid)
    $runs = Join-Path $testRoot 'Runs'
    [void][IO.Directory]::CreateDirectory($runs)
    Set-SetupDirectorySecurity -Path $runs -ReaderSids @($readerSid)
    $completed = Join-Path $testRoot 'Completed-test.json'
    Set-Content -LiteralPath $completed -Value '{}' -Encoding UTF8
    $current = Join-Path $runs 'current'
    $old = Join-Path $runs 'older'
    [void][IO.Directory]::CreateDirectory($current)
    [void][IO.Directory]::CreateDirectory($old)
    $existingLog = Join-Path $old 'SetupUI.log'
    Set-Content -LiteralPath $existingLog -Value 'old run' -Encoding UTF8
    Set-SetupDirectorySecurity -Path $current -ReaderSids @($readerSid) -InheritReaderAccess
    $log = Join-Path $current 'SetupUI.log'
    Set-Content -LiteralPath $log -Value 'new run' -Encoding UTF8
    Assert-LogTest (@(Get-ReaderRules $completed).Count -eq 0) 'Completion state does not inherit the log reader'
    Assert-LogTest (@(Get-ReaderRules $existingLog).Count -eq 0) 'A new run grant does not expose older runs'
    $rules = @(Get-ReaderRules $log)
    Assert-LogTest ($rules.Count -eq 1 -and $rules[0].IsInherited) 'New logs inherit their run-folder reader grant'
    $writeMask = [Security.AccessControl.FileSystemRights]'Write,Delete,DeleteSubdirectoriesAndFiles,ChangePermissions,TakeOwnership'
    Assert-LogTest (($rules[0].FileSystemRights -band $writeMask) -eq 0) 'Log reader has no write/delete/permission-change rights'
    foreach ($path in @($testRoot,$runs)) {
        $parentRules = @(Get-ReaderRules $path)
        Assert-LogTest ($parentRules.Count -eq 1 -and $parentRules[0].InheritanceFlags -eq 'None') 'Parent navigation rights are folder-only'
    }
    foreach ($sid in @('S-1-5-18','S-1-5-32-544')) {
        $full = @((Get-Acl -LiteralPath $log).GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]) | Where-Object {
            $_.IdentityReference.Value -eq $sid -and ($_.FileSystemRights -band [Security.AccessControl.FileSystemRights]::FullControl) -eq [Security.AccessControl.FileSystemRights]::FullControl
        })
        Assert-LogTest ($full.Count -gt 0) 'SYSTEM/Administrators retain full control'
    }
    Add-SetupLogReaderAccess -Path $testRoot -ReaderSid $readerSid
    Add-SetupLogReaderAccess -Path $runs -ReaderSid $readerSid
    Add-SetupLogReaderAccess -Path $old -ReaderSid $readerSid -InheritReaderAccess
    Assert-LogTest (@(Get-ReaderRules $existingLog).Count -gt 0) 'Explicit repair makes an existing log readable'
    Assert-LogTest (@(Get-ReaderRules $completed).Count -eq 0) 'Existing-log repair still excludes completion state'
    $private = Join-Path $runs 'private'
    [void][IO.Directory]::CreateDirectory($private)
    Set-SetupDirectorySecurity -Path $private
    Assert-LogTest (@(Get-ReaderRules $private).Count -eq 0) 'No reader SIDs retains administrator-only run access'
    Write-Host 'Log access ACL tests passed. Verify opening logs from an unelevated user session separately.'
}
finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

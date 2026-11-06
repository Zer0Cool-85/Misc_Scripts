#Requires -Version 5.1
[CmdletBinding()]
param([string]$Version='')
$ErrorActionPreference='Stop'
$repository=Get-PSRepository -Name PSGallery -ErrorAction Stop
if ($repository.SourceLocation.TrimEnd('/') -ne 'https://www.powershellgallery.com/api/v2') { throw 'Expected the official PSGallery repository URL.' }
if (-not $Version) { $Version=(Find-Module Microsoft.WinGet.Client -Repository PSGallery -ErrorAction Stop).Version.ToString() }
$target=Join-Path (Split-Path $PSScriptRoot -Parent) 'Payloads/Modules'
[void][IO.Directory]::CreateDirectory($target)
Save-Module -Name Microsoft.WinGet.Client -RequiredVersion $Version -Repository PSGallery -Path $target -ErrorAction Stop
Write-Host "Staged Microsoft.WinGet.Client $Version and its dependencies in $target. Review before packaging. No module was installed on this workstation."

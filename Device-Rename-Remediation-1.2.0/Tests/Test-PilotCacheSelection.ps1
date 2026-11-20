#requires -Version 5.1
# Exercise the reset helper's discovery function with in-memory registry nodes.
$ErrorActionPreference = 'Stop'
class TestRegistryNode {
    [hashtable]$Children = @{}
    [string[]]$Values = @()
    [string[]]GetSubKeyNames() { return @($this.Children.Keys) }
    [string[]]GetValueNames() { return $this.Values }
    [TestRegistryNode]OpenSubKey([string]$name) { return $this.Children[$name] }
    [void]Dispose() {}
    [TestRegistryNode]Add([string]$name) {
        $child = [TestRegistryNode]::new()
        $this.Children[$name] = $child
        return $child
    }
}
$path = (Resolve-Path (Join-Path $PSScriptRoot '..\Tools\Reset-IntuneWin32AppTestState.ps1')).Path
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors -join [Environment]::NewLine) }
$func = $ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-AppCacheTargets'},$true)
$setup = $ast.Find({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$appPattern'},$true)
. ([scriptblock]::Create($func.Extent.Text))
$AppId = [guid]'680ab7ff-5e1c-4b65-92ad-0248b38dfdb4'
. ([scriptblock]::Create($setup.Extent.Text))
$device = [guid]::Empty.ToString()
$user = 'ab9d6cc6-e7b6-4f1c-afca-edb7ce60ec89'
$root = [TestRegistryNode]::new()
$ctx = $root.Add($device)
$null = $ctx.Add("$AppId")
$null = $ctx.Add("${AppId}_12")
$null = $ctx.Add("${AppId}_old")
$null = $ctx.Add("${AppId}0")
$grs = $ctx.Add('GRS')
$shared = $grs.Add('ab/c+=')
$shared.Values = @("$AppId",$user,'LastExecution')
$null = $shared.Add($user)
$null = $grs.Add('otherhash').Add("$AppId")
$null = $root.Add($user).Add("$AppId")
$null = $root.Add('Reporting').Add("$AppId")
$contextFilter = $null
$actual = @(Get-AppCacheTargets $root | ForEach-Object { "$($_.Kind)|$($_.Parent)|$($_.Name)" })
$expected = @("Key|$device|$AppId","Key|$device|${AppId}_12","Value|$device\GRS\ab/c+=|$AppId","Key|$device\GRS\otherhash|$AppId","Key|$user|$AppId")
if ($actual.Count -ne $expected.Count -or (Compare-Object $actual $expected)) { throw "Wrong reset targets: $actual" }
$contextFilter = $user
$single = @(Get-AppCacheTargets $root)
if ($single.Count -ne 1 -or $single[0].Parent -ne $user) { throw 'Context scoping failed.' }
$contextFilter = [guid]::NewGuid().ToString()
if (@(Get-AppCacheTargets $root).Count) { throw 'Unexpected targets in missing context.' }
Write-Output 'PASS: exact keys, exact shared-bucket values, multiple contexts, and empty selection.'

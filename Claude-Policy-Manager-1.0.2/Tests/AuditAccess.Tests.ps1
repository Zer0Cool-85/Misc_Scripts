#requires -Version 5.1
# Reproduce the reported enum conversion, compile the real interop source, and
# test the native-call boundary with a substituted RegOpenKeyEx implementation.
# Does NOT execute Windows native APIs or modify registry/audit policy.
$ErrorActionPreference='Stop'
$script:Count=0
function Assert($ok,$text) {if (-not $ok) {throw "FAIL: $text"};$script:Count++;Write-Output "PASS: $text"}
$bundle=Split-Path $PSScriptRoot -Parent
$source=Get-Content (Join-Path $bundle 'Source/PolicyEngine.psm1') -Raw
$failure=$null
try {$null=[Security.AccessControl.RegistryRights]0x01020000} catch {$failure=$_}
Assert ($null -ne $failure -and $failure.FullyQualifiedErrorId -match 'UndefinedIntegerToEnum') 'Reproduced the reported 16908288 enum conversion failure'
$match=[regex]::Match($source,"(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@")
if (-not $match.Success) {throw 'Native helper source not found'}
$native=$match.Groups[1].Value
Add-Type -TypeDefinition ($native.Replace('class ClaudePolicyNative','class ClaudeAuditCompileTest'))
Assert ($null -ne ('ClaudeAuditCompileTest' -as [type])) 'Corrected native helper compiles without invoking Windows APIs'
$stub=@'
 public static int FakeResult=2;
 public static uint CapturedAccess;
 public static long CapturedHive;
 public static string CapturedPath;
 static int RegOpenKeyEx(IntPtr hive,string path,uint options,uint access,out SafeRegistryHandle handle) {
   CapturedAccess=access; CapturedHive=hive.ToInt64(); CapturedPath=path;
   handle=null; return FakeResult;
 }
'@
$pattern='(?s)\[DllImport\("advapi32.dll", EntryPoint="RegOpenKeyExW".*?static extern int RegOpenKeyEx\([^;]+;'
$mock=[regex]::Replace($native,$pattern,$stub).Replace('class ClaudePolicyNative','class ClaudeAuditBoundaryTest')
if ($mock -match 'extern int RegOpenKeyEx') {throw 'Failed to substitute native boundary'}
Add-Type -TypeDefinition $mock
$path='SOFTWARE\Policies\Claude'
[ClaudeAuditBoundaryTest]::FakeResult=2
Assert ($null -eq [ClaudeAuditBoundaryTest]::OpenAuditRegistryKey($path)) 'Missing registry key is a normal null snapshot'
Assert ([ClaudeAuditBoundaryTest]::CapturedAccess -eq 0x01020100) 'Native call requests SACL/read-control access in the 64-bit view'
Assert ([ClaudeAuditBoundaryTest]::CapturedHive -eq -2147483646 -and [ClaudeAuditBoundaryTest]::CapturedPath -ceq $path) 'Native call targets HKLM and the exact Claude policy path'
[ClaudeAuditBoundaryTest]::FakeResult=3
Assert ($null -eq [ClaudeAuditBoundaryTest]::OpenAuditRegistryKey($path)) 'Missing parent path is a normal null snapshot'
foreach ($errorCode in @(5,1314)) {
    [ClaudeAuditBoundaryTest]::FakeResult=$errorCode
    $nativeFailure=$null
    try {$null=[ClaudeAuditBoundaryTest]::OpenAuditRegistryKey($path)} catch {
        $e=$_.Exception
        while ($null -ne $e) {
            if ($e -is [ComponentModel.Win32Exception]) {$nativeFailure=$e;break}
            $e=$e.InnerException
        }
    }
    Assert ($null -ne $nativeFailure -and $nativeFailure.NativeErrorCode -eq $errorCode) "Native error $errorCode is preserved rather than treated as a missing key"
}
Write-Output "SUCCESS: $script:Count audit-access regression checks. Actual Windows handle and SACL integration remains to be tested."

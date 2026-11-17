#Requires -Version 5.1
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
Adds eligible Okta group users to an Entra group when their UPNs match.
.DESCRIPTION
Version 1.0.0. Preview is the default; use -Apply to add members.

Each run reads the entire Okta source group and the Entra target group's direct
members, including pagination. It matches Okta profile.login (configurable) to
Entra userPrincipalName, ignoring case and trimming surrounding whitespace.
By default, only ACTIVE Okta users and enabled Entra users qualify.

This is an add-only reconciliation: no removals, account creation, changes to
Okta, or saved last-run timestamp. Users without an Entra match are reconsidered
on later runs. Existing eligible users are included on the FIRST run as well.
Nested Entra membership does not count as direct membership.

Connect to Microsoft Graph before running. The script verifies TenantId and
supports the Global Microsoft cloud. Required Graph permissions (admin consent):
  User.Read.All
  GroupMember.ReadWrite.All
For delegated access, the signed-in user must also have permission to manage
the group (for example, group owner or Groups Administrator).

Target: an assigned, cloud-managed security group or Microsoft 365 group.
Dynamic, on-premises-synced, role-assignable, hidden-membership, distribution,
and mail-enabled security groups are rejected by this implementation.

The Okta token must be able to read the source group and its users. SSWS tokens
inherit their creator's rights. Alternatively supply a short-lived Okta OAuth
token with -OktaAuthScheme Bearer and okta.groups.read scope plus the appropriate
admin role/resource assignment. OAuth token acquisition/refresh is external.

All discovery must succeed before ANY additions are attempted. Graph calls use
the Graph SDK's retry handling; Okta reads retry throttling and transient errors.
An add error is only treated as success if a fresh read confirms membership.
Failed additions cause a terminating error after the report has been written;
successful earlier additions are not rolled back. Rerunning retries missing users.

CSV reports and text logs are written even in preview/-WhatIf mode. They contain
user identifiers, so put OutputDirectory somewhere access-controlled. Secrets
are accepted as SecureString and are never intentionally written to these files.
Do not enable PowerShell debug tracing while handling credentials.
.PARAMETER OktaOrgUrl
Your Okta org origin, e.g. https://company.okta.com (not the -admin URL).
.PARAMETER OktaGroupId
Okta source group ID, usually starting with 00g.
.PARAMETER OktaToken
Okta API token as SecureString, from Read-Host -AsSecureString or a secret vault.
.PARAMETER TenantId
Expected Entra tenant GUID. Must match the current Get-MgContext session.
.PARAMETER EntraGroupId
Entra target group OBJECT ID (GUID).
.PARAMETER OktaMatchAttribute
Top-level Okta profile attribute to match to Entra UPN. Default: login.
Use email if profile.email, rather than profile.login, holds your Entra UPN.
.PARAMETER AllowedOktaStatuses
Eligible Okta statuses. Default: ACTIVE. This does not remove existing members.
.PARAMETER IncludeDisabledEntraUsers
Allow matched users whose Entra accountEnabled is false. Default: skip them.
.PARAMETER OktaAuthScheme
SSWS (default) for an API token; Bearer for an already acquired Okta OAuth token.
.PARAMETER Apply
Actually add missing members. Without this switch, only produce a preview.
.PARAMETER OutputDirectory
Directory for timestamped CSV/log files. Default: Logs next to this script.
.EXAMPLE
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Connect-MgGraph -TenantId 'YOUR-TENANT-GUID' -Scopes 'User.Read.All','GroupMember.ReadWrite.All' -ContextScope Process -NoWelcome
$oktaToken = Read-Host 'Okta API token' -AsSecureString
$sync = @{
    OktaOrgUrl   = 'https://company.okta.com'
    OktaGroupId  = '00gYOURGROUPID'
    OktaToken    = $oktaToken
    TenantId    = 'YOUR-TENANT-GUID'
    EntraGroupId = 'YOUR-ENTRA-GROUP-GUID'
}
.\Sync-OktaGroupToEntra.ps1 @sync
.\Sync-OktaGroupToEntra.ps1 @sync -Apply
.EXAMPLE
# Unattended: upload the public certificate to your Entra app registration and
# grant APPLICATION permissions User.Read.All and GroupMember.ReadWrite.All.
# The task identity must have access to the matching private key.
Connect-MgGraph -TenantId 'YOUR-TENANT-GUID' -ClientId 'YOUR-APP-GUID' -CertificateThumbprint 'YOUR-THUMBPRINT' -ContextScope Process -NoWelcome
# Obtain OktaToken from your organization's secret store, then invoke with -Apply.
# Schedule a wrapper that connects and runs this script in the SAME process.
# Use try/catch in the wrapper with exit 0 on success, exit 1 on exception.
# Configure the scheduler to avoid overlapping runs.
.EXAMPLE
.\Sync-OktaGroupToEntra.ps1 @sync -OktaMatchAttribute email -Apply -WhatIf
.NOTES
Designed for Windows PowerShell 5.1 and PowerShell 7 with Microsoft.Graph.Authentication.
This script does not schedule itself or disconnect a Graph session owned by you.
Group membership is not an atomic snapshot across two services; a concurrent
source/target change is observed on the next run. This script never revokes access.
.LINK
https://developer.okta.com/docs/api/openapi/okta-management/management/tags/group/other/listgroupusers
.LINK
https://learn.microsoft.com/graph/api/user-list?view=graph-rest-1.0
.LINK
https://learn.microsoft.com/graph/api/group-post-members?view=graph-rest-1.0
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)][uri]$OktaOrgUrl,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9]+$')][string]$OktaGroupId,
    [Parameter(Mandatory)][Security.SecureString]$OktaToken,
    [Parameter(Mandatory)][guid]$TenantId,
    [Parameter(Mandatory)][guid]$EntraGroupId,
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_]*$')][string]$OktaMatchAttribute = 'login',
    [ValidateNotNullOrEmpty()][string[]]$AllowedOktaStatuses = @('ACTIVE'),
    [switch]$IncludeDisabledEntraUsers,
    [ValidateSet('SSWS', 'Bearer')][string]$OktaAuthScheme = 'SSWS',
    [switch]$Apply,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'Logs')
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-Field {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) { return $Object[$Name] }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $null
}

function Write-SyncLog {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f [DateTime]::UtcNow.ToString('o'), $Level, ($Message -replace '[\r\n]+', ' ')
    [IO.File]::AppendAllText($script:LogPath, $line + [Environment]::NewLine, $script:Utf8)
    Write-Host $line
}

function Assert-ApiUri {
    param([string]$Uri, [uri]$Origin, [string]$PathPrefix)
    $candidate = [uri]$Uri
    if (-not $candidate.IsAbsoluteUri -or $candidate.Scheme -ne 'https' -or
        $candidate.Authority -ine $Origin.Authority -or $candidate.UserInfo -or
        $candidate.Fragment -or -not $candidate.AbsolutePath.StartsWith($PathPrefix, [StringComparison]::Ordinal)) {
        throw 'Refusing an unexpected API or pagination URL.'
    }
}

function Get-HeaderValue {
    param($Headers, [string]$Name)
    if ($null -eq $Headers) { return $null }
    if ($Headers -is [System.Net.WebHeaderCollection] -or $Headers -is [System.Collections.IDictionary]) {
        return (@($Headers[$Name]) -join ',')
    }
    # PowerShell 7 exceptions expose HttpResponseHeaders rather than a dictionary.
    $values = $null
    if ($Headers.TryGetValues($Name, [ref]$values)) { return (@($values) -join ',') }
    return $null
}

function Invoke-OktaGet {
    param([string]$Uri)
    Assert-ApiUri $Uri $OktaOrgUrl "/api/v1/groups/$OktaGroupId"
    for ($attempt = 0; $attempt -le 5; $attempt++) {
        try {
            return Invoke-WebRequest -Uri $Uri -Method Get -Headers $script:OktaHeaders `
                -UseBasicParsing -MaximumRedirection 0 -TimeoutSec 60 -ErrorAction Stop
        }
        catch {
            $response = Get-Field $_.Exception 'Response'
            $status = 0
            if ($null -ne $response) { $status = [int](Get-Field $response 'StatusCode') }
            if ($attempt -eq 5 -or $status -notin @(0, 408, 429, 500, 502, 503, 504)) {
                throw "Okta read failed (HTTP $status; 0 means a transport failure). Check the org URL, token rights, token network restrictions and connectivity."
            }
            $delay = [Math]::Min(60, [Math]::Pow(2, $attempt + 1))
            $headers = Get-Field $response 'Headers'
            $retryAfter = Get-HeaderValue $headers 'Retry-After'
            $seconds = 0
            $date = [DateTimeOffset]::MinValue
            if ([int]::TryParse($retryAfter, [ref]$seconds)) {
                $delay = [Math]::Max($delay, $seconds)
            }
            elseif ([DateTimeOffset]::TryParse($retryAfter, [ref]$date)) {
                $delay = [Math]::Max($delay, [Math]::Ceiling(($date - [DateTimeOffset]::UtcNow).TotalSeconds))
            }
            $resetText = Get-HeaderValue $headers 'X-Rate-Limit-Reset'
            $reset = [long]0
            if ($status -eq 429 -and [long]::TryParse($resetText, [ref]$reset)) {
                $epoch = [DateTimeOffset]::Parse('1970-01-01T00:00:00Z')
                $delay = [Math]::Max($delay, [Math]::Ceiling(($epoch.AddSeconds($reset) - [DateTimeOffset]::UtcNow).TotalSeconds) + 1)
            }
            if ($delay -gt 900) { throw 'Okta requested a retry delay over 15 minutes. Retry the run later.' }
            Write-SyncLog "Okta HTTP $status; retrying in $delay seconds (retry $($attempt + 1)/5)." 'WARN'
            Start-Sleep -Seconds ([int][Math]::Max(1, $delay))
        }
    }
}

function Get-OktaGroupUsers {
    $next = "$script:OktaBase/api/v1/groups/$OktaGroupId/users?limit=200"
    $seenPages = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    while ($next) {
        if (-not $seenPages.Add($next)) { throw 'Okta returned a repeated pagination URL.' }
        $response = Invoke-OktaGet $next
        $content = [string]$response.Content
        if (-not $content.TrimStart().StartsWith('[')) { throw 'Okta did not return a user array.' }
        # Assignment handles differences in JSON array enumeration between PS versions.
        $page = ConvertFrom-Json -InputObject $content
        foreach ($user in @($page)) {
            if ($null -ne $user) {
                if (-not (Get-Field $user 'id')) { throw 'Okta returned a user without an ID.' }
                $user
            }
        }
        $next = $null
        $link = Get-HeaderValue $response.Headers 'Link'
        foreach ($match in [regex]::Matches([string]$link, '<([^>]+)>\s*;\s*rel="([^"]+)"')) {
            if (($match.Groups[2].Value -split '\s+') -contains 'next') {
                $next = $match.Groups[1].Value
                break
            }
        }
    }
}

function Invoke-GraphApi {
    param([string]$Uri, [ValidateSet('GET', 'POST')][string]$Method = 'GET', [string]$Body)
    Assert-ApiUri $Uri ([uri]'https://graph.microsoft.com') '/v1.0/'
    $request = @{ Uri = $Uri; Method = $Method; OutputType = 'PSObject'; ErrorAction = 'Stop' }
    if ($Method -eq 'POST') { $request.Body = $Body; $request.ContentType = 'application/json' }
    Invoke-MgGraphRequest @request
}

function Get-GraphCollection {
    param([string]$Uri)
    $seenPages = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    while ($Uri) {
        if (-not $seenPages.Add($Uri)) { throw 'Microsoft Graph returned a repeated pagination URL.' }
        $page = Invoke-GraphApi $Uri
        # An unreadable/invalid collection must never be mistaken for an empty one.
        if ($null -eq $page -or $null -eq $page.PSObject.Properties['value']) {
            throw 'Microsoft Graph did not return a collection.'
        }
        foreach ($item in @(Get-Field $page 'value')) {
            if ($null -ne $item) {
                if (-not (Get-Field $item 'id')) { throw 'Microsoft Graph returned an item without an ID.' }
                $item
            }
        }
        $Uri = [string](Get-Field $page '@odata.nextLink')
    }
}

function New-ResultRow {
    param($OktaUser)
    [pscustomobject][ordered]@{
        RunId             = $script:RunId
        OktaUserId        = [string](Get-Field $OktaUser 'id')
        OktaStatus        = [string](Get-Field $OktaUser 'status')
        MatchAttribute    = $OktaMatchAttribute
        MatchValue        = ''
        EntraUserId       = ''
        EntraUPN          = ''
        EntraGroupId      = $EntraGroupId.ToString()
        Action            = 'Pending'
        Detail            = ''
    }
}

function Save-Report {
    if ($script:Rows.Count -gt 0) {
        $lines = @($script:Rows | ConvertTo-Csv -NoTypeInformation)
    }
    else {
        $lines = @((New-ResultRow $null | ConvertTo-Csv -NoTypeInformation)[0])
    }
    [IO.File]::WriteAllLines($script:ReportPath, [string[]]$lines, $script:Utf8)
}

if (-not $OktaOrgUrl.IsAbsoluteUri -or $OktaOrgUrl.Scheme -ne 'https' -or
    $OktaOrgUrl.AbsolutePath -ne '/' -or $OktaOrgUrl.Query -or
    $OktaOrgUrl.Fragment -or $OktaOrgUrl.UserInfo) {
    throw 'OktaOrgUrl must be an HTTPS org origin, for example https://company.okta.com.'
}
if ($OktaToken.Length -eq 0) { throw 'OktaToken is empty.' }
if ($TenantId -eq [guid]::Empty -or $EntraGroupId -eq [guid]::Empty) { throw 'Tenant and group IDs cannot be empty GUIDs.' }

$context = Get-MgContext
if ($null -eq $context) { throw 'Connect to Microsoft Graph first with Connect-MgGraph.' }
if ([string]$context.TenantId -ine $TenantId.ToString()) { throw 'The current Graph session belongs to a different tenant. Reconnect to the expected tenant.' }
if ([string]$context.Environment -ne 'Global') { throw 'This version supports the Global Microsoft cloud only.' }

$script:RunId = '{0}-{1}' -f [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$script:Utf8 = [Text.UTF8Encoding]::new($false)
$OutputDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
# Local report creation is intentional even with -WhatIf.
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$script:LogPath = Join-Path $OutputDirectory "Okta-Entra-$script:RunId.log"
$script:ReportPath = Join-Path $OutputDirectory "Okta-Entra-$script:RunId.csv"
$script:Rows = [Collections.Generic.List[object]]::new()
$script:OktaBase = $OktaOrgUrl.GetLeftPart([UriPartial]::Authority)
$script:OktaHeaders = @{}
$originalTls = [Net.ServicePointManager]::SecurityProtocol
$fatal = $null
$failedAdds = 0
$phase = 'Discovery'

try {
    [Net.ServicePointManager]::SecurityProtocol = $originalTls -bor [Net.SecurityProtocolType]::Tls12
    $tokenPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($OktaToken)
    try {
        $script:OktaHeaders = @{
            Authorization = '{0} {1}' -f $OktaAuthScheme, [Runtime.InteropServices.Marshal]::PtrToStringBSTR($tokenPointer)
            Accept = 'application/json'
        }
    }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($tokenPointer) }

    $mode = 'PREVIEW'
    if ($Apply -and -not $WhatIfPreference) { $mode = 'APPLY' }
    Write-SyncLog "Mode=$mode; tenant=$TenantId; source=$OktaGroupId; target=$EntraGroupId; match=profile.$OktaMatchAttribute -> UPN."
    # Confirm both group identities before reading memberships.
    $sourceResponse = Invoke-OktaGet "$script:OktaBase/api/v1/groups/$OktaGroupId"
    $sourceGroup = $sourceResponse.Content | ConvertFrom-Json
    if ([string](Get-Field $sourceGroup 'id') -cne $OktaGroupId) { throw 'Okta returned an unexpected source group.' }
    $targetUri = 'https://graph.microsoft.com/v1.0/groups/{0}?$select=id,displayName,groupTypes,securityEnabled,mailEnabled,onPremisesSyncEnabled,isAssignableToRole,visibility' -f $EntraGroupId
    $targetGroup = Invoke-GraphApi $targetUri
    if ([string](Get-Field $targetGroup 'id') -ine $EntraGroupId.ToString()) { throw 'Microsoft Graph returned an unexpected target group.' }
    foreach ($required in @('groupTypes', 'securityEnabled', 'mailEnabled', 'onPremisesSyncEnabled', 'isAssignableToRole', 'visibility')) {
        if ($null -eq $targetGroup.PSObject.Properties[$required]) { throw "Cannot validate target group: missing property $required." }
    }
    $types = @(Get-Field $targetGroup 'groupTypes')
    if ($types -contains 'DynamicMembership') { throw 'The target group uses dynamic membership; use an Assigned group.' }
    if ((Get-Field $targetGroup 'onPremisesSyncEnabled') -eq $true) { throw 'The target group is synchronized from on-premises.' }
    if ((Get-Field $targetGroup 'isAssignableToRole') -eq $true) { throw 'Role-assignable groups are intentionally unsupported by this script.' }
    if ((Get-Field $targetGroup 'visibility') -eq 'HiddenMembership') { throw 'Hidden-membership groups are unsupported by this script.' }
    $isM365 = $types -contains 'Unified'
    $isSecurity = ((Get-Field $targetGroup 'securityEnabled') -eq $true) -and ((Get-Field $targetGroup 'mailEnabled') -eq $false)
    if (-not ($isM365 -or $isSecurity)) { throw 'Use a security group without mail, or a Microsoft 365 group.' }
    $sourceName = [string](Get-Field (Get-Field $sourceGroup 'profile') 'name')
    Write-SyncLog "Source group: $sourceName; target group: $($targetGroup.displayName)."

    $oktaUsers = @(Get-OktaGroupUsers)
    $memberUri = 'https://graph.microsoft.com/v1.0/groups/{0}/members?$select=id&$top=999' -f $EntraGroupId
    $memberIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($member in @(Get-GraphCollection $memberUri)) { [void]$memberIds.Add([string]$member.id) }
    Write-SyncLog "Read $($oktaUsers.Count) Okta users and $($memberIds.Count) direct Entra members."

    $lookupCache = @{}
    $plannedIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($oktaUser in $oktaUsers) {
        $row = New-ResultRow $oktaUser
        $script:Rows.Add($row)
        $value = Get-Field (Get-Field $oktaUser 'profile') $OktaMatchAttribute
        if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value)) {
            $row.Action = 'SkippedMissingMatch'; $row.Detail = 'Selected Okta profile field is absent, empty or not a string.'; continue
        }
        $upn = $value.Trim()
        $row.MatchValue = $upn
        if ($row.OktaStatus -notin $AllowedOktaStatuses) {
            $row.Action = 'SkippedOktaStatus'; $row.Detail = "Status is not in: $($AllowedOktaStatuses -join ', ')."; continue
        }
        if ($upn -notmatch '^[^\s@]+@[^\s@]+$') {
            $row.Action = 'SkippedInvalidUPN'; $row.Detail = 'Match value is not in user@domain form.'; continue
        }

        if (-not $lookupCache.ContainsKey($upn)) {
            # Escape apostrophes in the OData literal, then URL-encode the whole filter.
            $filter = "userPrincipalName eq '$($upn.Replace("'", "''"))'"
            $userUri = 'https://graph.microsoft.com/v1.0/users?$filter={0}&$select=id,userPrincipalName,accountEnabled' -f [uri]::EscapeDataString($filter)
            $lookupCache[$upn] = @(Get-GraphCollection $userUri)
        }
        $matchedUsers = @($lookupCache[$upn])
        if ($matchedUsers.Count -eq 0) {
            $row.Action = 'NoEntraMatch'; $row.Detail = 'No exact Entra UPN match; reconsidered on the next run.'; continue
        }
        if ($matchedUsers.Count -ne 1) { throw "Ambiguous Entra lookup for $upn; no additions have been attempted." }
        $entraUser = $matchedUsers[0]
        $row.EntraUserId = [string](Get-Field $entraUser 'id')
        $row.EntraUPN = [string](Get-Field $entraUser 'userPrincipalName')
        if (-not [string]::Equals($row.EntraUPN, $upn, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Graph returned a nonmatching UPN for $upn; no additions have been attempted."
        }
        $enabled = Get-Field $entraUser 'accountEnabled'
        if ($enabled -isnot [bool]) { throw "Cannot read accountEnabled for $upn; check User.Read.All permission." }
        if (-not $enabled -and -not $IncludeDisabledEntraUsers) {
            $row.Action = 'SkippedEntraDisabled'; $row.Detail = 'Entra account is disabled.'; continue
        }
        if ($memberIds.Contains($row.EntraUserId)) {
            $row.Action = 'AlreadyMember'; $row.Detail = 'Already a direct member.'; continue
        }
        if (-not $plannedIds.Add($row.EntraUserId)) {
            $row.Action = 'DuplicateSourceMatch'; $row.Detail = 'Another eligible Okta row already planned this Entra user.'; continue
        }
        $row.Action = 'WouldAdd'; $row.Detail = 'Eligible and missing from the direct membership snapshot.'
    }

    $candidates = @($script:Rows | Where-Object Action -eq 'WouldAdd')
    # Check report write access and persist the complete plan before changing membership.
    Save-Report
    Write-SyncLog "Discovery complete. $($candidates.Count) new direct member(s) eligible."
    $phase = 'Apply'
    foreach ($row in $candidates) {
        if (-not $Apply) { continue }
        if (-not $PSCmdlet.ShouldProcess("$($row.EntraUPN) -> $($targetGroup.displayName) [$EntraGroupId]", 'Add direct Entra group member')) {
            if (-not $WhatIfPreference) { $row.Action = 'NotApproved'; $row.Detail = 'ShouldProcess declined the addition.' }
            continue
        }
        try {
            $body = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$($row.EntraUserId)" } | ConvertTo-Json -Compress
            $addUri = 'https://graph.microsoft.com/v1.0/groups/{0}/members/$ref' -f $EntraGroupId
            $null = Invoke-GraphApi -Uri $addUri -Method POST -Body $body
            $row.Action = 'Added'; $row.Detail = 'Graph accepted the membership addition.'
            [void]$memberIds.Add($row.EntraUserId)
        }
        catch {
            $addError = $_.Exception.Message
            # Covers another writer adding the user, or a lost success response.
            # Do not assume every HTTP 400 means "already a member".
            $confirmed = $false
            try {
                $checkUri = 'https://graph.microsoft.com/v1.0/groups/{0}/members/{1}?$select=id' -f $EntraGroupId, $row.EntraUserId
                $current = Invoke-GraphApi $checkUri
                $confirmed = [string](Get-Field $current 'id') -ieq $row.EntraUserId
            }
            catch { $confirmed = $false }
            if ($confirmed) {
                $row.Action = 'AlreadyMemberAfterRetry'; $row.Detail = 'A fresh read confirmed direct membership after the add error.'
                [void]$memberIds.Add($row.EntraUserId)
            }
            else {
                $row.Action = 'Failed'; $row.Detail = $addError; $failedAdds++
            }
        }
        # Persist each attempted result, so a later interruption leaves useful evidence.
        Save-Report
        Write-SyncLog "$($row.Action): $($row.EntraUPN)"
    }
}
catch {
    $fatal = $_
    foreach ($row in $script:Rows) {
        if ($row.Action -in @('Pending', 'WouldAdd')) {
            $row.Action = 'NotAttempted'
            $row.Detail = "Run stopped during $phase; see log."
        }
    }
    Write-SyncLog $_.Exception.Message 'ERROR'
}
finally {
    $script:OktaHeaders.Clear()
    [Net.ServicePointManager]::SecurityProtocol = $originalTls
    Save-Report
}

foreach ($group in @($script:Rows | Group-Object Action | Sort-Object Name)) {
    Write-SyncLog "$($group.Name): $($group.Count)"
}
Write-SyncLog "CSV: $script:ReportPath"
if ($null -ne $fatal) { throw $fatal }
if ($failedAdds -gt 0) { throw "$failedAdds membership addition(s) failed. Review $script:ReportPath and rerun after correcting the issue." }
$script:Rows

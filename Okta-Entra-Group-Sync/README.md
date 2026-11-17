# Okta to Entra group sync and Excel reporting

**Version 1.1.0 · November 17, 2026**

`Sync-OktaGroupToEntra.ps1` compares one Okta source group with one Microsoft Entra target group. It can preview eligible additions, apply those additions, or create an Excel membership report without changing either group.

The Excel command is named **`Export-Excel`**, and it belongs to the **`ImportExcel`** PowerShell module. Microsoft Excel does not need to be installed on the machine running the script.

## Files

| File | Purpose |
| --- | --- |
| `Sync-OktaGroupToEntra.ps1` | The complete script, including preview, apply, and Excel report modes. |
| `README.md` | Setup, examples, report definitions, scheduling, and troubleshooting. |

No token, tenant configuration, certificate, or third-party module is included in the package.

## 1. Choose a mode

| Invocation | API behavior | Files created |
| --- | --- | --- |
| No mode switch | Reads both groups, resolves eligible users, and previews additions. | CSV and log |
| `-Apply` | Performs discovery, then adds eligible missing users to the target group. | CSV and log |
| `-Apply -WhatIf` | Reads and previews; PowerShell suppresses membership changes. | CSV and log |
| `-ReportOnly` | Reads both groups and compares all source users, including inactive accounts. | Excel workbook and log |

`-ReportOnly` and `-Apply` cannot be combined. The parameter sets reject that combination before API calls, and the internal Graph request function also blocks write methods in report mode. `-ReportOnly -WhatIf` still creates the local report; `-WhatIf` is not a request to suppress local output files.

The script is **add-only**. It does not remove members, create accounts, change Okta, or synchronize nested groups. Entra-only users are reported for review, not removed.

## 2. Requirements

- Windows PowerShell 5.1 or PowerShell 7. PowerShell 7 is recommended for new automation.
- `Microsoft.Graph.Authentication` in the PowerShell environment used to run the script.
- `ImportExcel` for `-ReportOnly`; preview and apply do not need it.
- HTTPS access to your Okta org, Microsoft Graph, and the Microsoft identity endpoints needed for authentication.
- An Okta token authorized to read the source group and its users.
- A Graph connection to the correct Entra tenant.
- Write access to the output directory.

Install the modules once under the account that will run the script:

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Install-Module ImportExcel -Scope CurrentUser

Get-Module -ListAvailable Microsoft.Graph.Authentication, ImportExcel |
    Select-Object Name, Version, Path
```

For a scheduled task, modules installed only for your personal account may not be available to the task identity. Install them for that identity or use an elevated `-Scope AllUsers` installation. Module installations and upgrades are separate from the scheduled job; the script never installs dependencies automatically.

### Entra group requirements

Preview and apply support an **Assigned**, cloud-managed, non-role-assignable security group without mail, or an Assigned Microsoft 365 group.

| Target group | Preview/apply | Excel report |
| --- | --- | --- |
| Supported Assigned security or Microsoft 365 group | Supported | Supported |
| Dynamic membership group | Rejected | Readable membership can be reported; no eligible write candidates are proposed. |
| Group synchronized from on-premises | Rejected | Can be reported if the identity can read it. |
| Role-assignable group | Rejected by this implementation | Can be reported if the identity has the required read access. |
| Mail-enabled security or distribution group | Rejected | Can be reported if Graph exposes its membership and the identity can read it. |
| Hidden-membership group | Rejected | Rejected by this implementation, even if additional permissions exist. |

This version uses the **Global Microsoft cloud** (`graph.microsoft.com`). It rejects a Graph connection to a different cloud or tenant.

## 3. Permissions and authentication

### Microsoft Graph

| Purpose | Graph permissions |
| --- | --- |
| Excel reporting or preview | `User.Read.All` and `GroupMember.Read.All` |
| Apply additions | `User.Read.All` and `GroupMember.ReadWrite.All` |

Use **delegated permissions** for interactive sign-in and **application permissions** for unattended certificate authentication. Obtain tenant administrator consent. For delegated writes, the signed-in user must also be allowed to manage the target group, for example through group ownership or an appropriate Entra role.

`User.Read.All` is used for exact UPN matching and account-state reads. Group membership permissions provide the group reads and, when granted, membership updates. Existing broader permissions may also work, but are not needed for this implementation.

Application permissions can authorize access beyond the one target group. The configured group ID limits this script's operations; it does not narrow the application's permission grant itself.

### Okta

The default is an **SSWS API token**. Create it using an administrator/service account authorized to read the selected group and user profiles. An SSWS token inherits the issuing account's privileges. Check any token network-zone restrictions against the host that will run the job.

Enter the token without displaying it:

```powershell
$oktaToken = Read-Host 'Okta API token' -AsSecureString
```

Alternatively, pass an already acquired Okta OAuth access token as a SecureString and use `-OktaAuthScheme Bearer`. The OAuth application needs `okta.groups.read` and the appropriate admin-role/resource assignment. This script does not acquire or refresh Okta OAuth tokens; your calling process must supply a valid token for each run.

The script accepts a SecureString but must convert it in memory to build the HTTPS authorization header. It does not intentionally log the token. Avoid embedding tokens in source files, command-line arguments, or debugging traces.

## 4. Gather your configuration

| Setting | Where it comes from |
| --- | --- |
| `OktaOrgUrl` | The org origin, such as `https://company.okta.com`. Use the org URL, not an `-admin` hostname or a group page URL. |
| `OktaGroupId` | The actual Okta group ID, commonly beginning with `00g`, obtainable from the group's admin-console URL or API response. |
| `TenantId` | Your Entra Directory/tenant ID, as a GUID. |
| `EntraGroupId` | The target group's **Object ID**, as a GUID. This is not a display name, application ID, or group email address. |
| `OktaMatchAttribute` | `login` by default. Use `email` or another top-level profile field if it contains your Entra UPN. |
| `OutputDirectory` | A location the run identity can write to; it will contain user identifiers. |

Each run logs the resolved source and target group names to help you verify the IDs.

## 5. Quick start: create an Excel report

Extract both files into a working directory and open PowerShell there. Replace every placeholder below.

```powershell
$tenantId = 'YOUR-ENTRA-TENANT-GUID'

Connect-MgGraph -TenantId $tenantId `
    -Scopes 'User.Read.All', 'GroupMember.Read.All' `
    -ContextScope Process -NoWelcome

$settings = @{
    OktaOrgUrl        = 'https://yourcompany.okta.com'
    OktaGroupId       = '00gYOURGROUPID'
    OktaToken         = (Read-Host 'Okta API token' -AsSecureString)
    TenantId          = $tenantId
    EntraGroupId      = 'YOUR-ENTRA-GROUP-OBJECT-GUID'
    OktaMatchAttribute = 'login'
    OutputDirectory  = 'C:\Reports\Okta-Entra'
}

$report = .\Sync-OktaGroupToEntra.ps1 @settings -ReportOnly
$report | Format-List

# Optional: open the completed workbook using your default spreadsheet app.
Invoke-Item -LiteralPath $report.WorkbookPath
```

Report mode returns one object with `WorkbookPath`, `LogPath`, `OktaUsers`, `EntraUsers`, `WouldAdd`, and `EntraOnly`. The workbook path is also printed in the log.

To match Okta email instead:

```powershell
$settings.OktaMatchAttribute = 'email'
.\Sync-OktaGroupToEntra.ps1 @settings -ReportOnly
```

## 6. Preview and apply the sync

The settings hashtable contains common settings only. Select the mode when invoking the script.

Preview using the connection above:

```powershell
$preview = .\Sync-OktaGroupToEntra.ps1 @settings
$preview | Where-Object Action -eq 'WouldAdd' |
    Format-Table MatchValue, EntraUPN, Action
```

When you are ready to apply, reconnect with the write permission:

```powershell
Disconnect-MgGraph
Connect-MgGraph -TenantId $tenantId `
    -Scopes 'User.Read.All', 'GroupMember.ReadWrite.All' `
    -ContextScope Process -NoWelcome

# Optional PowerShell WhatIf check with the write-capable connection.
.\Sync-OktaGroupToEntra.ps1 @settings -Apply -WhatIf

# Add eligible missing direct members.
$results = .\Sync-OktaGroupToEntra.ps1 @settings -Apply
```

The apply run performs fresh discovery; it does not execute a saved CSV or workbook. Changes between preview and apply may therefore change the candidate list. Editing an Excel report never changes group membership.

To get a workbook showing membership after a successful apply, run `-ReportOnly` again. Recent cloud changes may take time to become visible.

## 7. How matching and eligibility work

### Matching rule

The script takes the selected **top-level** Okta profile field, trims whitespace around it, and looks for an exact, case-insensitive match to Entra `userPrincipalName`.

For example, Okta ` Dale.Lute@company.com ` matches Entra `dale.lute@company.com`.

It does not fall back to Entra mail, proxy addresses, display names, employee IDs, or partial usernames. It does not rewrite domains. A custom profile attribute is supported if its name is letters/numbers/underscores beginning with a letter; nested property paths are not supported. Guest accounts often have `#EXT#` UPNs that differ from their email address, so an external email will not automatically match a guest UPN.

### Default addition criteria

1. The selected Okta profile value is a nonempty string.
2. The Okta status is `ACTIVE`.
3. The value has a `user@domain` form.
4. Exactly one existing Entra user has that UPN.
5. The Entra account is enabled.
6. The user is not already a **direct** member of the target group.
7. Another source row has not already proposed that Entra user.
8. The target group is supported for direct membership updates.

Duplicate Okta profile values can map to the same Entra user. Only one eligible row proposes the missing user. Do not treat `DuplicateSourceRows` as a full identity-quality audit: it counts rows suppressed as duplicate addition candidates, not every repeated profile value in the source.

### Optional eligibility changes

```powershell
# Example only: explicitly include another Okta status.
.\Sync-OktaGroupToEntra.ps1 @settings -ReportOnly `
    -AllowedOktaStatuses ACTIVE, PASSWORD_EXPIRED

# Explicitly include disabled Entra accounts in the eligibility assessment.
.\Sync-OktaGroupToEntra.ps1 @settings -ReportOnly `
    -IncludeDisabledEntraUsers
```

The same parameters affect preview and apply. Report inventories always include all returned users; these options change the `Action` assessment and the `WouldAdd` tab, not which source users are inventoried.

### What each run reads and writes

The script validates the tenant, retrieves both group identities, and reads all membership pages. Okta pagination follows the `Link` header; Entra pagination follows `@odata.nextLink`. Pagination is restricted to the expected HTTPS API origin.

During normal sync discovery, users with excluded Okta statuses are skipped before Entra lookup. In Excel report mode, every valid source identifier is looked up, including identifiers for excluded statuses. This allows the report to distinguish an inactive member present in both groups from a member actually absent from the target group.

Lookups are cached per UPN within a run. Report mode also reads Entra-only user profiles by ID so the target inventory includes their UPNs and account state. This is not a tenant-wide user export.

For apply, all discovery must finish successfully before any membership POST. A complete plan is saved before the first write, and results are saved after each attempted addition.

### Repeated runs and newly created accounts

This is full reconciliation on each invocation, not an event subscriber or a timestamp-based delta process.

- The first apply run includes existing eligible source users, not just users added since installation.
- A source user with no Entra match is reconsidered on the next run.
- Users already in the target group are skipped.
- A target member removed manually will be re-added on a later apply run if that person still qualifies in the source.
- Removing someone from Okta, changing their status, or disabling their Entra account does not remove existing target membership.
- Membership reads across two services are not an atomic snapshot. Concurrent changes may appear on the next run.

## 8. Excel workbook reference

Every successful report contains these eight tabs, even when some contain only headers:

| Tab | Contents |
| --- | --- |
| `Summary` | Run times in UTC, group names/IDs, matching settings, target restrictions, counts, and scope limitations. |
| `OktaMembers` | All returned Okta members: IDs, login, email, name, status, and selected match value. |
| `EntraMembers` | All returned direct user members, including users not linked to the source group. Includes account state and linked Okta IDs/statuses. |
| `Comparison` | One row per returned Okta member, with matching result, target membership, and sync assessment. |
| `WouldAdd` | Unique eligible missing Entra users for a supported target. No changes are made by report mode. |
| `EntraOnly` | Direct Entra user members with no UPN-linked user in the selected Okta source group. |
| `NoEntraMatch` | Okta rows with valid identifiers but no exact existing Entra UPN match, including excluded Okta statuses. |
| `OtherEntraObjects` | Returned direct non-user members such as nested groups or devices. They are not expanded or synced. |

Data tabs with records use filterable Excel tables and frozen headers. Empty tabs retain their headers without a fake account row. IDs and text are preserved as text, and profile strings beginning with `=` are not saved as executable Excel formulas.

### `Comparison` versus `Action`

These columns answer different questions. **Comparison** describes the membership relationship; **Action** describes what the sync would do under the configured criteria.

`InEntraGroup` is populated only after an Entra user has been resolved. A blank value means membership could not be assessed for that row; it is not a confirmed absence.

| Comparison | Meaning |
| --- | --- |
| `InBothGroups` | The source row resolved to a user who is already a direct target member. |
| `MissingFromEntraGroup` | The source row resolved to an Entra user who is not a direct target member. Eligibility may still exclude this user. |
| `NoEntraAccount` | No exact UPN match exists in the tenant query result. The user might have a different UPN. |
| `MissingMatchValue` | The selected Okta field is missing, empty, or not a string. |
| `InvalidMatchValue` | The value is not in `user@domain` form. |
| `EntraGroupOnly` | Used in target inventory tabs for users without a matched source-group row. It does not assert absence from the entire Okta org. |
| `NotEvaluated` | Normal CSV preview/apply skipped Entra lookup because the Okta status was excluded. Excel report mode evaluates valid identifiers for these users. |

For example, an Okta `SUSPENDED` user who is already in the Entra group appears as `Comparison = InBothGroups` and `Action = SkippedOktaStatus`. A disabled Entra user already in both groups appears as `InBothGroups` and `SkippedEntraDisabled` by default.

### Action values

| Action | Meaning |
| --- | --- |
| `WouldAdd` | Eligible missing direct member; preview/report only. |
| `Added` | Graph accepted the addition during apply. |
| `AlreadyMember` | Eligible matched user was already a direct member at discovery. |
| `AlreadyMemberAfterRetry` | An add returned an error, but a fresh direct-membership read confirmed the user is present. This can reflect a concurrent writer or a lost response. |
| `NoEntraMatch` | Eligible source identifier had no exact Entra UPN match. |
| `SkippedMissingMatch` | Source match field missing/empty/not a string. |
| `SkippedInvalidUPN` | Source match field not in `user@domain` form. |
| `SkippedOktaStatus` | Source status excluded by `AllowedOktaStatuses`. |
| `SkippedEntraDisabled` | Entra account disabled and the opt-in switch was not supplied. |
| `DuplicateSourceMatch` | Another eligible source row already planned this missing Entra user. |
| `TargetUnsupported` | Report found an otherwise eligible missing user, but this target cannot be synced by the script. |
| `NotApproved` | An apply operation was declined through PowerShell confirmation. |
| `Failed` | Apply failed and membership could not be confirmed. |
| `NotAttempted` | A run stopped before a pending addition was attempted. |

In CSV apply output, `InEntraGroup` and `Comparison` represent the discovery snapshot; `Action` records the subsequent write result. Generate a new Excel report to obtain another membership snapshot.

Counts explicitly labeled **rows** can include duplicate source identities. `EligibleUniqueAdditions`, `EntraDirectUsers`, and `EntraGroupOnlyUsers` refer to unique Entra users. The two group totals are not expected to be equal when duplicate Okta matches or non-user Entra members exist.

### Reporting scope limitations

The report compares direct **user** membership. It does not evaluate effective access through nested groups, application assignments, licensing, or downstream resource permissions. Microsoft documents a Graph v1.0 issue where service-principal group members can be omitted; `OtherEntraObjects` and total returned-object counts must not be used as a complete service-principal audit.

If a required read fails, the run throws and does not publish a completed XLSX. Workbook generation uses a temporary `.partial.xlsx` file and moves it to its final name only after all sheets have been saved. A process forcibly terminated while writing can leave a temporary file; the `.partial.xlsx` suffix identifies it as incomplete.

## 9. Parameter reference

| Parameter | Default | Notes |
| --- | --- | --- |
| `OktaOrgUrl` | Required | HTTPS org origin only. |
| `OktaGroupId` | Required | Okta source group ID. |
| `OktaToken` | Required | SecureString SSWS token or OAuth access token. |
| `TenantId` | Required | Expected Entra tenant GUID. |
| `EntraGroupId` | Required | Target group Object ID GUID. |
| `OktaMatchAttribute` | `login` | Top-level Okta profile field matched to Entra UPN. |
| `AllowedOktaStatuses` | `ACTIVE` | One or more eligible statuses, compared without case sensitivity. |
| `IncludeDisabledEntraUsers` | Off | Includes disabled Entra users in eligibility. |
| `OktaAuthScheme` | `SSWS` | Either `SSWS` or `Bearer`. |
| `Apply` | Off | Enables membership additions, subject to ShouldProcess/WhatIf. |
| `ReportOnly` | Off | Creates Excel report; mutually exclusive with Apply. |
| `OutputDirectory` | `Logs` next to script | Created if needed; timestamped files prevent normal runs from overwriting each other. |

Built-in help is also available:

```powershell
Get-Help .\Sync-OktaGroupToEntra.ps1 -Full
```

## 10. Unattended certificate authentication

Use application authentication for a scheduled job. An interactive Graph session in your desktop PowerShell process will not carry over to a new scheduled process.

### Register the app

1. Create a single-tenant app registration for this automation in Microsoft Entra.
2. Record its **Application/client ID** and **Directory/tenant ID**.
3. Add Microsoft Graph **Application** permissions from the permissions table above: read-only for reports/previews, or membership write for apply.
4. Grant administrator consent.
5. Create or obtain a certificate according to your organization's certificate policy, and upload its **public certificate** to the app registration's certificate credentials.
6. Keep the matching private key available to the scheduled task identity on the execution host. Plan certificate rotation before expiry.

For a Windows test setup, the following creates a certificate under the current user's Personal store and exports only the public portion. Run it as the identity that will execute the task:

```powershell
$certificateParameters = @{
    Subject           = 'CN=Okta-Entra-GroupSync'
    CertStoreLocation = 'Cert:\CurrentUser\My'
    KeyAlgorithm      = 'RSA'
    KeyLength         = 2048
    HashAlgorithm     = 'SHA256'
    KeySpec           = 'Signature'
    KeyExportPolicy   = 'NonExportable'
    NotAfter          = (Get-Date).AddYears(1)
}
$certificate = New-SelfSignedCertificate @certificateParameters
Export-Certificate -Cert $certificate -FilePath '.\Okta-Entra-GroupSync.cer'
$certificate.Thumbprint
```

Upload the `.cer` to the app registration. Test the connection as the task identity:

```powershell
Connect-MgGraph -TenantId 'YOUR-TENANT-GUID' `
    -ClientId 'YOUR-APP-CLIENT-GUID' `
    -CertificateThumbprint 'YOUR-CERTIFICATE-THUMBPRINT' `
    -ContextScope Process -NoWelcome

Get-MgContext | Select-Object TenantId, ClientId, AuthType, Environment
```

For a certificate in `Cert:\LocalMachine\My`, retrieve that certificate explicitly and pass `-Certificate $certificate` instead of relying on thumbprint-store discovery. The task identity must have read access to its private key.

### Store the Okta token for the job

An organization-approved secret vault is preferred. It must return a SecureString without requiring an interactive prompt during the job.

For a Windows-only local option, PowerShell can serialize the SecureString using Windows DPAPI. Create the file on the same machine, under the same Windows account that will run the task:

```powershell
# Create this directory with permissions limited to the task identity and admins.
$secretDirectory = 'C:\ProgramData\Okta-Entra-Sync\Secrets'
New-Item -ItemType Directory -Path $secretDirectory -Force | Out-Null

Read-Host 'Okta API token' -AsSecureString |
    Export-Clixml -LiteralPath (Join-Path $secretDirectory 'OktaToken.xml')
```

Directory creation alone does not restrict its ACL. Apply your organization's appropriate directory permissions. The DPAPI file cannot simply be copied to another account or machine and expected to decrypt. **This encryption guidance is Windows-only**; Export-Clixml does not provide equivalent credential encryption on macOS/Linux. Do not use that local-file approach there.

### Example scheduled wrapper

Save this example as `Run-GroupJob.ps1` alongside the main script after replacing its placeholders. The wrapper is an example to create locally; it is not an additional file in this package.

```powershell
[CmdletBinding()]
param(
    [ValidateSet('Report', 'Preview', 'Apply')]
    [string]$Mode = 'Report'
)

$ErrorActionPreference = 'Stop'
$jobExitCode = 0
$connected = $false

try {
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    $tenantId = 'YOUR-TENANT-GUID'

    Connect-MgGraph -TenantId $tenantId `
        -ClientId 'YOUR-APP-CLIENT-GUID' `
        -CertificateThumbprint 'YOUR-CERTIFICATE-THUMBPRINT' `
        -ContextScope Process -NoWelcome -ErrorAction Stop
    $connected = $true

    $token = Import-Clixml -LiteralPath `
        'C:\ProgramData\Okta-Entra-Sync\Secrets\OktaToken.xml'

    $settings = @{
        OktaOrgUrl       = 'https://company.okta.com'
        OktaGroupId      = '00gYOURGROUPID'
        OktaToken        = $token
        TenantId         = $tenantId
        EntraGroupId     = 'YOUR-GROUP-OBJECT-GUID'
        OktaMatchAttribute = 'login'
        OutputDirectory = 'C:\ProgramData\Okta-Entra-Sync\Reports'
    }

    $scriptPath = Join-Path $PSScriptRoot 'Sync-OktaGroupToEntra.ps1'
    switch ($Mode) {
        'Report'  { & $scriptPath @settings -ReportOnly | Out-Null }
        'Preview' { & $scriptPath @settings | Out-Null }
        'Apply'   { & $scriptPath @settings -Apply -Confirm:$false | Out-Null }
    }
}
catch {
    Write-Error -Message $_.Exception.Message -ErrorAction Continue
    $jobExitCode = 1
}
finally {
    if ($connected) {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    }
}

exit $jobExitCode
```

Example Task Scheduler settings for PowerShell 7:

| Setting | Example |
| --- | --- |
| Program/script | `C:\Program Files\PowerShell\7\pwsh.exe` |
| Arguments | `-NoLogo -NoProfile -NonInteractive -File "C:\Scripts\Okta-Entra\Run-GroupJob.ps1" -Mode Report` |
| Start in | `C:\Scripts\Okta-Entra` |
| Account | The account with module access, certificate private-key access, token access, and report-directory write access. |
| Trigger | Choose the interval needed for your deployment, such as every 30 minutes. |
| Existing instance | Do not start a new instance while the preceding run is still running. |

Test the wrapper manually as the task identity before scheduling. Use an execution policy and script-signing approach appropriate for your organization. Change `-Mode Report` to `-Mode Apply` only after supplying a write-authorized app and validating the preview. Scheduler exit code `0` means completion; `1` means the wrapper caught a failure. Authentication or module errors that occur before the main script starts will be in the host/job output rather than the main script's log.

## 11. Logging, retries, and failures

Output names use UTC timestamps and a short unique run identifier:

```text
Okta-Entra-YYYYMMDDTHHMMSSZ-xxxxxxxx.log
Okta-Entra-YYYYMMDDTHHMMSSZ-xxxxxxxx.csv
Okta-Entra-YYYYMMDDTHHMMSSZ-xxxxxxxx.xlsx
```

Preview/apply create CSV plus log. ReportOnly creates XLSX plus log. Protect the output directory because files contain user names, UPNs, IDs, group names, and account states. This version does not automatically delete old reports; set a retention policy outside the script.

Okta reads retry transport failures and HTTP 408, 429, 500, 502, 503, and 504, up to five retries after the first attempt. The delay uses exponential backoff and respects Retry-After or rate-limit reset information. A requested delay over 15 minutes stops the run. Graph requests use the Graph SDK's retry behavior.

A discovery failure stops apply before any writes. If an individual addition fails, the script checks direct membership again; it only treats the outcome as success if that read confirms membership. Other candidates are still attempted. Failed additions produce a terminating error after saving results, and successful additions are not rolled back. Rerunning is safe in the sense that current direct members are skipped, while missing candidates are reconsidered.

## 12. Troubleshooting

| Symptom | Check |
| --- | --- |
| Microsoft.Graph.Authentication not found | Install it for the current PowerShell host and run identity. |
| ReportOnly requires ImportExcel | Run `Install-Module ImportExcel -Scope CurrentUser` under the execution identity. `Export-Excel` is a command, not the module name. |
| Graph tenant mismatch | Disconnect and reconnect using the configured tenant GUID. |
| Okta HTTP 401/403 | Token validity, issuing account privileges, org URL, and token network restrictions. |
| Okta HTTP 0 | DNS, TLS, proxy/firewall, transport timeout, and correct org hostname. |
| Graph 403 during reads | Consent, permission type (delegated/application), current token, group visibility/access, and User.Read.All. Reconnect after updating consent. |
| Graph 403 during apply | GroupMember.ReadWrite.All, delegated user's authority, and target group manageability. |
| NoEntraMatch | Compare the selected Okta profile field to the actual Entra UPN. Check domains, guest UPNs, account provisioning, and replication delays. |
| All source users skipped by status | Confirm actual Okta statuses; default eligibility is ACTIVE only. |
| Disabled users are missing from WouldAdd | Default behavior; they remain visible in report inventory/comparison. |
| EntraOnly contains expected users | Check the selected source group and mapping field. EntraOnly is not an organization-wide Okta search result. |
| TargetUnsupported | Review Summary target restrictions. The report can inspect some group types that this script cannot modify. |
| Certificate not found/private key unavailable | Certificate store, task identity, thumbprint, private-key permissions, and expiry. |
| Cannot decrypt OktaToken.xml | Use the same Windows account and host that created the DPAPI file, or recreate it under the execution identity. |
| No workbook after failure | Read the log. A completed workbook is intentionally not published when required reads/export fail. |
| Excel file cannot be written | Directory permissions, disk space, antivirus/file locks, and execution identity. |
| Only some members visible | The script follows every returned page, but compares direct users only. Review nested groups, hidden membership, Graph visibility/replication, and the service-principal API limitation. |

## 13. Validation and version history

Version 1.1.0 adds report-only Excel output and this README while keeping the original default preview and explicit apply behavior. The CSV now also includes `EntraAccountEnabled`, `InEntraGroup`, and `Comparison` columns.

The script was syntax-checked and passed 32 scenarios in PowerShell 7.4 with mocked Okta/Graph responses. Excel integration was tested with the actual ImportExcel 7.8.10 module, including empty groups, inactive/disabled membership matches, duplicate candidates, Entra-only members, nested objects, invalid mode combinations, failure handling, and formula-like profile text. The existing sync regression cases were retained.

No live tenant credentials were used. Windows PowerShell 5.1 compatibility is intended but was not executed in this Linux test environment. Certificate/private-key access and Windows DPAPI behavior should be tested under your actual scheduled task identity.

## References

- [Okta: list group users](https://developer.okta.com/docs/api/openapi/okta-management/management/tags/group/other/listgroupusers)
- [Okta: API token authentication and permissions](https://developer.okta.com/docs/guides/create-an-api-token/main/)
- [Microsoft Graph: list users](https://learn.microsoft.com/en-us/graph/api/user-list?view=graph-rest-1.0)
- [Microsoft Graph: list direct group members and API limitations](https://learn.microsoft.com/en-us/graph/api/group-list-members?view=graph-rest-1.0)
- [Microsoft Graph: add group members and permissions](https://learn.microsoft.com/en-us/graph/api/group-post-members?view=graph-rest-1.0)
- [Microsoft Graph: throttling and SDK retries](https://learn.microsoft.com/en-us/graph/throttling)
- [Microsoft Graph PowerShell: app-only certificate authentication](https://learn.microsoft.com/en-us/powershell/microsoftgraph/app-only?view=graph-powershell-1.0)
- [PowerShell: Export-Clixml credential encryption](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/export-clixml)
- [PowerShell: New-SelfSignedCertificate](https://learn.microsoft.com/en-us/powershell/module/pki/new-selfsignedcertificate)
- [ImportExcel project](https://github.com/dfinke/ImportExcel)
- [Export-Excel command documentation](https://github.com/dfinke/ImportExcel/blob/master/mdHelp/en/export-excel.md)

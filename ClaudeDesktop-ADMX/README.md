# Claude Desktop for Windows – ADMX/ADML Policy Template for Intune

This package contains an Administrative Template (ADMX/ADML) that exposes the
documented Claude Desktop enterprise policy keys so you can manage them from
**Microsoft Intune → Imported Administrative Templates** (or classic Group Policy).

```
ClaudeDesktop-ADMX/
├── ClaudeDesktop.admx          # Policy definitions (namespace: Anthropic.Policies.ClaudeDesktop)
├── en-US/
│   └── ClaudeDesktop.adml      # English display strings & explain text
└── README.md
```

The template is **self-contained** – it does not reference `Windows.admx`, so you
do not need to upload any Microsoft base templates before importing it.

---

## Policy reference

All policies are **Computer (Device) policies** and write to:

```
HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Claude
```

| Intune / GPO setting | Category | Registry value | Type | Enabled → | Disabled → | App default |
|---|---|---|---|---|---|---|
| Restrict sign-in to specific organization(s) | Sign-in | `forceLoginOrgUUID` | REG_SZ | UUID or JSON array | removed | not set |
| Disable automatic updates | Updates | `disableAutoUpdates` | REG_DWORD | `1` | `0` | `0` (updates on) |
| Update enforcement window (hours) | Updates | `autoUpdaterEnforcementHours` | REG_DWORD | 1–72 | removed | 72 |
| Allow Claude Code in Claude Desktop | Claude Code | `isClaudeCodeForDesktopEnabled` | REG_DWORD | `1` | `0` | allowed |
| Default effort level for Claude Code sessions | Claude Code | `effortLevel` | REG_SZ | `low`/`medium`/`high`/`xhigh`/`max` | removed | not set |
| Allow Cowork in Claude Desktop | Cowork | `secureVmFeaturesEnabled` | REG_DWORD | `1` | `0` | allowed |
| Restrict folders that can be mounted in Cowork | Cowork | `allowedWorkspaceFolders` | REG_SZ (JSON) | JSON array of paths | removed | unrestricted |
| Cowork EDR sensor integration (beta) | Cowork | `coworkEDRIntegrationVendor` + `coworkEDRIntegration` | REG_SZ ×2 | vendor ID + package path | removed | not set |
| Allow desktop extensions | Extensions and MCP | `isDesktopExtensionEnabled` | REG_DWORD | `1` | `0` | allowed |
| Allow the extension directory | Extensions and MCP | `isDesktopExtensionDirectoryEnabled` | REG_DWORD | `1` | `0` | allowed |
| Allow local MCP servers | Extensions and MCP | `isLocalDevMcpEnabled` | REG_DWORD | `1` | `0` | allowed |

**Not configured** in Intune/GPO = the value is not written (or is removed), and Claude Desktop uses its built-in default.

### Value format notes

- **forceLoginOrgUUID** – a single UUID (`11111111-2222-3333-4444-555555555555`) also
  pre-selects that org at sign-in. A JSON array (`["uuid-1","uuid-2"]`) accepts any listed org
  without pre-selecting one. It is stored as **REG_SZ** – Anthropic explicitly says not to use
  REG_MULTI_SZ. The app reads it at launch, so users must quit and reopen Claude.
- **allowedWorkspaceFolders** – JSON text, so backslashes must be doubled:
  `["C:\\Users\\Public\\Projects","D:\\Shared\\Claude"]`
- **Extension allowlist** – machine policy overrides the in-app allowlist. If you want to use the
  allowlist in the Claude admin console, do **not** set *Allow desktop extensions* or
  *Allow the extension directory* to **Disabled**.
- **effortLevel** – requires Claude Desktop **1.25927.0** or later and does not affect Cowork sessions.
- **HKLM vs HKCU** – this template targets HKLM only (Anthropic's recommendation). If machine
  policy exists under `HKLM\SOFTWARE\Policies\Claude`, the app ignores
  `HKCU\SOFTWARE\Policies\Claude` entirely – the two hives are not merged. Avoid mixing them.

---

## Import into Intune

1. Sign in to the **Microsoft Intune admin center** (https://intune.microsoft.com).
2. Go to **Devices → Manage devices → Configuration → Import ADMX** tab → **Import**.
3. Upload:
   - **ADMX file:** `ClaudeDesktop.admx`
   - **ADML file:** `en-US/ClaudeDesktop.adml`
4. Click **Next → Create**. Wait for **Status = Available** (refresh after a minute or two).
   If it shows an error, select the entry to see the parsing message.

### Create the configuration profile

1. **Devices → Manage devices → Configuration → Create → New policy**.
2. **Platform:** Windows 10 and later
   **Profile type:** Templates → **Imported Administrative templates (Preview)**.
3. Name it, e.g. `Claude Desktop – Enterprise Policy`.
4. In **Configuration settings**, browse to
   **Computer Configuration → Anthropic → Claude Desktop** and configure the settings you need.
5. Assign to a **device** group (these are machine policies), then **Create**.

### Updating the template later

Intune will not let you re-import a template with the same namespace while profiles use it.
To ship a new version: bump `revision` in both files, delete the profiles that reference
the old import (or migrate them), delete the old import, then re-import.

---

## Group Policy (on-prem / hybrid)

Copy the files to the Central Store:

```
\\<domain>\SYSVOL\<domain>\Policies\PolicyDefinitions\ClaudeDesktop.admx
\\<domain>\SYSVOL\<domain>\Policies\PolicyDefinitions\en-US\ClaudeDesktop.adml
```

Settings appear under **Computer Configuration → Policies → Administrative Templates → Anthropic → Claude Desktop**.

---

## Verify on an endpoint

Force a sync (**Settings → Accounts → Access work or school → Info → Sync**), then:

```powershell
Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Claude' |
    Select-Object * -ExcludeProperty PS*
```

In Claude Desktop, **Help → Troubleshooting → Generate Diagnostic Report** shows which policy
values the app actually read. Quit and relaunch Claude after policy changes.

### Example equivalent .reg (for testing only)

```reg
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Claude]
"forceLoginOrgUUID"="[\"11111111-2222-3333-4444-555555555555\"]"
"disableAutoUpdates"=dword:00000001
"isClaudeCodeForDesktopEnabled"=dword:00000001
"secureVmFeaturesEnabled"=dword:00000001
"isDesktopExtensionEnabled"=dword:00000001
"isDesktopExtensionDirectoryEnabled"=dword:00000001
"isLocalDevMcpEnabled"=dword:00000000
"effortLevel"="high"
```

---

## Scope & caveats

- Keys and semantics are taken from Anthropic's **Enterprise configuration for Claude Desktop**
  article (support.claude.com/en/articles/12622667) as of November 2026. Anthropic adds keys
  over time – check the article before relying on a setting that isn't listed here.
- Anthropic doesn't state the Windows value types for `allowedWorkspaceFolders`, `effortLevel`
  and the EDR keys; this template writes them as REG_SZ, matching how other string/JSON keys
  are documented. Validate in a pilot ring first.
- Claude Desktop for **third-party inference** (Bedrock / Vertex / Foundry, `bootstrapUrl`, etc.)
  uses a separate key set. The in-app *Configure Third-Party Inference → Export* menu can
  generate its own ADMX for that scenario – it is not covered here.
- On Enterprise plans several of these controls can also be set in **Organization settings**
  on claude.ai without MDM. Pick one place to manage each setting to avoid confusion.
- Unofficial community template – not published or supported by Anthropic.

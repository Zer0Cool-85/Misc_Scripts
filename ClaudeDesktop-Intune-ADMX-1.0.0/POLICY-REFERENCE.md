# Policy reference

Package 1.0.0; documentation reviewed November 13, 2026.

All 12 settings target `HKLM\Software\Policies\Claude` in the machine policy scope. The template intentionally does not create HKCU variants. Anthropic gives HKLM precedence over matching HKCU settings. Values are written with the exact case shown below.

## Exact mappings

| Category | Profile setting | Registry value | Type | Enabled | Disabled |
|---|---|---|---|---|---|
| Sign-in | Restrict sign-in to approved organizations | `forceLoginOrgUUID` | REG_SZ | Entered UUID or JSON array | Delete this value |
| Updates | Disable automatic updates | `disableAutoUpdates` | REG_DWORD | `1` | `0` |
| Updates | Set update restart enforcement hours | `autoUpdaterEnforcementHours` | REG_DWORD | Integer, 1–72 | Delete this value |
| Features and extensions | Allow desktop extensions | `isDesktopExtensionEnabled` | REG_DWORD | `1` | `0` |
| Features and extensions | Allow extension directory access | `isDesktopExtensionDirectoryEnabled` | REG_DWORD | `1` | `0` |
| Features and extensions | Allow local MCP servers | `isLocalDevMcpEnabled` | REG_DWORD | `1` | `0` |
| Features and extensions | Allow Claude Code in Desktop | `isClaudeCodeForDesktopEnabled` | REG_DWORD | `1` | `0` |
| Features and extensions | Allow Cowork in Desktop | `secureVmFeaturesEnabled` | REG_DWORD | `1` | `0` |
| Features and extensions | Set Claude Code session effort level | `effortLevel` | REG_SZ | `low`, `medium`, `high`, `xhigh`, or `max` | Delete this value |
| Workspace folders | Set allowed Cowork workspace folders | `allowedWorkspaceFolders` | REG_SZ | JSON array of path strings | Delete this value |
| Cowork EDR (beta) | Set Cowork EDR sensor package path (beta) | `coworkEDRIntegration` | REG_SZ | Entered local package path | Delete this value |
| Cowork EDR (beta) | Set Cowork EDR vendor ID (beta) | `coworkEDRIntegrationVendor` | REG_SZ | Entered lowercase vendor ID | Delete this value |

Not configured supplies no setting from this profile. Boolean settings use literal DWORD 1/0; they do not use string values such as `true` or `false`. Text controls are REG_SZ, with environment expansion disabled. No setting is forced merely by importing this template.

## Input examples

These are format examples, not values to deploy unchanged.

**One organization:** enter your Claude organization UUID as plain text, without quotes:

```text
11111111-1111-4111-8111-111111111111
```

**Multiple organizations:** enter one JSON array in the same textbox:

```json
["11111111-1111-4111-8111-111111111111","22222222-2222-4222-8222-222222222222"]
```

Use actual Claude organization UUIDs. An Entra tenant ID, Okta organization URL, or email domain is not a substitute. The entire array remains one string, not a multi-string registry value. Restart the app after changing it.

**Cowork folders:** enter JSON with escaped Windows backslashes:

```json
["C:\\CompanyData\\Claude","D:\\ApprovedWork"]
```

Do not surround the whole array with another pair of quotes. The textbox cannot validate JSON or check whether paths exist. Use concrete paths in the pilot; wildcard and environment-variable expansion are not promised here. Anthropic's table describes this as a JSON string array; this template serializes that array into one REG_SZ. Empty-list semantics and per-folder read-only object formats are not asserted by this template. Use the Cowork enable/disable policy when the intention is to disable Cowork.

**EDR package path:** this is an ordinary string, so backslashes are not doubled:

```text
C:\ProgramData\Company\CoworkEDR\vendor-signed-package
```

Replace the example with the full path and file name of the integration package supplied by your supported EDR vendor. Deploy that package separately. Obtain the exact lowercase vendor ID from its integration instructions; the template does not guess it from the display name.

## Operational notes

- **Policy ownership:** Machine policies can override organization controls, even with a less restrictive value. Leaving a setting Not configured may be appropriate when the organization's settings should govern it.
- **Extensions and MCP:** To block both user-added MCP servers and local servers supplied by extensions, disable both relevant Allow policies. If you instead use an organization extension allowlist, keep extensions and directory access available.
- **Updates:** Decide whether Intune or Claude owns version deployment. The interval applies to the app restart for a prepared update, not a Windows reboot. Keep an update process in place if automatic updates are disabled.
- **Effort:** The documented minimum is Desktop 1.25927.0. The selected value is applied at the start of each Claude Code session and does not apply to Cowork. Supported-on text is not a runtime version check.
- **EDR:** Beta; requires the Windows MSIX build 4.4212.0 or later plus Cowork prerequisites. The supported sensor runs inside the local Cowork VM. These values do not install the ordinary host EDR agent, configure its tenant, or cover cloud Cowork sessions. Removing them does not remove an existing VM sensor.
- **Scope:** This package configures the Windows Desktop application. It does not create a Claude Code CLI managed-settings file, configure a browser extension, manage SSO, or impose Windows file/network access controls.
- **Validation:** Numeric bounds and dropdown choices are represented in ADMX. Text inputs require administrator validation of meaning, JSON, paths, and vendor IDs. Maximum text lengths are template input bounds, not claimed Claude product limits.

The mappings above come from [Anthropic's enterprise policy table](https://support.claude.com/en/articles/12622667-enterprise-configuration-for-claude-desktop). EDR requirements and removal behavior are described in [the EDR integration guide](https://support.claude.com/en/articles/17828685-run-your-endpoint-detection-and-response-edr-sensor-in-claude-cowork-on-claude-desktop). State/deletion behavior is defined by this custom template.

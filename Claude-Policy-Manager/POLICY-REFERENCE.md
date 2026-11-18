# JSON policy reference

Use `Source\PolicyConfig.json` for deployment. `Examples\All-Settings.example.json` demonstrates all 12 settings together. It is a type example, not a recommended baseline: replace the organization/vendor/package placeholders or set those entries to null.

All names are case sensitive in the configuration validator. Boolean settings accept JSON `true`/`false` or integer `1`/`0`. Do not quote booleans or numbers. The engine converts them to native REG_DWORD values. Other managed values use REG_SZ.

## Each policy

| JSON key | Example JSON value | Meaning and use |
|---|---|---|
| `disableAutoUpdates` | `false` | `false`/`0` allows automatic updates; `true`/`1` disables them. If disabled, supply an update process through your deployment tooling. |
| `autoUpdaterEnforcementHours` | `72` | Integer 1–72 for the app's forced restart to apply a prepared update. This is not a Windows reboot timer or update polling interval. |
| `isDesktopExtensionEnabled` | `false` | Disable desktop extensions with false; allow them with true. Keep this available if using an organization extension allowlist. |
| `isDesktopExtensionDirectoryEnabled` | `false` | Controls directory access separately from extension execution. An extension allowlist needs directory access available. |
| `isLocalDevMcpEnabled` | `false` | Controls user-configured local MCP servers. Blocking this alone does not block local servers supplied by desktop extensions. |
| `isClaudeCodeForDesktopEnabled` | `true` | Controls the Code feature inside Desktop. It does not configure a separately installed Claude Code CLI. |
| `secureVmFeaturesEnabled` | `false` | Controls Cowork in Desktop. Setting true does not install virtualization prerequisites. |
| `forceLoginOrgUUID` | `"11111111-1111-4111-8111-111111111111"` | Require a specified Claude organization. Replace the example with your real Claude organization UUID. Multiple organizations can be provided as a native JSON array. |
| `allowedWorkspaceFolders` | `["C:\\CompanyData\\Claude"]` | Nonempty JSON array of concrete Windows folder paths for Cowork mounts. The engine serializes it to one REG_SZ JSON array. It does not create folders or enforce Windows filesystem permissions. |
| `effortLevel` | `"high"` | One of `low`, `medium`, `high`, `xhigh`, `max`, in lowercase. Applied at the start of Desktop Code sessions; does not apply to Cowork. The documented minimum is Desktop 1.25927.0. |
| `coworkEDRIntegration` | `"C:\\ProgramData\\Company\\CoworkEDR\\vendor-signed-package"` | Full local path to the vendor-signed Cowork EDR integration package. Stage the correct package separately; do not substitute an arbitrary host-agent installer. |
| `coworkEDRIntegrationVendor` | `"your-vendor-id"` | Exact lowercase vendor identifier from your vendor's Cowork integration instructions. Use with the package-path setting. |

The two EDR settings are beta controls. Anthropic currently specifies the Windows MSIX build 4.4212.0 or later and Cowork prerequisites. The integration covers the local Cowork VM; removal of these values does not uninstall an existing VM sensor. Verify the vendor's actual ID and package requirements.

## Organization and path examples

Single organization:

```json
"forceLoginOrgUUID": "11111111-1111-4111-8111-111111111111"
```

Multiple organizations:

```json
"forceLoginOrgUUID": [
  "11111111-1111-4111-8111-111111111111",
  "22222222-2222-4222-8222-222222222222"
]
```

These are illustrative UUIDs. Use the actual Claude organization IDs, not Entra tenant IDs, Okta URLs, or email domains. The engine retains the single-string format for one plain UUID; an array remains JSON text in one REG_SZ. It never writes REG_MULTI_SZ for organization lists.

Folders, including a UNC example:

```json
"allowedWorkspaceFolders": [
  "C:\\CompanyData\\Claude",
  "\\\\fileserver\\ApprovedShare\\Claude"
]
```

JSON requires escaped backslashes. The engine decodes paths and serializes folder arrays correctly. This package intentionally rejects empty arrays, relative paths, wildcards, environment-variable expressions, and parent-directory traversal. It does not assert unsupported empty-list behavior; use `secureVmFeaturesEnabled: false` to disable Cowork.

## Null, removals, and config updates

`null` means **no new instruction**, not false and not deletion. On a new device the setting is unmanaged. On an existing manager, its last enforced instruction is retained, including an instruction to keep the value absent.

To delete an existing managed value and keep it deleted:

```json
"Policies": {
  "effortLevel": null
},
"RemovePolicies": ["effortLevel"]
```

To change it again, remove `effortLevel` from `RemovePolicies` and set the desired string in `Policies`. To disable a boolean feature, use `false`; removing its value may let the application's default or organization setting enable it again.

An update preserves original snapshots from the first time this manager owned a value. Omitting a policy from config 2 therefore neither erases its backup nor stops its enforcement. The default uninstall restores that original state if the value still matches the last enforced instruction.

## Application behavior

Anthropic documents these controls for Team/Enterprise administration. HKLM takes precedence over HKCU, and device policy can override matching organization controls. Applying any Desktop policy currently moves release-channel management to Stable, according to the reviewed guide. A package cannot grant a feature entitlement or make an unsupported app version recognize a setting.

Quit and reopen Claude Desktop when testing a change. For organization restrictions, inspect **Help → Troubleshooting → Generate Diagnostic Report** to confirm the value the app read.

Sources: [Enterprise policy table](https://support.claude.com/en/articles/12622667-enterprise-configuration-for-claude-desktop) and [Cowork EDR integration](https://support.claude.com/en/articles/17828685-run-your-endpoint-detection-and-response-edr-sensor-in-claude-cowork-on-claude-desktop).

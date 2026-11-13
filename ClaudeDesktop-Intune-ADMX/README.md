# Claude Desktop: additions to your supplied Intune template

Updated November 13, 2026. Use the two files in this folder together:

- `claude_admx.admx`
- `claude_adml.adml`

This is an extension of the pair you supplied. The original seven policies, strings, presentations, categories, XML namespaces, policy namespace, revisions, and formatting have been preserved. Five new policies, their help strings, and matching text boxes were appended under the existing **Features** category. There are now 12 policies.

| Added policy | Registry value | Input |
|---|---|---|
| Restrict Login to Organization(s) | `forceLoginOrgUUID` | One Claude organization UUID or a JSON array of UUIDs |
| Allowed Cowork Workspace Folders | `allowedWorkspaceFolders` | JSON array of folder paths |
| Claude Code Session Effort Level | `effortLevel` | `low`, `medium`, `high`, `xhigh`, or `max` |
| Cowork EDR Sensor Package Path (Beta) | `coworkEDRIntegration` | Full local path to the vendor-signed integration package |
| Cowork EDR Vendor ID (Beta) | `coworkEDRIntegrationVendor` | Exact supported vendor ID in lowercase |

All five additions use a required text box and write one REG_SZ value under `HKLM\SOFTWARE\Policies\Claude`. The text boxes do not validate JSON, UUIDs, paths, or allowed effort/vendor values. No defaults are prefilled for the new policies. The 32,767-character maximum is a template input limit, not a claimed Claude product limit.

## Import and configure

1. In Intune, open **Devices → Manage devices → Configuration → Import ADMX → Import**.
2. Select the ADMX and ADML files above. Wait for the import to become **Available**.
3. Create a **Windows 10 and later → Templates → Imported Administrative templates (Preview)** profile.
4. Browse **Claude Desktop → Features** for the additions. Enable the desired policy and enter its value. Assign to a test device first.

**For the existing numeric switches, enable the policy and enter 0 or 1.** The policy's outer Disabled state is not a substitute for entering numeric 0. For example, to block Cowork, enable **Enable Cowork (Secure VM Features)** and enter `0`. The original Auto Updates field has inverse wording: `0` permits automatic updates; `1` disables them.

After syncing the test device, fully quit and reopen Claude Desktop. Check the registry and confirm the intended application behavior:

```powershell
reg.exe query "HKLM\SOFTWARE\Policies\Claude" /reg:64
```

For a folder list, enter JSON such as `["C:\\CompanyData\\Claude","D:\\ApprovedWork"]`. A package path uses ordinary single backslashes, such as `C:\ProgramData\Company\VendorPackage`. Replace examples with your actual values. See the individual policy help text for version requirements and usage notes.

## If you already imported the original pair

The policy namespace intentionally remains `Anthropic.Policies.Claude`. These files are a replacement, not a second template to import alongside that pair. Intune rejects duplicate imported settings/namespaces. Preserve existing profile settings before following Microsoft's replacement process: remove profiles that use the old import, remove that import, import this pair, then recreate and assign the profile. Check the pilot before restoring broad assignments.

## Validation and sources

The update was checked for preservation of the original definitions, XML structure, unique IDs, resolved strings/presentations, input mappings, and all 12 registry names. No live Intune import or Windows application test was performed. The specific cause of the earlier template's import failure has not been established.

- [Anthropic enterprise configuration](https://support.claude.com/en/articles/12622667-enterprise-configuration-for-claude-desktop)
- [Anthropic Cowork EDR integration](https://support.claude.com/en/articles/17828685-run-your-endpoint-detection-and-response-edr-sensor-in-claude-cowork-on-claude-desktop)
- [Microsoft: importing and replacing custom ADMX templates](https://learn.microsoft.com/en-us/intune/device-configuration/settings-catalog/import-custom-admx-templates)

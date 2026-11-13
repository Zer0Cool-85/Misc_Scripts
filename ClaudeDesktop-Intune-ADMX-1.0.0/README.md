# Claude Desktop for Windows: Intune administrative templates

**Package:** 1.0.0 | **Documentation reviewed:** November 13, 2026

This custom ADMX/ADML pair exposes the 12 Windows policy values in Anthropic's enterprise configuration table. It is not an official Anthropic template. It writes machine policies to `HKEY_LOCAL_MACHINE\Software\Policies\Claude`.

The package has been checked against Microsoft's published XML schema and checked for references, registry mappings, input types, and policy-state behavior. **It has not been imported into a live Intune tenant or tested against a running Windows Claude Desktop installation.** Complete the pilot below before a broader assignment.

## Included files

| File | Use |
|---|---|
| `ClaudeDesktop.admx` | Policy definitions to import |
| `en-US/ClaudeDesktop.adml` | Matching English labels, help, and controls to import |
| `POLICY-REFERENCE.md` | Exact registry mapping and setting notes |
| `VALIDATION.txt` | Checks performed and remaining deployment checks |
| `SHA256SUMS.txt` | SHA-256 hashes of the package contents |

The ADMX has no external namespace dependencies. You do not need to import `Windows.admx` or another parent template. Importing these files creates available settings; it does not apply a baseline or install Claude.

## Import into Intune

1. Extract this ZIP. Keep the ADMX and ADML from the same package version.
2. Open **Intune admin center → Devices → Manage devices → Configuration → Import ADMX → Import**. The equivalent Windows configuration page can also expose this tab.
3. Select `ClaudeDesktop.admx` for the ADMX file and `en-US/ClaudeDesktop.adml` for the language file. Verify that the language is English (United States).
4. Complete the import and refresh until the status is **Available**. Microsoft currently labels imported administrative templates as **Preview**. An account with the appropriate device-configuration permissions is required.
5. Go to **Devices → Manage devices → Configuration → Create → New policy**.
6. Select **Windows 10 and later**, then **Templates → Imported Administrative templates (Preview)**. Name the profile, for example, `Windows - Claude Desktop - Pilot`.
7. Under computer settings, browse **Claude Desktop (Custom)**. The categories are Sign-in, Updates, Features and extensions, Workspace folders, and Cowork EDR (beta).
8. Configure only the settings you intend to manage. Assign the profile to a small device test group, then create it.

These are computer settings even when Intune offers assignment to user groups. Device groups make the intended machine-wide scope clearer. Use a single management owner for each registry value; do not also write the same value from a script, another profile, or Group Policy.

## Understand the switches

| Template setting type | Enabled | Disabled | Not configured |
|---|---|---|---|
| Settings beginning **Allow** | Writes DWORD `1` | Writes DWORD `0` | No value specified by this profile |
| **Disable automatic updates** | Writes DWORD `1`: automatic updates disabled | Writes DWORD `0`: automatic updates permitted | No value specified by this profile |
| Text, dropdown, or numeric setting | Writes the supplied value | Explicitly deletes that one named registry value | No value specified by this profile |

For example, **Disabled** on *Set update restart enforcement hours* removes that value; it does not disable updates. **Disabled** on *Restrict sign-in to approved organizations* removes that machine restriction.

Not configured does not mean a feature is disabled, nor does it guarantee that another management source has not set the value. App defaults and organization settings can still affect behavior. Supported-on labels are informational; they do not install or upgrade the app.

## Pilot and verify

1. Use a current Claude Desktop build and the appropriate Team or Enterprise plan. For the newer controls, check the build requirements in `POLICY-REFERENCE.md`.
2. Select a reversible test, such as **Allow desktop extensions = Disabled**. Keep unrelated settings Not configured. Do not enter placeholder organization IDs in an assigned profile.
3. Sync the device with Intune and inspect the profile's device and setting status. Fully quit Claude Desktop and reopen it before checking behavior.
4. On the endpoint, inspect the native 64-bit policy registry:

   ```powershell
   reg.exe query "HKLM\SOFTWARE\Policies\Claude" /reg:64
   ```

5. Confirm the value name, type, and data against the reference. For the extension test, expect `isDesktopExtensionEnabled`, `REG_DWORD`, and `0x0`. Numeric output from `reg.exe` is hexadecimal: a 72-hour interval appears as `0x48`.
6. Confirm the actual feature behavior in Claude. For sign-in restrictions, also use **Help → Troubleshooting → Generate Diagnostic Report** to inspect what the app read. Registry delivery alone is not proof of application enforcement.
7. Change the test setting to Enabled, sync, reopen the app, and verify the opposite state. Finally test Not configured/unassignment and inspect the registry again. For a text or numeric setting, also test Disabled and confirm that only its named value is removed.
8. Expand assignment only after application behavior and rollback both match your intended result.

## Rollback and future versions

- For an **Allow** setting, Enabled expressly permits that feature at the machine-policy layer; Disabled expressly blocks it. Choose the state you actually intend during rollback.
- For a text/dropdown/numeric setting, Disabled requests deletion of its single value. To stop managing a setting, use Not configured or remove its assignment, sync, and verify the device result. If a value remains or reappears, investigate other profiles/scripts and pending MDM processing before manually deleting it.
- Removing EDR configuration does not uninstall a sensor already present in the Cowork VM. Follow the vendor's removal process.
- Do not delete the entire `Claude` registry key: it may contain values managed elsewhere.
- Namespace: `Custom.Policies.ClaudeDesktop.v1`. Import only one copy with this namespace. Renaming the file does not change namespace identity.
- Intune does not simply overwrite an imported ADMX with duplicate settings. For a future package version, plan a replacement using Microsoft's documented process or a separately versioned namespace. Do not assign old and new templates to the same devices for the same values. Preserve your profile settings before removing an old profile/template.

## Troubleshooting import and delivery

| Symptom | Check |
|---|---|
| Import cannot resolve strings or presentations | Both files must come from this exact package. Select the ADML inside `en-US`. |
| Duplicate namespace/settings error | Check whether `Custom.Policies.ClaudeDesktop.v1` is already imported. Do not upload renamed duplicates. |
| File-limit error | Intune currently allows up to 20 imported ADMX files, each at most 1 MB. This package uses one small ADMX. |
| Profile succeeds but behavior is unchanged | Check the actual registry value/type, app build, complete app restart, licensing, and competing policy sources. |
| JSON setting is accepted but ineffective | Intune's textbox does not validate JSON, organization membership, or folder existence. Validate those separately. |
| A feature remains restricted after policy removal | Check HKLM/HKCU, organization settings, other management sources, and the app's effective configuration. |

## Sources

- [Anthropic: Enterprise configuration for Claude Desktop](https://support.claude.com/en/articles/12622667-enterprise-configuration-for-claude-desktop)
- [Anthropic: Deploy Claude Desktop for Windows](https://support.claude.com/en/articles/12622703-deploy-claude-desktop-for-windows)
- [Anthropic: Run an EDR sensor in Claude Cowork](https://support.claude.com/en/articles/17828685-run-your-endpoint-detection-and-response-edr-sensor-in-claude-cowork-on-claude-desktop)
- [Microsoft: Import custom ADMX and ADML templates](https://learn.microsoft.com/en-us/intune/device-configuration/settings-catalog/import-custom-admx-templates)
- [Microsoft: ADMX policy ingestion](https://learn.microsoft.com/en-us/windows/client-management/win32-and-centennial-app-policy-configuration)
- [Microsoft: ADMX schema](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gpreg/ddeb37b6-22ab-4936-adc4-b9d7fe1de6e6)

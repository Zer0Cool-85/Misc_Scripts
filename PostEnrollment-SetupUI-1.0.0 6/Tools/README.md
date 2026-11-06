Place your existing **x64 ServiceUI.exe** in this folder if you use
Run-Live-ServiceUI.cmd. No Microsoft executable is redistributed in this package.

You can instead keep your existing launcher and point it at Start-DeviceSetup.ps1.
ServiceUI displays the SYSTEM-launched window in the selected interactive session;
it does not elevate an ordinary user's process. The sample launcher targets
explorer.exe and is intended for a normal desktop session after provisioning.
Retain your existing session selection if you use shared devices or multiple sessions.

The new inventory and first-logon launchers use the same x64 ServiceUI executable. Run `Stage-WinGetClient.ps1` on a packaging workstation to stage an approved AllUsers-capable WinGet PowerShell module in the package, as described in [Hotfix 10](../Docs/HOTFIX10.md).

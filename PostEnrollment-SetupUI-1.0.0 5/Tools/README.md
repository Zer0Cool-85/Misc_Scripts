Place your existing **x64 ServiceUI.exe** in this folder if you use
Run-Live-ServiceUI.cmd. No Microsoft executable is redistributed in this package.

You can instead keep your existing launcher and point it at Start-DeviceSetup.ps1.
ServiceUI displays the SYSTEM-launched window in the selected interactive session;
it does not elevate an ordinary user's process. The sample launcher targets
explorer.exe and is intended for a normal desktop session after provisioning.
Retain your existing session selection if you use shared devices or multiple sessions.

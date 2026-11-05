using System;
using System.Runtime.InteropServices;

namespace DeviceSetupUI {
    public static class TaskbarIdentity {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
        private static extern int SetCurrentProcessExplicitAppUserModelID(string appId);

        // Call in a dedicated powershell.exe process, before showing any window.
        public static void Set(string appId) {
            if (String.IsNullOrWhiteSpace(appId) || appId.Length > 128)
                throw new ArgumentException("Taskbar identity must be 1-128 characters.", "appId");
            Marshal.ThrowExceptionForHR(SetCurrentProcessExplicitAppUserModelID(appId));
        }
    }
}

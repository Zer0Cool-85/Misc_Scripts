#requires -Version 5.1
# Standalone Intune upload script; no companion file is needed.
$ErrorActionPreference = 'Stop'
$script:Component = 'Detection'
#requires -Version 5.1
# Shared implementation for the installer. Intune upload scripts contain their
# own embedded copy, because Intune runs them outside this package directory.
# If changing these settings, also update both scripts in the Intune folder.
$script:StateRoot = 'HKLM:\SOFTWARE\DeviceRenameRemediation'
$script:AllowedDeviceTypes = @('LT', 'DT', 'VM', 'SRV', 'PC')
$script:NotificationVersion = '1.1.0'
# Embedded payload is regenerated from User-RebootToast.ps1 by Build-UploadScripts.ps1.
$script:ToastPayloadBase64 = '77u/I3JlcXVpcmVzIC1WZXJzaW9uIDUuMQ0KPCMgUnVucyBvbmx5IGluIHRoZSBpbnRlcmFjdGl2ZSB1c2VyJ3MgV2luZG93cyBQb3dlclNoZWxsIDUuMSBzZXNzaW9uLg0KICAgU2hvdyBzdWJtaXRzIG9uZSBuYXRpdmUgdG9hc3QgYW5kIGV4aXRzLiBXaW5kb3dzIGltcGxlbWVudHMgU25vb3plLg0KICAgQWN0aXZhdGUgaGFuZGxlcyBvbmx5IHRoZSBleGFjdCBwcm90b2NvbCByb3V0ZXMgYW5kIGN1cnJlbnQgcmFuZG9tIHRva2VuLg0KICAgQ2xlYW51cCByZW1vdmVzIHRoaXMgdXNlcidzIHRvYXN0IHJlZ2lzdHJhdGlvbiBhbmQgc2hvcnRjdXQsIG5vdCB0aGUgbmFtZS4NCiM+DQpbQ21kbGV0QmluZGluZygpXQ0KcGFyYW0oDQogICAgW1ZhbGlkYXRlU2V0KCdTaG93JywnQWN0aXZhdGUnLCdDbGVhbnVwJyldW3N0cmluZ10kTW9kZSA9ICdTaG93JywNCiAgICBbc3RyaW5nXSRBY3RpdmF0aW9uVXJpLA0KICAgIFtzd2l0Y2hdJFByZXZpZXcNCikNCiRFcnJvckFjdGlvblByZWZlcmVuY2UgPSAnU3RvcCcNCiRzY3JpcHQ6QXBwSWQgPSAnRGV2aWNlUmVuYW1lUmVtZWRpYXRpb24uUmVib290Jw0KJHNjcmlwdDpQcm90b2NvbCA9ICdkZXZpY2VyZW5hbWUtcmVib290Jw0KJHNjcmlwdDpVc2VyUm9vdCA9ICdIS0NVOlxTb2Z0d2FyZVxEZXZpY2VSZW5hbWVSZW1lZGlhdGlvblxUb2FzdCcNCiRzY3JpcHQ6RGlzcGxheU5hbWUgPSAnSVQgRGV2aWNlIFNldHVwJw0KDQpmdW5jdGlvbiBXcml0ZS1Ub2FzdExvZyB7DQogICAgcGFyYW0oW3N0cmluZ10kTWVzc2FnZSkNCiAgICB0cnkgew0KICAgICAgICAkZGlyZWN0b3J5ID0gSm9pbi1QYXRoICRlbnY6TE9DQUxBUFBEQVRBICdEZXZpY2VSZW5hbWVSZW1lZGlhdGlvbicNCiAgICAgICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJGRpcmVjdG9yeSkpIHsgW3ZvaWRdKE5ldy1JdGVtIC1QYXRoICRkaXJlY3RvcnkgLUl0ZW1UeXBlIERpcmVjdG9yeSkgfQ0KICAgICAgICBBZGQtQ29udGVudCAtTGl0ZXJhbFBhdGggKEpvaW4tUGF0aCAkZGlyZWN0b3J5ICdUb2FzdC5sb2cnKSAtRW5jb2RpbmcgVVRGOCAtVmFsdWUgKCIkKFtEYXRlVGltZV06OlV0Y05vdy5Ub1N0cmluZygnbycpKSAkTWVzc2FnZSIpDQogICAgfSBjYXRjaCB7IH0NCn0NCg0KZnVuY3Rpb24gR2V0LVRvYXN0TmFtZVN0YXRlIHsNCiAgICAka2V5ID0gJ0hLTE06XFNZU1RFTVxDdXJyZW50Q29udHJvbFNldFxDb250cm9sXENvbXB1dGVyTmFtZScNCiAgICAkYWN0aXZlID0gW3N0cmluZ10oR2V0LUl0ZW1Qcm9wZXJ0eVZhbHVlIC1MaXRlcmFsUGF0aCAiJGtleVxBY3RpdmVDb21wdXRlck5hbWUiIC1OYW1lIENvbXB1dGVyTmFtZSAtRXJyb3JBY3Rpb24gU3RvcCkNCiAgICAkdGFyZ2V0ID0gW3N0cmluZ10oR2V0LUl0ZW1Qcm9wZXJ0eVZhbHVlIC1MaXRlcmFsUGF0aCAiJGtleVxDb21wdXRlck5hbWUiIC1OYW1lIENvbXB1dGVyTmFtZSAtRXJyb3JBY3Rpb24gU3RvcCkNCiAgICBpZiAoW3N0cmluZ106OklzTnVsbE9yV2hpdGVTcGFjZSgkYWN0aXZlKSAtb3IgW3N0cmluZ106OklzTnVsbE9yV2hpdGVTcGFjZSgkdGFyZ2V0KSkgeyB0aHJvdyAnQ29tcHV0ZXItbmFtZSBzdGF0ZSBpcyB1bmF2YWlsYWJsZS4nIH0NCiAgICBbcHNjdXN0b21vYmplY3RdQHsgQWN0aXZlPSRhY3RpdmU7IFRhcmdldD0kdGFyZ2V0OyBQZW5kaW5nPSgkYWN0aXZlIC1pbmUgJHRhcmdldCkgfQ0KfQ0KDQpmdW5jdGlvbiBSZWFkLVRvYXN0UmVjb3JkIHsNCiAgICBpZiAoLW5vdCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkc2NyaXB0OlVzZXJSb290KSkgeyByZXR1cm4gJG51bGwgfQ0KICAgICRwcm9wZXJ0aWVzID0gR2V0LUl0ZW1Qcm9wZXJ0eSAtTGl0ZXJhbFBhdGggJHNjcmlwdDpVc2VyUm9vdCAtRXJyb3JBY3Rpb24gU3RvcA0KICAgICR2YWx1ZSA9ICRwcm9wZXJ0aWVzLlBTT2JqZWN0LlByb3BlcnRpZXNbJ0N1cnJlbnQnXQ0KICAgIGlmICgkbnVsbCAtZXEgJHZhbHVlIC1vciBbc3RyaW5nXTo6SXNOdWxsT3JXaGl0ZVNwYWNlKFtzdHJpbmddJHZhbHVlLlZhbHVlKSkgeyByZXR1cm4gJG51bGwgfQ0KICAgIHRyeSB7IHJldHVybiAoJHZhbHVlLlZhbHVlIHwgQ29udmVydEZyb20tSnNvbiAtRXJyb3JBY3Rpb24gU3RvcCkgfSBjYXRjaCB7IHJldHVybiAkbnVsbCB9DQp9DQoNCmZ1bmN0aW9uIFNhdmUtVG9hc3RSZWNvcmQgew0KICAgIHBhcmFtKFtQYXJhbWV0ZXIoTWFuZGF0b3J5KV0kUmVjb3JkKQ0KICAgIGlmICgtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRzY3JpcHQ6VXNlclJvb3QpKSB7IFt2b2lkXShOZXctSXRlbSAtUGF0aCAkc2NyaXB0OlVzZXJSb290IC1Gb3JjZSkgfQ0KICAgIFt2b2lkXShOZXctSXRlbVByb3BlcnR5IC1MaXRlcmFsUGF0aCAkc2NyaXB0OlVzZXJSb290IC1OYW1lIEN1cnJlbnQgLVByb3BlcnR5VHlwZSBTdHJpbmcgLVZhbHVlICgkUmVjb3JkIHwgQ29udmVydFRvLUpzb24gLUNvbXByZXNzKSAtRm9yY2UpDQp9DQoNCmZ1bmN0aW9uIFRlc3QtUmVzdGFydEF1dGhvcml6YXRpb24gew0KICAgIHBhcmFtKCRSZWNvcmQsICROYW1lU3RhdGUsIFtzdHJpbmddJFRva2VuLCBbbG9uZ10kTm93VGlja3MgPSBbRGF0ZVRpbWVdOjpVdGNOb3cuVGlja3MpDQogICAgaWYgKCRudWxsIC1lcSAkUmVjb3JkIC1vciAkbnVsbCAtZXEgJE5hbWVTdGF0ZSkgeyByZXR1cm4gJGZhbHNlIH0NCiAgICBpZiAoJFRva2VuIC1jbm90bWF0Y2ggJ1xBW2EtZjAtOV17MzJ9XHonIC1vciAkUmVjb3JkLlRva2VuIC1jbmUgJFRva2VuKSB7IHJldHVybiAkZmFsc2UgfQ0KICAgIGlmICgkUmVjb3JkLlByZXZpZXcgLW5lICRmYWxzZSAtb3IgJFJlY29yZC5Db25zdW1lZCAtbmUgJGZhbHNlKSB7IHJldHVybiAkZmFsc2UgfQ0KICAgICRleHBpcmVzID0gW2xvbmddMA0KICAgIGlmICgtbm90IFtsb25nXTo6VHJ5UGFyc2UoW3N0cmluZ10kUmVjb3JkLkV4cGlyZXNUaWNrcywgW3JlZl0kZXhwaXJlcykgLW9yICRleHBpcmVzIC1sZSAkTm93VGlja3MpIHsgcmV0dXJuICRmYWxzZSB9DQogICAgcmV0dXJuICgkTmFtZVN0YXRlLlBlbmRpbmcgLWFuZCAkTmFtZVN0YXRlLkFjdGl2ZSAtaWVxICRSZWNvcmQuQWN0aXZlIC1hbmQgJE5hbWVTdGF0ZS5UYXJnZXQgLWllcSAkUmVjb3JkLlRhcmdldCkNCn0NCg0KZnVuY3Rpb24gR2V0LVRvYXN0QWN0aXZhdGlvbiB7DQogICAgcGFyYW0oW3N0cmluZ10kVXJpKQ0KICAgICMgTm8gYXJiaXRyYXJ5IGNvbW1hbmQsIHBhdGgsIGFyZ3VtZW50cywgb3IgVVJJIHF1ZXJ5IGlzIGV2ZXIgZXhlY3V0ZWQuDQogICAgaWYgKCRVcmkgLWNtYXRjaCAnXEFkZXZpY2VyZW5hbWUtcmVib290Oi8vKHJlc3RhcnR8b3BlbikvKFthLWYwLTldezMyfSkvP1x6Jykgew0KICAgICAgICByZXR1cm4gW3BzY3VzdG9tb2JqZWN0XUB7IEFjdGlvbj0kTWF0Y2hlc1sxXTsgVG9rZW49JE1hdGNoZXNbMl0gfQ0KICAgIH0NCiAgICByZXR1cm4gJG51bGwNCn0NCg0KZnVuY3Rpb24gTmV3LVJlbmFtZVRvYXN0WG1sIHsNCiAgICBwYXJhbShbUGFyYW1ldGVyKE1hbmRhdG9yeSldW3N0cmluZ10kVG9rZW4sIFtzd2l0Y2hdJElzUHJldmlldykNCiAgICBpZiAoJFRva2VuIC1jbm90bWF0Y2ggJ1xBW2EtZjAtOV17MzJ9XHonKSB7IHRocm93ICdJbnZhbGlkIHRvYXN0IHRva2VuLicgfQ0KICAgICR0aXRsZSA9ICdSZXN0YXJ0IHJlcXVpcmVkJw0KICAgICRib2R5ID0gJ1lvdXIgUEMgbmVlZHMgYSByZXN0YXJ0IHRvIGZpbmlzaCBhIGRldmljZS1uYW1lIHVwZGF0ZS4gU2F2ZSB5b3VyIHdvcmsgYmVmb3JlIGNob29zaW5nIFJlc3RhcnQgbm93LicNCiAgICBpZiAoJElzUHJldmlldykgeyAkdGl0bGUgPSAnUHJldmlldzogcmVzdGFydCByZW1pbmRlcic7ICRib2R5ID0gJ1RoaXMgaXMgYSB0ZXN0IG5vdGlmaWNhdGlvbi4gUmVzdGFydCBub3cgaXMgZGlzYWJsZWQgaW4gdGhpcyBwcmV2aWV3OyBTbm9vemUgY2FuIGJlIHRlc3RlZCBub3JtYWxseS4nIH0NCiAgICAkdGl0bGUgPSBbU2VjdXJpdHkuU2VjdXJpdHlFbGVtZW50XTo6RXNjYXBlKCR0aXRsZSkNCiAgICAkYm9keSA9IFtTZWN1cml0eS5TZWN1cml0eUVsZW1lbnRdOjpFc2NhcGUoJGJvZHkpDQogICAgcmV0dXJuIEAiDQo8dG9hc3Qgc2NlbmFyaW89InJlbWluZGVyIiBhY3RpdmF0aW9uVHlwZT0icHJvdG9jb2wiIGxhdW5jaD0iZGV2aWNlcmVuYW1lLXJlYm9vdDovL29wZW4vJFRva2VuIj4NCiAgPHZpc3VhbD48YmluZGluZyB0ZW1wbGF0ZT0iVG9hc3RHZW5lcmljIj48dGV4dD4kdGl0bGU8L3RleHQ+PHRleHQ+JGJvZHk8L3RleHQ+PC9iaW5kaW5nPjwvdmlzdWFsPg0KICA8YWN0aW9ucz4NCiAgICA8aW5wdXQgaWQ9InNub296ZVRpbWUiIHR5cGU9InNlbGVjdGlvbiIgdGl0bGU9IlJlbWluZCBtZSBpbiIgZGVmYXVsdElucHV0PSIxNSI+DQogICAgICA8c2VsZWN0aW9uIGlkPSIxNSIgY29udGVudD0iMTUgbWludXRlcyIgLz4NCiAgICAgIDxzZWxlY3Rpb24gaWQ9IjYwIiBjb250ZW50PSIxIGhvdXIiIC8+DQogICAgICA8c2VsZWN0aW9uIGlkPSIyNDAiIGNvbnRlbnQ9IjQgaG91cnMiIC8+DQogICAgPC9pbnB1dD4NCiAgICA8YWN0aW9uIGNvbnRlbnQ9IlNub296ZSIgYWN0aXZhdGlvblR5cGU9InN5c3RlbSIgYXJndW1lbnRzPSJzbm9vemUiIGhpbnQtaW5wdXRJZD0ic25vb3plVGltZSIgLz4NCiAgICA8YWN0aW9uIGNvbnRlbnQ9IlJlc3RhcnQgbm93IiBhY3RpdmF0aW9uVHlwZT0icHJvdG9jb2wiIGFyZ3VtZW50cz0iZGV2aWNlcmVuYW1lLXJlYm9vdDovL3Jlc3RhcnQvJFRva2VuIiAvPg0KICA8L2FjdGlvbnM+DQogIDxhdWRpbyBzcmM9Im1zLXdpbnNvdW5kZXZlbnQ6Tm90aWZpY2F0aW9uLkRlZmF1bHQiIC8+DQo8L3RvYXN0Pg0KIkANCn0NCg0KZnVuY3Rpb24gSW5pdGlhbGl6ZS1TaG9ydGN1dEludGVyb3Agew0KICAgIGlmICgnRGV2aWNlUmVuYW1lVG9hc3QuU2hvcnRjdXRQcm9wZXJ0aWVzJyAtYXMgW3R5cGVdKSB7IHJldHVybiB9DQogICAgQWRkLVR5cGUgLUVycm9yQWN0aW9uIFN0b3AgLVR5cGVEZWZpbml0aW9uIEAnDQp1c2luZyBTeXN0ZW07DQp1c2luZyBTeXN0ZW0uUnVudGltZS5JbnRlcm9wU2VydmljZXM7DQpuYW1lc3BhY2UgRGV2aWNlUmVuYW1lVG9hc3Qgew0KICAgIFtTdHJ1Y3RMYXlvdXQoTGF5b3V0S2luZC5TZXF1ZW50aWFsKV0NCiAgICBwdWJsaWMgc3RydWN0IFByb3BlcnR5S2V5IHsgcHVibGljIEd1aWQgRm9ybWF0SWQ7IHB1YmxpYyB1aW50IElkOyB9DQogICAgW1N0cnVjdExheW91dChMYXlvdXRLaW5kLkV4cGxpY2l0LCBTaXplPTI0KV0NCiAgICBwdWJsaWMgc3RydWN0IFByb3BWYXJpYW50IHsNCiAgICAgICAgW0ZpZWxkT2Zmc2V0KDApXSBwdWJsaWMgdXNob3J0IFR5cGU7DQogICAgICAgIFtGaWVsZE9mZnNldCg4KV0gcHVibGljIEludFB0ciBQb2ludGVyOw0KICAgIH0NCiAgICBbQ29tSW1wb3J0LCBHdWlkKCI4ODZEOEVFQi04Q0YyLTQ0NDYtOEQwMi1DREJBMURCRENGOTkiKSwgSW50ZXJmYWNlVHlwZShDb21JbnRlcmZhY2VUeXBlLkludGVyZmFjZUlzSVVua25vd24pXQ0KICAgIHB1YmxpYyBpbnRlcmZhY2UgSVByb3BlcnR5U3RvcmUgew0KICAgICAgICBbUHJlc2VydmVTaWddIGludCBHZXRDb3VudChvdXQgdWludCBjb3VudCk7DQogICAgICAgIFtQcmVzZXJ2ZVNpZ10gaW50IEdldEF0KHVpbnQgaW5kZXgsIG91dCBQcm9wZXJ0eUtleSBrZXkpOw0KICAgICAgICBbUHJlc2VydmVTaWddIGludCBHZXRWYWx1ZShyZWYgUHJvcGVydHlLZXkga2V5LCBvdXQgUHJvcFZhcmlhbnQgdmFsdWUpOw0KICAgICAgICBbUHJlc2VydmVTaWddIGludCBTZXRWYWx1ZShyZWYgUHJvcGVydHlLZXkga2V5LCByZWYgUHJvcFZhcmlhbnQgdmFsdWUpOw0KICAgICAgICBbUHJlc2VydmVTaWddIGludCBDb21taXQoKTsNCiAgICB9DQogICAgcHVibGljIHN0YXRpYyBjbGFzcyBTaG9ydGN1dFByb3BlcnRpZXMgew0KICAgICAgICBbRGxsSW1wb3J0KCJzaGVsbDMyLmRsbCIsIENoYXJTZXQ9Q2hhclNldC5Vbmljb2RlLCBFeGFjdFNwZWxsaW5nPXRydWUpXQ0KICAgICAgICBwcml2YXRlIHN0YXRpYyBleHRlcm4gaW50IFNIR2V0UHJvcGVydHlTdG9yZUZyb21QYXJzaW5nTmFtZShzdHJpbmcgcGF0aCwgSW50UHRyIGJpbmRpbmcsDQogICAgICAgICAgICB1aW50IGZsYWdzLCByZWYgR3VpZCBpbnRlcmZhY2VJZCwgb3V0IElQcm9wZXJ0eVN0b3JlIHN0b3JlKTsNCiAgICAgICAgW0RsbEltcG9ydCgib2xlMzIuZGxsIiwgRXhhY3RTcGVsbGluZz10cnVlKV0NCiAgICAgICAgcHJpdmF0ZSBzdGF0aWMgZXh0ZXJuIGludCBQcm9wVmFyaWFudENsZWFyKHJlZiBQcm9wVmFyaWFudCB2YWx1ZSk7DQogICAgICAgIHB1YmxpYyBzdGF0aWMgdm9pZCBTZXQoc3RyaW5nIHNob3J0Y3V0LCBzdHJpbmcgYXBwSWQsIHN0cmluZyBhY3RpdmF0b3JJZCkgew0KICAgICAgICAgICAgR3VpZCBpaWQgPSB0eXBlb2YoSVByb3BlcnR5U3RvcmUpLkdVSUQ7DQogICAgICAgICAgICBJUHJvcGVydHlTdG9yZSBzdG9yZTsNCiAgICAgICAgICAgIE1hcnNoYWwuVGhyb3dFeGNlcHRpb25Gb3JIUihTSEdldFByb3BlcnR5U3RvcmVGcm9tUGFyc2luZ05hbWUoc2hvcnRjdXQsIEludFB0ci5aZXJvLCAyLCByZWYgaWlkLCBvdXQgc3RvcmUpKTsNCiAgICAgICAgICAgIHRyeSB7DQogICAgICAgICAgICAgICAgdmFyIGtleSA9IG5ldyBQcm9wZXJ0eUtleSB7IEZvcm1hdElkPW5ldyBHdWlkKCI5RjRDMjg1NS05Rjc5LTRCMzktQThEMC1FMUQ0MkRFMUQ1RjMiKSwgSWQ9NSB9Ow0KICAgICAgICAgICAgICAgIHZhciB2YWx1ZSA9IG5ldyBQcm9wVmFyaWFudCB7IFR5cGU9MzEsIFBvaW50ZXI9TWFyc2hhbC5TdHJpbmdUb0NvVGFza01lbVVuaShhcHBJZCkgfTsNCiAgICAgICAgICAgICAgICB0cnkgeyBNYXJzaGFsLlRocm93RXhjZXB0aW9uRm9ySFIoc3RvcmUuU2V0VmFsdWUocmVmIGtleSwgcmVmIHZhbHVlKSk7IH0NCiAgICAgICAgICAgICAgICBmaW5hbGx5IHsgUHJvcFZhcmlhbnRDbGVhcihyZWYgdmFsdWUpOyB9DQogICAgICAgICAgICAgICAgLy8gQSBzdHViIENMU0lEIHBlcm1pdHMgcHJvdG9jb2wtYWN0aXZhdGVkIG5vdGlmaWNhdGlvbnMgdG8gcGVyc2lzdC4NCiAgICAgICAgICAgICAgICBrZXkuSWQgPSAyNjsNCiAgICAgICAgICAgICAgICB2YWx1ZSA9IG5ldyBQcm9wVmFyaWFudCB7IFR5cGU9NzIsIFBvaW50ZXI9TWFyc2hhbC5BbGxvY0NvVGFza01lbSgxNikgfTsNCiAgICAgICAgICAgICAgICB0cnkgew0KICAgICAgICAgICAgICAgICAgICBNYXJzaGFsLkNvcHkobmV3IEd1aWQoYWN0aXZhdG9ySWQpLlRvQnl0ZUFycmF5KCksIDAsIHZhbHVlLlBvaW50ZXIsIDE2KTsNCiAgICAgICAgICAgICAgICAgICAgTWFyc2hhbC5UaHJvd0V4Y2VwdGlvbkZvckhSKHN0b3JlLlNldFZhbHVlKHJlZiBrZXksIHJlZiB2YWx1ZSkpOw0KICAgICAgICAgICAgICAgIH0gZmluYWxseSB7IFByb3BWYXJpYW50Q2xlYXIocmVmIHZhbHVlKTsgfQ0KICAgICAgICAgICAgICAgIE1hcnNoYWwuVGhyb3dFeGNlcHRpb25Gb3JIUihzdG9yZS5Db21taXQoKSk7DQogICAgICAgICAgICB9IGZpbmFsbHkgeyBNYXJzaGFsLlJlbGVhc2VDb21PYmplY3Qoc3RvcmUpOyB9DQogICAgICAgIH0NCiAgICB9DQp9DQonQCB8IE91dC1OdWxsDQp9DQoNCmZ1bmN0aW9uIFJlZ2lzdGVyLVRvYXN0SWRlbnRpdHkgew0KICAgIEluaXRpYWxpemUtU2hvcnRjdXRJbnRlcm9wDQogICAgJHBvd2VyU2hlbGwgPSBKb2luLVBhdGggJGVudjpXSU5ESVIgJ1N5c3RlbTMyXFdpbmRvd3NQb3dlclNoZWxsXHYxLjBccG93ZXJzaGVsbC5leGUnDQogICAgJHNjcmlwdFBhdGggPSAkUFNDb21tYW5kUGF0aA0KICAgICRjb21tYW5kID0gJyJ7MH0iIC1Ob0xvZ28gLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLVdpbmRvd1N0eWxlIEhpZGRlbiAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiezF9IiAtTW9kZSBBY3RpdmF0ZSAtQWN0aXZhdGlvblVyaSAiJTEiJyAtZiAkcG93ZXJTaGVsbCwgJHNjcmlwdFBhdGgNCiAgICAkcHJvdG9jb2xLZXkgPSAnSEtDVTpcU29mdHdhcmVcQ2xhc3Nlc1wnICsgJHNjcmlwdDpQcm90b2NvbA0KICAgIGZvcmVhY2ggKCRwYXRoIGluIEAoJHByb3RvY29sS2V5LCAiJHByb3RvY29sS2V5XHNoZWxsIiwgIiRwcm90b2NvbEtleVxzaGVsbFxvcGVuIiwgIiRwcm90b2NvbEtleVxzaGVsbFxvcGVuXGNvbW1hbmQiKSkgew0KICAgICAgICBpZiAoLW5vdCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkcGF0aCkpIHsgW3ZvaWRdKE5ldy1JdGVtIC1QYXRoICRwYXRoIC1Gb3JjZSkgfQ0KICAgIH0NCiAgICBTZXQtSXRlbSAtTGl0ZXJhbFBhdGggJHByb3RvY29sS2V5IC1WYWx1ZSAnVVJMOkRldmljZSByZW5hbWUgcmVzdGFydCByZW1pbmRlcicNCiAgICBbdm9pZF0oTmV3LUl0ZW1Qcm9wZXJ0eSAtTGl0ZXJhbFBhdGggJHByb3RvY29sS2V5IC1OYW1lICdVUkwgUHJvdG9jb2wnIC1Qcm9wZXJ0eVR5cGUgU3RyaW5nIC1WYWx1ZSAnJyAtRm9yY2UpDQogICAgU2V0LUl0ZW0gLUxpdGVyYWxQYXRoICIkcHJvdG9jb2xLZXlcc2hlbGxcb3Blblxjb21tYW5kIiAtVmFsdWUgJGNvbW1hbmQNCiAgICAkaWRlbnRpdHkgPSAnSEtDVTpcU29mdHdhcmVcQ2xhc3Nlc1xBcHBVc2VyTW9kZWxJZFwnICsgJHNjcmlwdDpBcHBJZA0KICAgIGlmICgtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRpZGVudGl0eSkpIHsgW3ZvaWRdKE5ldy1JdGVtIC1QYXRoICRpZGVudGl0eSAtRm9yY2UpIH0NCiAgICBbdm9pZF0oTmV3LUl0ZW1Qcm9wZXJ0eSAtTGl0ZXJhbFBhdGggJGlkZW50aXR5IC1OYW1lIERpc3BsYXlOYW1lIC1Qcm9wZXJ0eVR5cGUgU3RyaW5nIC1WYWx1ZSAkc2NyaXB0OkRpc3BsYXlOYW1lIC1Gb3JjZSkNCiAgICAkc2hvcnRjdXRQYXRoID0gSm9pbi1QYXRoIChbRW52aXJvbm1lbnRdOjpHZXRGb2xkZXJQYXRoKCdQcm9ncmFtcycpKSAnSVQgRGV2aWNlIFJlc3RhcnQubG5rJw0KICAgICRzaGVsbCA9IE5ldy1PYmplY3QgLUNvbU9iamVjdCBXU2NyaXB0LlNoZWxsDQogICAgJHNob3J0Y3V0ID0gJHNoZWxsLkNyZWF0ZVNob3J0Y3V0KCRzaG9ydGN1dFBhdGgpDQogICAgdHJ5IHsNCiAgICAgICAgJHNob3J0Y3V0LlRhcmdldFBhdGggPSAkcG93ZXJTaGVsbA0KICAgICAgICAkc2hvcnRjdXQuQXJndW1lbnRzID0gJy1Ob0xvZ28gLU5vUHJvZmlsZSAtTm9uSW50ZXJhY3RpdmUgLVdpbmRvd1N0eWxlIEhpZGRlbiAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiezB9IiAtTW9kZSBTaG93JyAtZiAkc2NyaXB0UGF0aA0KICAgICAgICAkc2hvcnRjdXQuRGVzY3JpcHRpb24gPSAnU2hvdyB0aGUgcGVuZGluZyBjb21wdXRlciByZW5hbWUgcmVzdGFydCByZW1pbmRlcicNCiAgICAgICAgJHNob3J0Y3V0Lkljb25Mb2NhdGlvbiA9ICIkZW52OldJTkRJUlxTeXN0ZW0zMlxzaGVsbDMyLmRsbCwyMzgiDQogICAgICAgICRzaG9ydGN1dC5TYXZlKCkNCiAgICB9IGZpbmFsbHkgeyBbdm9pZF1bUnVudGltZS5JbnRlcm9wU2VydmljZXMuTWFyc2hhbF06OlJlbGVhc2VDb21PYmplY3QoJHNob3J0Y3V0KTsgW3ZvaWRdW1J1bnRpbWUuSW50ZXJvcFNlcnZpY2VzLk1hcnNoYWxdOjpSZWxlYXNlQ29tT2JqZWN0KCRzaGVsbCkgfQ0KICAgIFtEZXZpY2VSZW5hbWVUb2FzdC5TaG9ydGN1dFByb3BlcnRpZXNdOjpTZXQoJHNob3J0Y3V0UGF0aCwgJHNjcmlwdDpBcHBJZCwgJ0Y0QkQ5MUIxLTRFRDUtNEUxOC05QjJFLTZGOEY5QkY3ODg1NicpDQp9DQoNCmZ1bmN0aW9uIEluaXRpYWxpemUtVG9hc3RSdW50aW1lIHsNCiAgICBbdm9pZF1bV2luZG93cy5VSS5Ob3RpZmljYXRpb25zLlRvYXN0Tm90aWZpY2F0aW9uTWFuYWdlciwgV2luZG93cy5VSS5Ob3RpZmljYXRpb25zLCBDb250ZW50VHlwZT1XaW5kb3dzUnVudGltZV0NCiAgICBbdm9pZF1bV2luZG93cy5VSS5Ob3RpZmljYXRpb25zLlRvYXN0Tm90aWZpY2F0aW9uLCBXaW5kb3dzLlVJLk5vdGlmaWNhdGlvbnMsIENvbnRlbnRUeXBlPVdpbmRvd3NSdW50aW1lXQ0KICAgIFt2b2lkXVtXaW5kb3dzLkRhdGEuWG1sLkRvbS5YbWxEb2N1bWVudCwgV2luZG93cy5EYXRhLlhtbC5Eb20uWG1sRG9jdW1lbnQsIENvbnRlbnRUeXBlPVdpbmRvd3NSdW50aW1lXQ0KfQ0KDQpmdW5jdGlvbiBSZW1vdmUtUmVuYW1lVG9hc3Qgew0KICAgIHRyeSB7IEluaXRpYWxpemUtVG9hc3RSdW50aW1lOyBbV2luZG93cy5VSS5Ob3RpZmljYXRpb25zLlRvYXN0Tm90aWZpY2F0aW9uTWFuYWdlcl06Okhpc3RvcnkuQ2xlYXIoJHNjcmlwdDpBcHBJZCkgfSBjYXRjaCB7IFdyaXRlLVRvYXN0TG9nICJDbGVhciB0b2FzdDogJCgkXy5FeGNlcHRpb24uTWVzc2FnZSkiIH0NCn0NCg0KZnVuY3Rpb24gU2hvdy1SZW5hbWVUb2FzdCB7DQogICAgcGFyYW0oW3N3aXRjaF0kSXNQcmV2aWV3KQ0KICAgICRzdGF0ZSA9IEdldC1Ub2FzdE5hbWVTdGF0ZQ0KICAgIGlmICgtbm90ICRzdGF0ZS5QZW5kaW5nIC1hbmQgLW5vdCAkSXNQcmV2aWV3KSB7DQogICAgICAgIFJlbW92ZS1SZW5hbWVUb2FzdA0KICAgICAgICBXcml0ZS1Ub2FzdExvZyAnTm8gcGVuZGluZyBjb21wdXRlciByZW5hbWU7IG5vdGhpbmcgdG8gZGlzcGxheS4nDQogICAgICAgIHJldHVybg0KICAgIH0NCiAgICBSZWdpc3Rlci1Ub2FzdElkZW50aXR5DQogICAgSW5pdGlhbGl6ZS1Ub2FzdFJ1bnRpbWUNCiAgICAkdG9rZW4gPSBbR3VpZF06Ok5ld0d1aWQoKS5Ub1N0cmluZygnTicpDQogICAgJGV4cGlyZXMgPSBbRGF0ZVRpbWVdOjpVdGNOb3cuQWRkRGF5cygxKQ0KICAgIFNhdmUtVG9hc3RSZWNvcmQgKFtwc2N1c3RvbW9iamVjdF1AeyBUb2tlbj0kdG9rZW47IEFjdGl2ZT0kc3RhdGUuQWN0aXZlOyBUYXJnZXQ9JHN0YXRlLlRhcmdldDsgUHJldmlldz1bYm9vbF0kSXNQcmV2aWV3OyBDb25zdW1lZD0kZmFsc2U7IEV4cGlyZXNUaWNrcz0kZXhwaXJlcy5UaWNrcy5Ub1N0cmluZygpIH0pDQogICAgJHhtbCA9IE5ldy1PYmplY3QgV2luZG93cy5EYXRhLlhtbC5Eb20uWG1sRG9jdW1lbnQNCiAgICAkeG1sLkxvYWRYbWwoKE5ldy1SZW5hbWVUb2FzdFhtbCAtVG9rZW4gJHRva2VuIC1Jc1ByZXZpZXc6JElzUHJldmlldykpDQogICAgJHRvYXN0ID0gW1dpbmRvd3MuVUkuTm90aWZpY2F0aW9ucy5Ub2FzdE5vdGlmaWNhdGlvbl06Om5ldygkeG1sKQ0KICAgICR0b2FzdC5UYWcgPSAncmVuYW1lJw0KICAgICR0b2FzdC5Hcm91cCA9ICdkZXZpY2Utc2V0dXAnDQogICAgJHRvYXN0LkV4cGlyYXRpb25UaW1lID0gW0RhdGVUaW1lT2Zmc2V0XSRleHBpcmVzDQogICAgJHRvYXN0LkV4cGlyZXNPblJlYm9vdCA9ICR0cnVlDQogICAgJG5vdGlmaWVyID0gW1dpbmRvd3MuVUkuTm90aWZpY2F0aW9ucy5Ub2FzdE5vdGlmaWNhdGlvbk1hbmFnZXJdOjpDcmVhdGVUb2FzdE5vdGlmaWVyKCRzY3JpcHQ6QXBwSWQpDQogICAgaWYgKCRub3RpZmllci5TZXR0aW5nLlRvU3RyaW5nKCkgLW5lICdFbmFibGVkJykgeyB0aHJvdyAiVG9hc3Qgbm90aWZpY2F0aW9ucyB1bmF2YWlsYWJsZTogJCgkbm90aWZpZXIuU2V0dGluZykuIiB9DQogICAgJG5vdGlmaWVyLlNob3coJHRvYXN0KQ0KICAgIFdyaXRlLVRvYXN0TG9nICJUb2FzdCBzdWJtaXR0ZWQ7IHByZXZpZXc9JChbYm9vbF0kSXNQcmV2aWV3KTsgdGFyZ2V0PSQoJHN0YXRlLlRhcmdldCkuIg0KfQ0KDQpmdW5jdGlvbiBJbnZva2UtVG9hc3RBY3RpdmF0aW9uIHsNCiAgICBwYXJhbShbc3RyaW5nXSRVcmkpDQogICAgJGFjdGl2YXRpb24gPSBHZXQtVG9hc3RBY3RpdmF0aW9uIC1VcmkgJFVyaQ0KICAgIGlmICgkbnVsbCAtZXEgJGFjdGl2YXRpb24pIHsgdGhyb3cgJ1Vuc3VwcG9ydGVkIGFjdGl2YXRpb24gVVJJLicgfQ0KICAgICRyZWNvcmQgPSBSZWFkLVRvYXN0UmVjb3JkDQogICAgaWYgKCRudWxsIC1lcSAkcmVjb3JkIC1vciAkcmVjb3JkLlRva2VuIC1jbmUgJGFjdGl2YXRpb24uVG9rZW4pIHsgV3JpdGUtVG9hc3RMb2cgJ0lnbm9yaW5nIG9ic29sZXRlIHRvYXN0IHRva2VuLic7IHJldHVybiB9DQogICAgaWYgKCRhY3RpdmF0aW9uLkFjdGlvbiAtZXEgJ29wZW4nKSB7IFNob3ctUmVuYW1lVG9hc3QgLUlzUHJldmlldzooW2Jvb2xdJHJlY29yZC5QcmV2aWV3KTsgcmV0dXJuIH0NCiAgICAkc3RhdGUgPSBHZXQtVG9hc3ROYW1lU3RhdGUNCiAgICBpZiAoLW5vdCAoVGVzdC1SZXN0YXJ0QXV0aG9yaXphdGlvbiAtUmVjb3JkICRyZWNvcmQgLU5hbWVTdGF0ZSAkc3RhdGUgLVRva2VuICRhY3RpdmF0aW9uLlRva2VuKSkgew0KICAgICAgICBXcml0ZS1Ub2FzdExvZyAnUmVzdGFydCBpZ25vcmVkOiBwcmV2aWV3LCBleHBpcmVkL3VzZWQgdG9rZW4sIGNoYW5nZWQgbmFtZSwgb3IgcmVuYW1lIG5vIGxvbmdlciBwZW5kaW5nLicNCiAgICAgICAgUmVtb3ZlLVJlbmFtZVRvYXN0DQogICAgICAgIHJldHVybg0KICAgIH0NCiAgICAkcmVjb3JkLkNvbnN1bWVkID0gJHRydWUNCiAgICBTYXZlLVRvYXN0UmVjb3JkICRyZWNvcmQNCiAgICBXcml0ZS1Ub2FzdExvZyAnVXNlciBzZWxlY3RlZCBSZXN0YXJ0IG5vdy4gUmVxdWVzdGluZyByZXN0YXJ0IHdpdGhvdXQgZm9yY2UtY2xvc2luZyBhcHBsaWNhdGlvbnMuJw0KICAgICMgL3QgZ3JlYXRlciB0aGFuIHplcm8gaW1wbGllcyAvZi4gVXNlIC90IDAgYW5kIERPIE5PVCBhZGQgL2YuDQogICAgJHByb2Nlc3MgPSBTdGFydC1Qcm9jZXNzIC1GaWxlUGF0aCAoSm9pbi1QYXRoICRlbnY6V0lORElSICdTeXN0ZW0zMlxzaHV0ZG93bi5leGUnKSAtQXJndW1lbnRMaXN0IEAoJy9yJywnL3QnLCcwJykgLVdpbmRvd1N0eWxlIEhpZGRlbiAtV2FpdCAtUGFzc1RocnUNCiAgICBpZiAoJHByb2Nlc3MuRXhpdENvZGUgLW5lIDApIHsNCiAgICAgICAgJHJlY29yZC5Db25zdW1lZCA9ICRmYWxzZQ0KICAgICAgICBTYXZlLVRvYXN0UmVjb3JkICRyZWNvcmQNCiAgICAgICAgdGhyb3cgIlJlc3RhcnQgcmVxdWVzdCBmYWlsZWQgd2l0aCBleGl0IGNvZGUgJCgkcHJvY2Vzcy5FeGl0Q29kZSkuIFVzZSBTdGFydCA+IFBvd2VyID4gUmVzdGFydC4iDQogICAgfQ0KfQ0KDQpmdW5jdGlvbiBSZW1vdmUtVG9hc3RSZWdpc3RyYXRpb24gew0KICAgIFJlbW92ZS1SZW5hbWVUb2FzdA0KICAgIGZvcmVhY2ggKCRwYXRoIGluIEAoJHNjcmlwdDpVc2VyUm9vdCwgKCdIS0NVOlxTb2Z0d2FyZVxDbGFzc2VzXCcgKyAkc2NyaXB0OlByb3RvY29sKSwgKCdIS0NVOlxTb2Z0d2FyZVxDbGFzc2VzXEFwcFVzZXJNb2RlbElkXCcgKyAkc2NyaXB0OkFwcElkKSkpIHsNCiAgICAgICAgaWYgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJHBhdGgpIHsgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICRwYXRoIC1SZWN1cnNlIC1Gb3JjZSB9DQogICAgfQ0KICAgICRzaG9ydGN1dCA9IEpvaW4tUGF0aCAoW0Vudmlyb25tZW50XTo6R2V0Rm9sZGVyUGF0aCgnUHJvZ3JhbXMnKSkgJ0lUIERldmljZSBSZXN0YXJ0LmxuaycNCiAgICBpZiAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkc2hvcnRjdXQpIHsgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICRzaG9ydGN1dCAtRm9yY2UgfQ0KICAgIFdyaXRlLVRvYXN0TG9nICdSZW1vdmVkIHVzZXIgbm90aWZpY2F0aW9uIHJlZ2lzdHJhdGlvbi4nDQp9DQoNCiMgTUFJTjogVXNlci1zZXNzaW9uIGVudHJ5IHBvaW50LiBOZXZlciBydW4gdGhpcyBzY3JpcHQgYXMgU1lTVEVNLg0KJG11dGV4ID0gJG51bGwNCiRvd25lZCA9ICRmYWxzZQ0KdHJ5IHsNCiAgICBpZiAoJFBTVmVyc2lvblRhYmxlLlBTRWRpdGlvbiAtbmUgJ0Rlc2t0b3AnKSB7IHRocm93ICdVc2UgV2luZG93cyBQb3dlclNoZWxsIDUuMSwgbm90IFBvd2VyU2hlbGwgNy4nIH0NCiAgICBpZiAoLW5vdCBbRW52aXJvbm1lbnRdOjpJczY0Qml0UHJvY2VzcykgeyB0aHJvdyAnVXNlIDY0LWJpdCBXaW5kb3dzIFBvd2VyU2hlbGwuJyB9DQogICAgJHNpZCA9IFtTZWN1cml0eS5QcmluY2lwYWwuV2luZG93c0lkZW50aXR5XTo6R2V0Q3VycmVudCgpLlVzZXIuVmFsdWUNCiAgICBpZiAoJHNpZCAtZXEgJ1MtMS01LTE4JyAtb3IgW0RpYWdub3N0aWNzLlByb2Nlc3NdOjpHZXRDdXJyZW50UHJvY2VzcygpLlNlc3Npb25JZCAtZXEgMCkgeyB0aHJvdyAnQW4gaW50ZXJhY3RpdmUgdXNlciBzZXNzaW9uIGlzIHJlcXVpcmVkLicgfQ0KICAgICRtdXRleCA9IE5ldy1PYmplY3QgVGhyZWFkaW5nLk11dGV4KCRmYWxzZSwgKCdMb2NhbFxEZXZpY2VSZW5hbWVUb2FzdC0nICsgJHNpZCkpDQogICAgdHJ5IHsgJG93bmVkID0gJG11dGV4LldhaXRPbmUoNTAwMCkgfSBjYXRjaCBbVGhyZWFkaW5nLkFiYW5kb25lZE11dGV4RXhjZXB0aW9uXSB7ICRvd25lZCA9ICR0cnVlIH0NCiAgICBpZiAoLW5vdCAkb3duZWQpIHsgdGhyb3cgJ0Fub3RoZXIgcmVtaW5kZXIgYWN0aW9uIGlzIHN0aWxsIHJ1bm5pbmcuJyB9DQogICAgc3dpdGNoICgkTW9kZSkgew0KICAgICAgICAnU2hvdycgeyBTaG93LVJlbmFtZVRvYXN0IC1Jc1ByZXZpZXc6JFByZXZpZXcgfQ0KICAgICAgICAnQWN0aXZhdGUnIHsgSW52b2tlLVRvYXN0QWN0aXZhdGlvbiAtVXJpICRBY3RpdmF0aW9uVXJpIH0NCiAgICAgICAgJ0NsZWFudXAnIHsgUmVtb3ZlLVRvYXN0UmVnaXN0cmF0aW9uIH0NCiAgICB9DQogICAgZXhpdCAwDQp9IGNhdGNoIHsNCiAgICBXcml0ZS1Ub2FzdExvZyAiRkFJTEVEOiAkKCRfLkV4Y2VwdGlvbi5NZXNzYWdlKSINCiAgICBleGl0IDENCn0gZmluYWxseSB7DQogICAgaWYgKCRvd25lZCkgeyAkbXV0ZXguUmVsZWFzZU11dGV4KCkgfQ0KICAgIGlmICgkbnVsbCAtbmUgJG11dGV4KSB7ICRtdXRleC5EaXNwb3NlKCkgfQ0KfQ0K'
$script:ToastPayloadSha256 = 'D2813BF52C4D89F443EF33D4C9377DD1D0F7082E6A95B0872F61A1CD617E5B29'

function Write-NamingLog {
    param([string]$Message)
    # Never write log text to STDOUT: Intune parses that stream.
    try {
        $directory = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs'
        if (Test-Path -LiteralPath $directory) {
            $line = '{0} [{1}] {2}' -f [DateTime]::UtcNow.ToString('o'), $script:Component, $Message
            Add-Content -LiteralPath (Join-Path $directory 'DeviceRenameRemediation.log') -Value $line -Encoding UTF8 -ErrorAction Stop
        }
    } catch { }
}

function Get-ComputerNameState {
    $root = 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName'
    $active = [string](Get-ItemPropertyValue -LiteralPath "$root\ActiveComputerName" -Name ComputerName -ErrorAction Stop)
    $configured = [string](Get-ItemPropertyValue -LiteralPath "$root\ComputerName" -Name ComputerName -ErrorAction Stop)
    if ([string]::IsNullOrWhiteSpace($active) -or [string]::IsNullOrWhiteSpace($configured)) {
        throw 'Unable to read both computer-name registry values. Rename is blocked.'
    }
    [pscustomobject]@{
        ActiveName = $active
        ConfiguredName = $configured
        PendingRename = -not [string]::Equals($active, $configured, [StringComparison]::OrdinalIgnoreCase)
    }
}

function Test-GenericWindowsComputerName {
    param([AllowNull()][string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name.Length -gt 15) { return $false }
    # Eligibility is now based only on these whole-name patterns. The suffix
    # must contain one or more ASCII letters/digits; no fixed suffix length.
    return ($Name -imatch '\A(?:DESKTOP|LAPTOP)-[A-Z0-9]+\z')
}

function Test-NamingConvention {
    param([AllowNull()][string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name.Length -gt 15) { return $false }
    $types = ($script:AllowedDeviceTypes | ForEach-Object { [regex]::Escape($_) }) -join '|'
    # First initial + at least one surname character; optional TWO-character suffix.
    # Case-insensitive, whole-string match. Total length is checked separately.
    $pattern = '\A[A-Z][A-Z0-9]{1,8}-(?:' + $types + ')(?:-[A-Z0-9]{2})?\z'
    return ($Name -imatch $pattern)
}

function ConvertTo-NameToken {
    param([Parameter(Mandatory)][string]$Text)
    $builder = New-Object System.Text.StringBuilder
    foreach ($character in $Text.Normalize([Text.NormalizationForm]::FormD).ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($character) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$builder.Append($character)
        }
    }
    return ($builder.ToString().ToUpperInvariant() -replace '[^A-Z0-9]', '')
}

function Get-UserNamePrefix {
    param([AllowNull()][string]$Account)
    if ([string]::IsNullOrWhiteSpace($Account)) { throw 'No console user is signed in.' }
    $leaf = ($Account -split '\\')[-1]
    $leaf = ($leaf -split '@', 2)[0]
    $parts = @($leaf -split '\.')
    # Do not guess a surname from first.middle.last or a display-name account.
    if ($parts.Count -ne 2 -or $parts[0] -notmatch "\A[\p{L}\p{M}'-]+\z" -or $parts[1] -notmatch "\A[\p{L}\p{M}0-9'-]+\z") {
        throw 'The console account must use first.last or first.last@domain. Configure another authoritative name source for other formats.'
    }
    $first = ConvertTo-NameToken -Text $parts[0]
    $last = ConvertTo-NameToken -Text $parts[1]
    if ($first -notmatch '\A[A-Z]' -or $last -notmatch '\A[A-Z]') {
        throw 'Cannot build an ASCII first initial and surname from this account.'
    }
    return ($first.Substring(0, 1) + $last)
}

function Get-ComputerChassisType {
    param([Parameter(Mandatory)]$ComputerSystem)
    if ($ComputerSystem.Model -match 'Virtual|VMware|KVM|VirtualBox|Hyper-V' -or
        $ComputerSystem.Manufacturer -match 'VMware|QEMU|Xen') { return 'VM' }
    # Role 2 is a standalone server, which the original -ge 3 check missed.
    if ([int]$ComputerSystem.DomainRole -ge 2) { return 'SRV' }
    $types = @(Get-CimInstance -ClassName Win32_SystemEnclosure -ErrorAction Stop | ForEach-Object { $_.ChassisTypes })
    # Evaluate the complete array before returning. 12/18/21 are NOT laptop types.
    if (@($types | Where-Object { $_ -in 8, 9, 10, 11, 14, 30, 31, 32 }).Count -gt 0) { return 'LT' }
    if (@($types | Where-Object { $_ -in 3, 4, 5, 6, 7, 13, 15, 16, 35, 36 }).Count -gt 0) { return 'DT' }
    return 'PC'
}

function New-CompliantComputerName {
    param(
        [Parameter(Mandatory)][string]$Prefix,
        [Parameter(Mandatory)][ValidateSet('LT','DT','VM','SRV','PC')][string]$DeviceType,
        [switch]$NoRandomSuffix
    )
    $tail = '-' + $DeviceType.ToUpperInvariant()
    if (-not $NoRandomSuffix) {
        $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
        $randomPart = -join (1..2 | ForEach-Object { $alphabet[(Get-Random -Minimum 0 -Maximum $alphabet.Length)] })
        $tail += '-' + $randomPart
    }
    # Nine is the business cap; a three-character SRV token can require eight.
    $maximumPrefix = [Math]::Min(9, (15 - $tail.Length))
    if ($Prefix.Length -lt 2 -or $Prefix -notmatch '\A[A-Z][A-Z0-9]+\z') { throw 'Invalid user-name prefix.' }
    $prefixLength = [Math]::Min($Prefix.Length, $maximumPrefix)
    $name = $Prefix.Substring(0, $prefixLength).ToUpperInvariant() + $tail
    if (-not (Test-NamingConvention -Name $name)) { throw "Generated name '$name' failed validation." }
    return $name
}

function Initialize-SessionDiscovery {
    if ('DeviceNaming.SessionDiscovery' -as [type]) { return }
    # Discover active users only; notification display runs in their scheduled task.
    Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace DeviceNaming {
    public class UserSession {
        public int Id;
        public string Account;
    }
    public static class SessionDiscovery {
        [StructLayout(LayoutKind.Sequential)]
        private struct SessionInfo {
            public int SessionId;
            public IntPtr StationName;
            public int State;
        }
        [DllImport("wtsapi32.dll", EntryPoint="WTSEnumerateSessionsW", ExactSpelling=true, SetLastError=true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool Enumerate(IntPtr server, int reserved, int version, out IntPtr sessions, out int count);
        [DllImport("wtsapi32.dll", EntryPoint="WTSQuerySessionInformationW", ExactSpelling=true, SetLastError=true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool Query(IntPtr server, int id, int infoClass, out IntPtr data, out int bytes);
        [DllImport("wtsapi32.dll", EntryPoint="WTSFreeMemory", ExactSpelling=true)]
        private static extern void Free(IntPtr data);
        private static string QueryText(int id, int infoClass) {
            IntPtr data = IntPtr.Zero;
            int bytes;
            try {
                if (!Query(IntPtr.Zero, id, infoClass, out data, out bytes))
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                return data == IntPtr.Zero ? "" : Marshal.PtrToStringUni(data);
            } finally { if (data != IntPtr.Zero) Free(data); }
        }
        public static UserSession[] ActiveUsers() {
            IntPtr data = IntPtr.Zero;
            int count;
            var result = new List<UserSession>();
            try {
                if (!Enumerate(IntPtr.Zero, 0, 1, out data, out count))
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                int size = Marshal.SizeOf(typeof(SessionInfo));
                for (int index = 0; index < count; index++) {
                    var info = (SessionInfo)Marshal.PtrToStructure(IntPtr.Add(data, index * size), typeof(SessionInfo));
                    if (info.State != 0 || info.SessionId == 0) continue;
                    // Sessions can disappear between enumeration and query.
                    try {
                        string user = QueryText(info.SessionId, 5);
                        if (String.IsNullOrWhiteSpace(user)) continue;
                        string domain = QueryText(info.SessionId, 7);
                        result.Add(new UserSession { Id=info.SessionId, Account=domain + "\\" + user });
                    } catch (Win32Exception) { }
                }
            } finally { if (data != IntPtr.Zero) Free(data); }
            return result.ToArray();
        }
    }
}
'@ | Out-Null
}

function Get-RebootToastPayloadPath {
    # Program Files supplies an admin/SYSTEM-writable location readable by users.
    $directory = Join-Path $env:ProgramFiles 'DeviceRenameRemediation'
    if (-not (Test-Path -LiteralPath $directory)) { [void](New-Item -Path $directory -ItemType Directory -ErrorAction Stop) }
    $item = Get-Item -LiteralPath $directory -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Notification directory must not be a reparse point.' }
    $path = Join-Path $directory 'User-RebootToast.ps1'
    if (Test-Path -LiteralPath $path) {
        $item = Get-Item -LiteralPath $path -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Notification script must not be a reparse point.' }
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $script:ToastPayloadSha256) { return $path }
    }
    $bytes = [Convert]::FromBase64String($script:ToastPayloadBase64)
    $temporary = Join-Path $directory ([Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllBytes($temporary, $bytes)
        if ((Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash -ne $script:ToastPayloadSha256) { throw 'Embedded toast payload integrity check failed.' }
        Move-Item -LiteralPath $temporary -Destination $path -Force -ErrorAction Stop
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
    return $path
}

function Resolve-NotificationUserSid {
    param([Parameter(Mandatory)][string]$Account)
    $identity = New-Object Security.Principal.NTAccount($Account)
    return $identity.Translate([Security.Principal.SecurityIdentifier]).Value
}

function Register-RebootToastTask {
    param([Parameter(Mandatory)][string]$UserSid, [Parameter(Mandatory)][string]$ScriptPath)
    if ($UserSid -notmatch '\AS-1-\d+(?:-\d+)+\z' -or $UserSid -eq 'S-1-5-18') { throw 'Invalid interactive user SID.' }
    $taskName = 'DeviceRename-RebootToast-' + $UserSid
    $powerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = '-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Mode Show' -f $ScriptPath
    $action = New-ScheduledTaskAction -Execute $powerShell -Argument $arguments
    $principal = New-ScheduledTaskPrincipal -UserId $UserSid -LogonType Interactive -RunLevel Limited
    $trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddSeconds(15))
    $trigger.EndBoundary = (Get-Date).AddMinutes(10).ToString('s')
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 2) -MultipleInstances IgnoreNew -DeleteExpiredTaskAfter (New-TimeSpan -Hours 1)
    [void](Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Display one pending-rename toast as the signed-in user; Snooze is handled by Windows.' -Force -ErrorAction Stop)
    return $taskName
}

function Show-PendingRenameReminder {
    param([Parameter(Mandatory)]$NameState, [switch]$ForceReminder)
    if (-not $NameState.PendingRename) { return }
    try {
        Initialize-SessionDiscovery
        $sessions = @([DeviceNaming.SessionDiscovery]::ActiveUsers())
        if ($sessions.Count -eq 0) { Write-NamingLog 'Pending rename; no active user for the toast task.'; return }
        $key = Join-Path $script:StateRoot 'Notifications'
        if (-not (Test-Path -LiteralPath $script:StateRoot)) { [void](New-Item -Path $script:StateRoot -ErrorAction Stop) }
        if (-not (Test-Path -LiteralPath $key)) { [void](New-Item -Path $key -ErrorAction Stop) }
        $seen = @{}
        foreach ($session in $sessions) {
            try {
                $sid = Resolve-NotificationUserSid -Account $session.Account
                if ($seen.ContainsKey($sid)) { continue }
                $seen[$sid] = $true
                $valueName = 'User_' + $sid
                # Missing history is expected on first run. Read the key's
                # existing properties instead of requesting a nonexistent value.
                $properties = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
                $property = $properties.PSObject.Properties[$valueName]
                $previous = $null
                if ($null -ne $property -and $property.Value) {
                    try { $previous = $property.Value | ConvertFrom-Json -ErrorAction Stop } catch { $previous = $null }
                }
                if (-not $ForceReminder -and $null -ne $previous -and
                    $previous.Version -eq $script:NotificationVersion -and
                    $previous.Target -ieq $NameState.ConfiguredName -and $previous.Active -ieq $NameState.ActiveName) {
                    # One launch per user/name change. Do not override their Snooze
                    # selection with a fresh toast on each Intune evaluation.
                    continue
                }
                $path = Get-RebootToastPayloadPath
                $taskName = Register-RebootToastTask -UserSid $sid -ScriptPath $path
                $record = @{ Version=$script:NotificationVersion; Account=$session.Account; Sid=$sid; Target=$NameState.ConfiguredName; Active=$NameState.ActiveName; Utc=[DateTime]::UtcNow.ToString('o'); TaskName=$taskName } | ConvertTo-Json -Compress
                [void](New-ItemProperty -LiteralPath $key -Name $valueName -Value $record -PropertyType String -Force -ErrorAction Stop)
                Write-NamingLog "Queued one-time user toast task '$taskName'. Check the user's Toast.log for display status."
            } catch { Write-NamingLog "Could not schedule/store a toast for session $($session.Id): $($_.Exception.Message)" }
        }
    } catch { Write-NamingLog "Reboot toast scheduling unavailable: $($_.Exception.Message)" }
}

function Get-RenameEligibility {
    param([Parameter(Mandatory)]$NameState)
    if ($NameState.PendingRename) {
        return [pscustomobject]@{ Eligible=$false; Reason='A computer rename is already pending.'; Prefix=$null; System=$null }
    }
    if (-not (Test-GenericWindowsComputerName -Name $NameState.ActiveName)) {
        return [pscustomobject]@{ Eligible=$false; Reason='Current name is not DESKTOP-/LAPTOP- with an alphanumeric suffix; leave unchanged.'; Prefix=$null; System=$null }
    }
    $system = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    if ($system.PartOfDomain) {
        return [pscustomobject]@{ Eligible=$false; Reason='AD domain-joined computer excluded; this package does not supply domain credentials.'; Prefix=$null; System=$system }
    }
    try { $prefix = Get-UserNamePrefix -Account $system.UserName }
    catch { return [pscustomobject]@{ Eligible=$false; Reason=$_.Exception.Message; Prefix=$null; System=$system } }
    return [pscustomobject]@{ Eligible=$true; Reason='Generic Windows computer name found and console account is usable.'; Prefix=$prefix; System=$system }
}

function Save-RenameReceipt {
    param([Parameter(Mandatory)][string]$TargetName)
    # A single JSON value avoids partially committed detection properties.
    $record = @{ Schema=1; TargetName=$TargetName; AppliedUtc=[DateTime]::UtcNow.ToString('o') } | ConvertTo-Json -Compress
    if (-not (Test-Path -LiteralPath $script:StateRoot)) { [void](New-Item -Path $script:StateRoot -ErrorAction Stop) }
    [void](New-ItemProperty -LiteralPath $script:StateRoot -Name Receipt -Value $record -PropertyType String -Force -ErrorAction Stop)
}

# MAIN: A verified receipt plus the current/configured target detects this app.
# Pre-existing compliant devices have no receipt and are NOT detected as installed.
try {
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw 'Configure detection to run as a 64-bit process.' }
    $state = Get-ComputerNameState
    # Detection may be evaluated without requirements. Use the same once-per-user record here
    # so a pending rename can still prompt, without launching the same toast again.
    Show-PendingRenameReminder -NameState $state
    if (-not (Test-Path -LiteralPath $script:StateRoot)) { exit 1 }
    $raw = Get-ItemPropertyValue -LiteralPath $script:StateRoot -Name Receipt -ErrorAction Stop
    $receipt = $raw | ConvertFrom-Json -ErrorAction Stop
    if ($receipt.Schema -ne 1 -or -not (Test-NamingConvention -Name $receipt.TargetName)) { exit 1 }
    # ConfiguredName is authoritative during a pending rename. Do not detect an
    # old receipt just because ActiveName still matches a now-replaced target.
    if ($state.ConfiguredName -ieq $receipt.TargetName) {
        Write-Output ('Rename applied: ' + $receipt.TargetName)
        exit 0
    }
    exit 1
} catch {
    Write-NamingLog "Detection not satisfied: $($_.Exception.Message)"
    exit 1
}

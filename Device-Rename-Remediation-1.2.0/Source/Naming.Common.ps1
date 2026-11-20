#requires -Version 5.1
# Shared implementation for the installer. Intune upload scripts contain their
# own embedded copy, because Intune runs them outside this package directory.
# If changing these settings, also update both scripts in the Intune folder.
$script:StateRoot = 'HKLM:\SOFTWARE\DeviceRenameRemediation'
$script:AllowedDeviceTypes = @('LT', 'DT', 'VM', 'SRV', 'PC')
$script:NotificationVersion = '1.1.0'
# Embedded payload is regenerated from User-RebootToast.ps1 by Build-UploadScripts.ps1.
$script:ToastPayloadBase64 = '77u/I3JlcXVpcmVzIC1WZXJzaW9uIDUuMQ0KPCMgUnVucyBvbmx5IGluIHRoZSBpbnRlcmFjdGl2ZSB1c2VyJ3MgV2luZG93cyBQb3dlclNoZWxsIDUuMSBzZXNzaW9uLg0KICAgU2hvdyBzdWJtaXRzIG9uZSBuYXRpdmUgdG9hc3QgYW5kIGV4aXRzLiBXaW5kb3dzIGltcGxlbWVudHMgU25vb3plLg0KICAgQWN0aXZhdGUgaGFuZGxlcyBvbmx5IHRoZSBleGFjdCBwcm90b2NvbCByb3V0ZXMgYW5kIGN1cnJlbnQgcmFuZG9tIHRva2VuLg0KICAgQ2xlYW51cCByZW1vdmVzIHRoaXMgdXNlcidzIHRvYXN0IHJlZ2lzdHJhdGlvbiBhbmQgc2hvcnRjdXQsIG5vdCB0aGUgbmFtZS4NCiM+DQpbQ21kbGV0QmluZGluZygpXQ0KcGFyYW0oDQogICAgW1ZhbGlkYXRlU2V0KCdTaG93JywnQWN0aXZhdGUnLCdDbGVhbnVwJyldW3N0cmluZ10kTW9kZSA9ICdTaG93JywNCiAgICBbc3RyaW5nXSRBY3RpdmF0aW9uVXJpLA0KICAgIFtzd2l0Y2hdJFByZXZpZXcsDQogICAgW3N0cmluZ10kRXhwZWN0ZWRTaWQsDQogICAgW2ludF0kRXhwZWN0ZWRTZXNzaW9uSWQNCikNCiRFcnJvckFjdGlvblByZWZlcmVuY2UgPSAnU3RvcCcNCiRzY3JpcHQ6QXBwSWQgPSAnRGV2aWNlUmVuYW1lUmVtZWRpYXRpb24uUmVib290Jw0KJHNjcmlwdDpQcm90b2NvbCA9ICdkZXZpY2VyZW5hbWUtcmVib290Jw0KJHNjcmlwdDpVc2VyUm9vdCA9ICdIS0NVOlxTb2Z0d2FyZVxEZXZpY2VSZW5hbWVSZW1lZGlhdGlvblxUb2FzdCcNCiRzY3JpcHQ6RGlzcGxheU5hbWUgPSAnSVQgRGV2aWNlIFNldHVwJw0KJHNjcmlwdDpUb2FzdFN0YWdlID0gJ3N0YXJ0aW5nIHVzZXIgaGVscGVyJw0KDQpmdW5jdGlvbiBXcml0ZS1Ub2FzdExvZyB7DQogICAgcGFyYW0oW3N0cmluZ10kTWVzc2FnZSkNCiAgICB0cnkgew0KICAgICAgICAkZGlyZWN0b3J5ID0gSm9pbi1QYXRoICRlbnY6TE9DQUxBUFBEQVRBICdEZXZpY2VSZW5hbWVSZW1lZGlhdGlvbicNCiAgICAgICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJGRpcmVjdG9yeSkpIHsgW3ZvaWRdKE5ldy1JdGVtIC1QYXRoICRkaXJlY3RvcnkgLUl0ZW1UeXBlIERpcmVjdG9yeSkgfQ0KICAgICAgICBBZGQtQ29udGVudCAtTGl0ZXJhbFBhdGggKEpvaW4tUGF0aCAkZGlyZWN0b3J5ICdUb2FzdC5sb2cnKSAtRW5jb2RpbmcgVVRGOCAtVmFsdWUgKCIkKFtEYXRlVGltZV06OlV0Y05vdy5Ub1N0cmluZygnbycpKSBidWlsZD0xLjIuMyBwaWQ9JFBJRCBtb2RlPSRNb2RlICRNZXNzYWdlIikNCiAgICB9IGNhdGNoIHsgfQ0KfQ0KDQpmdW5jdGlvbiBHZXQtVG9hc3ROYW1lU3RhdGUgew0KICAgICRrZXkgPSAnSEtMTTpcU1lTVEVNXEN1cnJlbnRDb250cm9sU2V0XENvbnRyb2xcQ29tcHV0ZXJOYW1lJw0KICAgICRhY3RpdmUgPSBbc3RyaW5nXShHZXQtSXRlbVByb3BlcnR5VmFsdWUgLUxpdGVyYWxQYXRoICIka2V5XEFjdGl2ZUNvbXB1dGVyTmFtZSIgLU5hbWUgQ29tcHV0ZXJOYW1lIC1FcnJvckFjdGlvbiBTdG9wKQ0KICAgICR0YXJnZXQgPSBbc3RyaW5nXShHZXQtSXRlbVByb3BlcnR5VmFsdWUgLUxpdGVyYWxQYXRoICIka2V5XENvbXB1dGVyTmFtZSIgLU5hbWUgQ29tcHV0ZXJOYW1lIC1FcnJvckFjdGlvbiBTdG9wKQ0KICAgIGlmIChbc3RyaW5nXTo6SXNOdWxsT3JXaGl0ZVNwYWNlKCRhY3RpdmUpIC1vciBbc3RyaW5nXTo6SXNOdWxsT3JXaGl0ZVNwYWNlKCR0YXJnZXQpKSB7IHRocm93ICdDb21wdXRlci1uYW1lIHN0YXRlIGlzIHVuYXZhaWxhYmxlLicgfQ0KICAgIFtwc2N1c3RvbW9iamVjdF1AeyBBY3RpdmU9JGFjdGl2ZTsgVGFyZ2V0PSR0YXJnZXQ7IFBlbmRpbmc9KCRhY3RpdmUgLWluZSAkdGFyZ2V0KSB9DQp9DQoNCmZ1bmN0aW9uIFJlYWQtVG9hc3RSZWNvcmQgew0KICAgIGlmICgtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRzY3JpcHQ6VXNlclJvb3QpKSB7IHJldHVybiAkbnVsbCB9DQogICAgJHByb3BlcnRpZXMgPSBHZXQtSXRlbVByb3BlcnR5IC1MaXRlcmFsUGF0aCAkc2NyaXB0OlVzZXJSb290IC1FcnJvckFjdGlvbiBTdG9wDQogICAgJHZhbHVlID0gJHByb3BlcnRpZXMuUFNPYmplY3QuUHJvcGVydGllc1snQ3VycmVudCddDQogICAgaWYgKCRudWxsIC1lcSAkdmFsdWUgLW9yIFtzdHJpbmddOjpJc051bGxPcldoaXRlU3BhY2UoW3N0cmluZ10kdmFsdWUuVmFsdWUpKSB7IHJldHVybiAkbnVsbCB9DQogICAgdHJ5IHsgcmV0dXJuICgkdmFsdWUuVmFsdWUgfCBDb252ZXJ0RnJvbS1Kc29uIC1FcnJvckFjdGlvbiBTdG9wKSB9IGNhdGNoIHsgcmV0dXJuICRudWxsIH0NCn0NCg0KZnVuY3Rpb24gU2F2ZS1Ub2FzdFJlY29yZCB7DQogICAgcGFyYW0oW1BhcmFtZXRlcihNYW5kYXRvcnkpXSRSZWNvcmQpDQogICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJHNjcmlwdDpVc2VyUm9vdCkpIHsgW3ZvaWRdKE5ldy1JdGVtIC1QYXRoICRzY3JpcHQ6VXNlclJvb3QgLUZvcmNlKSB9DQogICAgW3ZvaWRdKE5ldy1JdGVtUHJvcGVydHkgLUxpdGVyYWxQYXRoICRzY3JpcHQ6VXNlclJvb3QgLU5hbWUgQ3VycmVudCAtUHJvcGVydHlUeXBlIFN0cmluZyAtVmFsdWUgKCRSZWNvcmQgfCBDb252ZXJ0VG8tSnNvbiAtQ29tcHJlc3MpIC1Gb3JjZSkNCn0NCg0KZnVuY3Rpb24gVGVzdC1SZXN0YXJ0QXV0aG9yaXphdGlvbiB7DQogICAgcGFyYW0oJFJlY29yZCwgJE5hbWVTdGF0ZSwgW3N0cmluZ10kVG9rZW4sIFtsb25nXSROb3dUaWNrcyA9IFtEYXRlVGltZV06OlV0Y05vdy5UaWNrcykNCiAgICBpZiAoJG51bGwgLWVxICRSZWNvcmQgLW9yICRudWxsIC1lcSAkTmFtZVN0YXRlKSB7IHJldHVybiAkZmFsc2UgfQ0KICAgIGlmICgkVG9rZW4gLWNub3RtYXRjaCAnXEFbYS1mMC05XXszMn1ceicgLW9yICRSZWNvcmQuVG9rZW4gLWNuZSAkVG9rZW4pIHsgcmV0dXJuICRmYWxzZSB9DQogICAgaWYgKCRSZWNvcmQuUHJldmlldyAtbmUgJGZhbHNlIC1vciAkUmVjb3JkLkNvbnN1bWVkIC1uZSAkZmFsc2UpIHsgcmV0dXJuICRmYWxzZSB9DQogICAgJGV4cGlyZXMgPSBbbG9uZ10wDQogICAgaWYgKC1ub3QgW2xvbmddOjpUcnlQYXJzZShbc3RyaW5nXSRSZWNvcmQuRXhwaXJlc1RpY2tzLCBbcmVmXSRleHBpcmVzKSAtb3IgJGV4cGlyZXMgLWxlICROb3dUaWNrcykgeyByZXR1cm4gJGZhbHNlIH0NCiAgICByZXR1cm4gKCROYW1lU3RhdGUuUGVuZGluZyAtYW5kICROYW1lU3RhdGUuQWN0aXZlIC1pZXEgJFJlY29yZC5BY3RpdmUgLWFuZCAkTmFtZVN0YXRlLlRhcmdldCAtaWVxICRSZWNvcmQuVGFyZ2V0KQ0KfQ0KDQpmdW5jdGlvbiBHZXQtVG9hc3RBY3RpdmF0aW9uIHsNCiAgICBwYXJhbShbc3RyaW5nXSRVcmkpDQogICAgIyBObyBhcmJpdHJhcnkgY29tbWFuZCwgcGF0aCwgYXJndW1lbnRzLCBvciBVUkkgcXVlcnkgaXMgZXZlciBleGVjdXRlZC4NCiAgICBpZiAoJFVyaSAtY21hdGNoICdcQWRldmljZXJlbmFtZS1yZWJvb3Q6Ly8ocmVzdGFydHxvcGVuKS8oW2EtZjAtOV17MzJ9KS8/XHonKSB7DQogICAgICAgIHJldHVybiBbcHNjdXN0b21vYmplY3RdQHsgQWN0aW9uPSRNYXRjaGVzWzFdOyBUb2tlbj0kTWF0Y2hlc1syXSB9DQogICAgfQ0KICAgIHJldHVybiAkbnVsbA0KfQ0KDQpmdW5jdGlvbiBOZXctUmVuYW1lVG9hc3RYbWwgew0KICAgIHBhcmFtKFtQYXJhbWV0ZXIoTWFuZGF0b3J5KV1bc3RyaW5nXSRUb2tlbiwgW3N3aXRjaF0kSXNQcmV2aWV3KQ0KICAgIGlmICgkVG9rZW4gLWNub3RtYXRjaCAnXEFbYS1mMC05XXszMn1ceicpIHsgdGhyb3cgJ0ludmFsaWQgdG9hc3QgdG9rZW4uJyB9DQogICAgJHRpdGxlID0gJ1Jlc3RhcnQgcmVxdWlyZWQnDQogICAgJGJvZHkgPSAnWW91ciBQQyBuZWVkcyBhIHJlc3RhcnQgdG8gZmluaXNoIGEgZGV2aWNlLW5hbWUgdXBkYXRlLiBTYXZlIHlvdXIgd29yayBiZWZvcmUgY2hvb3NpbmcgUmVzdGFydCBub3cuJw0KICAgIGlmICgkSXNQcmV2aWV3KSB7ICR0aXRsZSA9ICdQcmV2aWV3OiByZXN0YXJ0IHJlbWluZGVyJzsgJGJvZHkgPSAnVGhpcyBpcyBhIHRlc3Qgbm90aWZpY2F0aW9uLiBSZXN0YXJ0IG5vdyBpcyBkaXNhYmxlZCBpbiB0aGlzIHByZXZpZXc7IFNub296ZSBjYW4gYmUgdGVzdGVkIG5vcm1hbGx5LicgfQ0KICAgICR0aXRsZSA9IFtTZWN1cml0eS5TZWN1cml0eUVsZW1lbnRdOjpFc2NhcGUoJHRpdGxlKQ0KICAgICRib2R5ID0gW1NlY3VyaXR5LlNlY3VyaXR5RWxlbWVudF06OkVzY2FwZSgkYm9keSkNCiAgICByZXR1cm4gQCINCjx0b2FzdCBzY2VuYXJpbz0icmVtaW5kZXIiIGFjdGl2YXRpb25UeXBlPSJwcm90b2NvbCIgbGF1bmNoPSJkZXZpY2VyZW5hbWUtcmVib290Oi8vb3Blbi8kVG9rZW4iPg0KICA8dmlzdWFsPjxiaW5kaW5nIHRlbXBsYXRlPSJUb2FzdEdlbmVyaWMiPjx0ZXh0PiR0aXRsZTwvdGV4dD48dGV4dD4kYm9keTwvdGV4dD48L2JpbmRpbmc+PC92aXN1YWw+DQogIDxhY3Rpb25zPg0KICAgIDxpbnB1dCBpZD0ic25vb3plVGltZSIgdHlwZT0ic2VsZWN0aW9uIiB0aXRsZT0iUmVtaW5kIG1lIGluIiBkZWZhdWx0SW5wdXQ9IjE1Ij4NCiAgICAgIDxzZWxlY3Rpb24gaWQ9IjE1IiBjb250ZW50PSIxNSBtaW51dGVzIiAvPg0KICAgICAgPHNlbGVjdGlvbiBpZD0iNjAiIGNvbnRlbnQ9IjEgaG91ciIgLz4NCiAgICAgIDxzZWxlY3Rpb24gaWQ9IjI0MCIgY29udGVudD0iNCBob3VycyIgLz4NCiAgICA8L2lucHV0Pg0KICAgIDxhY3Rpb24gY29udGVudD0iU25vb3plIiBhY3RpdmF0aW9uVHlwZT0ic3lzdGVtIiBhcmd1bWVudHM9InNub296ZSIgaGludC1pbnB1dElkPSJzbm9vemVUaW1lIiAvPg0KICAgIDxhY3Rpb24gY29udGVudD0iUmVzdGFydCBub3ciIGFjdGl2YXRpb25UeXBlPSJwcm90b2NvbCIgYXJndW1lbnRzPSJkZXZpY2VyZW5hbWUtcmVib290Oi8vcmVzdGFydC8kVG9rZW4iIC8+DQogIDwvYWN0aW9ucz4NCiAgPGF1ZGlvIHNyYz0ibXMtd2luc291bmRldmVudDpOb3RpZmljYXRpb24uRGVmYXVsdCIgLz4NCjwvdG9hc3Q+DQoiQA0KfQ0KDQpmdW5jdGlvbiBJbml0aWFsaXplLVNob3J0Y3V0SW50ZXJvcCB7DQogICAgaWYgKCdEZXZpY2VSZW5hbWVUb2FzdC5TaG9ydGN1dFByb3BlcnRpZXMnIC1hcyBbdHlwZV0pIHsgcmV0dXJuIH0NCiAgICBBZGQtVHlwZSAtRXJyb3JBY3Rpb24gU3RvcCAtVHlwZURlZmluaXRpb24gQCcNCnVzaW5nIFN5c3RlbTsNCnVzaW5nIFN5c3RlbS5SdW50aW1lLkludGVyb3BTZXJ2aWNlczsNCm5hbWVzcGFjZSBEZXZpY2VSZW5hbWVUb2FzdCB7DQogICAgW1N0cnVjdExheW91dChMYXlvdXRLaW5kLlNlcXVlbnRpYWwpXQ0KICAgIHB1YmxpYyBzdHJ1Y3QgUHJvcGVydHlLZXkgeyBwdWJsaWMgR3VpZCBGb3JtYXRJZDsgcHVibGljIHVpbnQgSWQ7IH0NCiAgICBbU3RydWN0TGF5b3V0KExheW91dEtpbmQuRXhwbGljaXQsIFNpemU9MjQpXQ0KICAgIHB1YmxpYyBzdHJ1Y3QgUHJvcFZhcmlhbnQgew0KICAgICAgICBbRmllbGRPZmZzZXQoMCldIHB1YmxpYyB1c2hvcnQgVHlwZTsNCiAgICAgICAgW0ZpZWxkT2Zmc2V0KDgpXSBwdWJsaWMgSW50UHRyIFBvaW50ZXI7DQogICAgfQ0KICAgIFtDb21JbXBvcnQsIEd1aWQoIjg4NkQ4RUVCLThDRjItNDQ0Ni04RDAyLUNEQkExREJEQ0Y5OSIpLCBJbnRlcmZhY2VUeXBlKENvbUludGVyZmFjZVR5cGUuSW50ZXJmYWNlSXNJVW5rbm93bildDQogICAgcHVibGljIGludGVyZmFjZSBJUHJvcGVydHlTdG9yZSB7DQogICAgICAgIFtQcmVzZXJ2ZVNpZ10gaW50IEdldENvdW50KG91dCB1aW50IGNvdW50KTsNCiAgICAgICAgW1ByZXNlcnZlU2lnXSBpbnQgR2V0QXQodWludCBpbmRleCwgb3V0IFByb3BlcnR5S2V5IGtleSk7DQogICAgICAgIFtQcmVzZXJ2ZVNpZ10gaW50IEdldFZhbHVlKHJlZiBQcm9wZXJ0eUtleSBrZXksIG91dCBQcm9wVmFyaWFudCB2YWx1ZSk7DQogICAgICAgIFtQcmVzZXJ2ZVNpZ10gaW50IFNldFZhbHVlKHJlZiBQcm9wZXJ0eUtleSBrZXksIHJlZiBQcm9wVmFyaWFudCB2YWx1ZSk7DQogICAgICAgIFtQcmVzZXJ2ZVNpZ10gaW50IENvbW1pdCgpOw0KICAgIH0NCiAgICBwdWJsaWMgc3RhdGljIGNsYXNzIFNob3J0Y3V0UHJvcGVydGllcyB7DQogICAgICAgIFtEbGxJbXBvcnQoInNoZWxsMzIuZGxsIiwgQ2hhclNldD1DaGFyU2V0LlVuaWNvZGUsIEV4YWN0U3BlbGxpbmc9dHJ1ZSldDQogICAgICAgIHByaXZhdGUgc3RhdGljIGV4dGVybiBpbnQgU0hHZXRQcm9wZXJ0eVN0b3JlRnJvbVBhcnNpbmdOYW1lKHN0cmluZyBwYXRoLCBJbnRQdHIgYmluZGluZywNCiAgICAgICAgICAgIHVpbnQgZmxhZ3MsIHJlZiBHdWlkIGludGVyZmFjZUlkLCBvdXQgSVByb3BlcnR5U3RvcmUgc3RvcmUpOw0KICAgICAgICBbRGxsSW1wb3J0KCJvbGUzMi5kbGwiLCBFeGFjdFNwZWxsaW5nPXRydWUpXQ0KICAgICAgICBwcml2YXRlIHN0YXRpYyBleHRlcm4gaW50IFByb3BWYXJpYW50Q2xlYXIocmVmIFByb3BWYXJpYW50IHZhbHVlKTsNCiAgICAgICAgcHVibGljIHN0YXRpYyB2b2lkIFNldChzdHJpbmcgc2hvcnRjdXQsIHN0cmluZyBhcHBJZCwgc3RyaW5nIGFjdGl2YXRvcklkKSB7DQogICAgICAgICAgICBHdWlkIGlpZCA9IHR5cGVvZihJUHJvcGVydHlTdG9yZSkuR1VJRDsNCiAgICAgICAgICAgIElQcm9wZXJ0eVN0b3JlIHN0b3JlOw0KICAgICAgICAgICAgTWFyc2hhbC5UaHJvd0V4Y2VwdGlvbkZvckhSKFNIR2V0UHJvcGVydHlTdG9yZUZyb21QYXJzaW5nTmFtZShzaG9ydGN1dCwgSW50UHRyLlplcm8sIDIsIHJlZiBpaWQsIG91dCBzdG9yZSkpOw0KICAgICAgICAgICAgdHJ5IHsNCiAgICAgICAgICAgICAgICB2YXIga2V5ID0gbmV3IFByb3BlcnR5S2V5IHsgRm9ybWF0SWQ9bmV3IEd1aWQoIjlGNEMyODU1LTlGNzktNEIzOS1BOEQwLUUxRDQyREUxRDVGMyIpLCBJZD01IH07DQogICAgICAgICAgICAgICAgdmFyIHZhbHVlID0gbmV3IFByb3BWYXJpYW50IHsgVHlwZT0zMSwgUG9pbnRlcj1NYXJzaGFsLlN0cmluZ1RvQ29UYXNrTWVtVW5pKGFwcElkKSB9Ow0KICAgICAgICAgICAgICAgIHRyeSB7IE1hcnNoYWwuVGhyb3dFeGNlcHRpb25Gb3JIUihzdG9yZS5TZXRWYWx1ZShyZWYga2V5LCByZWYgdmFsdWUpKTsgfQ0KICAgICAgICAgICAgICAgIGZpbmFsbHkgeyBQcm9wVmFyaWFudENsZWFyKHJlZiB2YWx1ZSk7IH0NCiAgICAgICAgICAgICAgICAvLyBBIHN0dWIgQ0xTSUQgcGVybWl0cyBwcm90b2NvbC1hY3RpdmF0ZWQgbm90aWZpY2F0aW9ucyB0byBwZXJzaXN0Lg0KICAgICAgICAgICAgICAgIGtleS5JZCA9IDI2Ow0KICAgICAgICAgICAgICAgIHZhbHVlID0gbmV3IFByb3BWYXJpYW50IHsgVHlwZT03MiwgUG9pbnRlcj1NYXJzaGFsLkFsbG9jQ29UYXNrTWVtKDE2KSB9Ow0KICAgICAgICAgICAgICAgIHRyeSB7DQogICAgICAgICAgICAgICAgICAgIE1hcnNoYWwuQ29weShuZXcgR3VpZChhY3RpdmF0b3JJZCkuVG9CeXRlQXJyYXkoKSwgMCwgdmFsdWUuUG9pbnRlciwgMTYpOw0KICAgICAgICAgICAgICAgICAgICBNYXJzaGFsLlRocm93RXhjZXB0aW9uRm9ySFIoc3RvcmUuU2V0VmFsdWUocmVmIGtleSwgcmVmIHZhbHVlKSk7DQogICAgICAgICAgICAgICAgfSBmaW5hbGx5IHsgUHJvcFZhcmlhbnRDbGVhcihyZWYgdmFsdWUpOyB9DQogICAgICAgICAgICAgICAgTWFyc2hhbC5UaHJvd0V4Y2VwdGlvbkZvckhSKHN0b3JlLkNvbW1pdCgpKTsNCiAgICAgICAgICAgIH0gZmluYWxseSB7IE1hcnNoYWwuUmVsZWFzZUNvbU9iamVjdChzdG9yZSk7IH0NCiAgICAgICAgfQ0KICAgIH0NCn0NCidAIHwgT3V0LU51bGwNCn0NCg0KZnVuY3Rpb24gUmVnaXN0ZXItVG9hc3RJZGVudGl0eSB7DQogICAgJHNjcmlwdDpUb2FzdFN0YWdlID0gJ3JlZ2lzdGVyIG5vdGlmaWNhdGlvbiBpZGVudGl0eScNCiAgICBJbml0aWFsaXplLVNob3J0Y3V0SW50ZXJvcA0KICAgICRwb3dlclNoZWxsID0gSm9pbi1QYXRoICRlbnY6V0lORElSICdTeXN0ZW0zMlxXaW5kb3dzUG93ZXJTaGVsbFx2MS4wXHBvd2Vyc2hlbGwuZXhlJw0KICAgICRzY3JpcHRQYXRoID0gJFBTQ29tbWFuZFBhdGgNCiAgICAkY29tbWFuZCA9ICciezB9IiAtTm9Mb2dvIC1Ob1Byb2ZpbGUgLU5vbkludGVyYWN0aXZlIC1XaW5kb3dTdHlsZSBIaWRkZW4gLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgInsxfSIgLU1vZGUgQWN0aXZhdGUgLUFjdGl2YXRpb25VcmkgIiUxIicgLWYgJHBvd2VyU2hlbGwsICRzY3JpcHRQYXRoDQogICAgJHByb3RvY29sS2V5ID0gJ0hLQ1U6XFNvZnR3YXJlXENsYXNzZXNcJyArICRzY3JpcHQ6UHJvdG9jb2wNCiAgICBmb3JlYWNoICgkcGF0aCBpbiBAKCRwcm90b2NvbEtleSwgIiRwcm90b2NvbEtleVxzaGVsbCIsICIkcHJvdG9jb2xLZXlcc2hlbGxcb3BlbiIsICIkcHJvdG9jb2xLZXlcc2hlbGxcb3Blblxjb21tYW5kIikpIHsNCiAgICAgICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJHBhdGgpKSB7IFt2b2lkXShOZXctSXRlbSAtUGF0aCAkcGF0aCAtRm9yY2UpIH0NCiAgICB9DQogICAgU2V0LUl0ZW0gLUxpdGVyYWxQYXRoICRwcm90b2NvbEtleSAtVmFsdWUgJ1VSTDpEZXZpY2UgcmVuYW1lIHJlc3RhcnQgcmVtaW5kZXInDQogICAgW3ZvaWRdKE5ldy1JdGVtUHJvcGVydHkgLUxpdGVyYWxQYXRoICRwcm90b2NvbEtleSAtTmFtZSAnVVJMIFByb3RvY29sJyAtUHJvcGVydHlUeXBlIFN0cmluZyAtVmFsdWUgJycgLUZvcmNlKQ0KICAgIFNldC1JdGVtIC1MaXRlcmFsUGF0aCAiJHByb3RvY29sS2V5XHNoZWxsXG9wZW5cY29tbWFuZCIgLVZhbHVlICRjb21tYW5kDQogICAgJGlkZW50aXR5ID0gJ0hLQ1U6XFNvZnR3YXJlXENsYXNzZXNcQXBwVXNlck1vZGVsSWRcJyArICRzY3JpcHQ6QXBwSWQNCiAgICBpZiAoLW5vdCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkaWRlbnRpdHkpKSB7IFt2b2lkXShOZXctSXRlbSAtUGF0aCAkaWRlbnRpdHkgLUZvcmNlKSB9DQogICAgW3ZvaWRdKE5ldy1JdGVtUHJvcGVydHkgLUxpdGVyYWxQYXRoICRpZGVudGl0eSAtTmFtZSBEaXNwbGF5TmFtZSAtUHJvcGVydHlUeXBlIFN0cmluZyAtVmFsdWUgJHNjcmlwdDpEaXNwbGF5TmFtZSAtRm9yY2UpDQogICAgJHNjcmlwdDpUb2FzdFN0YWdlID0gJ2NyZWF0ZSBTdGFydCBtZW51IHNob3J0Y3V0Jw0KICAgICRzaG9ydGN1dFBhdGggPSBKb2luLVBhdGggKFtFbnZpcm9ubWVudF06OkdldEZvbGRlclBhdGgoJ1Byb2dyYW1zJykpICdJVCBEZXZpY2UgUmVzdGFydC5sbmsnDQogICAgJHNoZWxsID0gTmV3LU9iamVjdCAtQ29tT2JqZWN0IFdTY3JpcHQuU2hlbGwNCiAgICBpZiAoJG51bGwgLWVxICRzaGVsbCkgeyB0aHJvdyAnV1NjcmlwdC5TaGVsbCByZXR1cm5lZCBubyBDT00gb2JqZWN0LicgfQ0KICAgICRzaG9ydGN1dCA9ICRudWxsDQogICAgdHJ5IHsNCiAgICAgICAgJHNob3J0Y3V0ID0gJHNoZWxsLkNyZWF0ZVNob3J0Y3V0KCRzaG9ydGN1dFBhdGgpDQogICAgICAgIGlmICgkbnVsbCAtZXEgJHNob3J0Y3V0KSB7IHRocm93ICJXU2NyaXB0LlNoZWxsIHJldHVybmVkIG5vIHNob3J0Y3V0IGZvciAkc2hvcnRjdXRQYXRoLiIgfQ0KICAgICAgICAkc2hvcnRjdXQuVGFyZ2V0UGF0aCA9ICRwb3dlclNoZWxsDQogICAgICAgICRzaG9ydGN1dC5Bcmd1bWVudHMgPSAnLU5vTG9nbyAtTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtV2luZG93U3R5bGUgSGlkZGVuIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICJ7MH0iIC1Nb2RlIFNob3cnIC1mICRzY3JpcHRQYXRoDQogICAgICAgICRzaG9ydGN1dC5EZXNjcmlwdGlvbiA9ICdTaG93IHRoZSBwZW5kaW5nIGNvbXB1dGVyIHJlbmFtZSByZXN0YXJ0IHJlbWluZGVyJw0KICAgICAgICAkc2hvcnRjdXQuSWNvbkxvY2F0aW9uID0gIiRlbnY6V0lORElSXFN5c3RlbTMyXHNoZWxsMzIuZGxsLDIzOCINCiAgICAgICAgJHNob3J0Y3V0LlNhdmUoKQ0KICAgIH0gZmluYWxseSB7DQogICAgICAgIGlmICgkbnVsbCAtbmUgJHNob3J0Y3V0KSB7IFt2b2lkXVtSdW50aW1lLkludGVyb3BTZXJ2aWNlcy5NYXJzaGFsXTo6UmVsZWFzZUNvbU9iamVjdCgkc2hvcnRjdXQpIH0NCiAgICAgICAgW3ZvaWRdW1J1bnRpbWUuSW50ZXJvcFNlcnZpY2VzLk1hcnNoYWxdOjpSZWxlYXNlQ29tT2JqZWN0KCRzaGVsbCkNCiAgICB9DQogICAgJHNjcmlwdDpUb2FzdFN0YWdlID0gJ3NldCBzaG9ydGN1dCBub3RpZmljYXRpb24gaWRlbnRpdHknDQogICAgW0RldmljZVJlbmFtZVRvYXN0LlNob3J0Y3V0UHJvcGVydGllc106OlNldCgkc2hvcnRjdXRQYXRoLCAkc2NyaXB0OkFwcElkLCAnRjRCRDkxQjEtNEVENS00RTE4LTlCMkUtNkY4RjlCRjc4ODU2JykNCn0NCg0KZnVuY3Rpb24gSW5pdGlhbGl6ZS1Ub2FzdFJ1bnRpbWUgew0KICAgIFt2b2lkXVtXaW5kb3dzLlVJLk5vdGlmaWNhdGlvbnMuVG9hc3ROb3RpZmljYXRpb25NYW5hZ2VyLCBXaW5kb3dzLlVJLk5vdGlmaWNhdGlvbnMsIENvbnRlbnRUeXBlPVdpbmRvd3NSdW50aW1lXQ0KICAgIFt2b2lkXVtXaW5kb3dzLlVJLk5vdGlmaWNhdGlvbnMuVG9hc3ROb3RpZmljYXRpb24sIFdpbmRvd3MuVUkuTm90aWZpY2F0aW9ucywgQ29udGVudFR5cGU9V2luZG93c1J1bnRpbWVdDQogICAgW3ZvaWRdW1dpbmRvd3MuRGF0YS5YbWwuRG9tLlhtbERvY3VtZW50LCBXaW5kb3dzLkRhdGEuWG1sLkRvbS5YbWxEb2N1bWVudCwgQ29udGVudFR5cGU9V2luZG93c1J1bnRpbWVdDQp9DQoNCmZ1bmN0aW9uIFJlbW92ZS1SZW5hbWVUb2FzdCB7DQogICAgdHJ5IHsgSW5pdGlhbGl6ZS1Ub2FzdFJ1bnRpbWU7IFtXaW5kb3dzLlVJLk5vdGlmaWNhdGlvbnMuVG9hc3ROb3RpZmljYXRpb25NYW5hZ2VyXTo6SGlzdG9yeS5DbGVhcigkc2NyaXB0OkFwcElkKSB9IGNhdGNoIHsgV3JpdGUtVG9hc3RMb2cgIkNsZWFyIHRvYXN0OiAkKCRfLkV4Y2VwdGlvbi5NZXNzYWdlKSIgfQ0KfQ0KDQpmdW5jdGlvbiBTZW5kLVJlbmFtZVRvYXN0IHsNCiAgICBwYXJhbSgkTm90aWZpZXIsICRUb2FzdCkNCiAgICBpZiAoJG51bGwgLWVxICROb3RpZmllcikgeyB0aHJvdyAiV2luZG93cyByZXR1cm5lZCBubyB0b2FzdCBub3RpZmllciBmb3IgJHNjcmlwdDpBcHBJZC4iIH0NCiAgICBpZiAoJG51bGwgLWVxICRUb2FzdCkgeyB0aHJvdyAnV2luZG93cyByZXR1cm5lZCBubyB0b2FzdCBub3RpZmljYXRpb24gb2JqZWN0LicgfQ0KICAgICRzY3JpcHQ6VG9hc3RTdGFnZSA9ICdyZWFkIG5vdGlmaWNhdGlvbiBzZXR0aW5nJw0KICAgICRzZXR0aW5nID0gJE5vdGlmaWVyLlNldHRpbmcNCiAgICBpZiAoJG51bGwgLWVxICRzZXR0aW5nKSB7DQogICAgICAgIFdyaXRlLVRvYXN0TG9nICdOb3RpZmljYXRpb24gc2V0dGluZyB1bmF2YWlsYWJsZS4gU3VibWl0dGluZyB0aHJvdWdoIHRoZSBXaW5kb3dzIG5vdGlmaWVyLicNCiAgICB9IGVsc2VpZiAoW3N0cmluZ10kc2V0dGluZyAtbm90aW4gJ0VuYWJsZWQnLCcwJykgew0KICAgICAgICB0aHJvdyAiV2luZG93cyBub3RpZmljYXRpb24gc2V0dGluZyBmb3IgJHNjcmlwdDpBcHBJZCBpcyAkc2V0dGluZy4iDQogICAgfQ0KICAgICRzY3JpcHQ6VG9hc3RTdGFnZSA9ICdzdWJtaXQgdG9hc3QgdG8gV2luZG93cycNCiAgICAkTm90aWZpZXIuU2hvdygkVG9hc3QpDQp9DQoNCmZ1bmN0aW9uIFNob3ctUmVuYW1lVG9hc3Qgew0KICAgIHBhcmFtKFtzd2l0Y2hdJElzUHJldmlldykNCiAgICAkc2NyaXB0OlRvYXN0U3RhZ2UgPSAncmVhZCBjb21wdXRlciBuYW1lIHN0YXRlJw0KICAgICRzdGF0ZSA9IEdldC1Ub2FzdE5hbWVTdGF0ZQ0KICAgIGlmICgtbm90ICRzdGF0ZS5QZW5kaW5nIC1hbmQgLW5vdCAkSXNQcmV2aWV3KSB7DQogICAgICAgIFJlbW92ZS1SZW5hbWVUb2FzdA0KICAgICAgICBXcml0ZS1Ub2FzdExvZyAnTm8gcGVuZGluZyBjb21wdXRlciByZW5hbWU7IG5vdGhpbmcgdG8gZGlzcGxheS4nDQogICAgICAgIHJldHVybg0KICAgIH0NCiAgICBSZWdpc3Rlci1Ub2FzdElkZW50aXR5DQogICAgJHNjcmlwdDpUb2FzdFN0YWdlID0gJ2xvYWQgV2luZG93cyBub3RpZmljYXRpb24gdHlwZXMnDQogICAgSW5pdGlhbGl6ZS1Ub2FzdFJ1bnRpbWUNCiAgICAkdG9rZW4gPSBbR3VpZF06Ok5ld0d1aWQoKS5Ub1N0cmluZygnTicpDQogICAgJGV4cGlyZXMgPSBbRGF0ZVRpbWVdOjpVdGNOb3cuQWRkRGF5cygxKQ0KICAgICRzY3JpcHQ6VG9hc3RTdGFnZSA9ICdzYXZlIGFjdGl2YXRpb24gcmVjb3JkJw0KICAgIFNhdmUtVG9hc3RSZWNvcmQgKFtwc2N1c3RvbW9iamVjdF1AeyBUb2tlbj0kdG9rZW47IEFjdGl2ZT0kc3RhdGUuQWN0aXZlOyBUYXJnZXQ9JHN0YXRlLlRhcmdldDsgUHJldmlldz1bYm9vbF0kSXNQcmV2aWV3OyBDb25zdW1lZD0kZmFsc2U7IEV4cGlyZXNUaWNrcz0kZXhwaXJlcy5UaWNrcy5Ub1N0cmluZygpIH0pDQogICAgJHNjcmlwdDpUb2FzdFN0YWdlID0gJ2J1aWxkIHRvYXN0IFhNTCcNCiAgICAkeG1sID0gW1dpbmRvd3MuRGF0YS5YbWwuRG9tLlhtbERvY3VtZW50XTo6bmV3KCkNCiAgICBpZiAoJG51bGwgLWVxICR4bWwpIHsgdGhyb3cgJ1dpbmRvd3MgcmV0dXJuZWQgbm8gWE1MIGRvY3VtZW50LicgfQ0KICAgICR4bWwuTG9hZFhtbCgoTmV3LVJlbmFtZVRvYXN0WG1sIC1Ub2tlbiAkdG9rZW4gLUlzUHJldmlldzokSXNQcmV2aWV3KSkNCiAgICAkdG9hc3QgPSBbV2luZG93cy5VSS5Ob3RpZmljYXRpb25zLlRvYXN0Tm90aWZpY2F0aW9uXTo6bmV3KCR4bWwpDQogICAgaWYgKCRudWxsIC1lcSAkdG9hc3QpIHsgdGhyb3cgJ1dpbmRvd3MgcmV0dXJuZWQgbm8gdG9hc3Qgbm90aWZpY2F0aW9uIG9iamVjdC4nIH0NCiAgICAkdG9hc3QuVGFnID0gJ3JlbmFtZScNCiAgICAkdG9hc3QuR3JvdXAgPSAnZGV2aWNlLXNldHVwJw0KICAgICR0b2FzdC5FeHBpcmF0aW9uVGltZSA9IFtEYXRlVGltZU9mZnNldF0kZXhwaXJlcw0KICAgICR0b2FzdC5FeHBpcmVzT25SZWJvb3QgPSAkdHJ1ZQ0KICAgICRzY3JpcHQ6VG9hc3RTdGFnZSA9ICdjcmVhdGUgV2luZG93cyBub3RpZmllcicNCiAgICAkbm90aWZpZXIgPSBbV2luZG93cy5VSS5Ob3RpZmljYXRpb25zLlRvYXN0Tm90aWZpY2F0aW9uTWFuYWdlcl06OkNyZWF0ZVRvYXN0Tm90aWZpZXIoJHNjcmlwdDpBcHBJZCkNCiAgICBTZW5kLVJlbmFtZVRvYXN0IC1Ob3RpZmllciAkbm90aWZpZXIgLVRvYXN0ICR0b2FzdA0KICAgIFdyaXRlLVRvYXN0TG9nICJUb2FzdCBzdWJtaXR0ZWQ7IHByZXZpZXc9JChbYm9vbF0kSXNQcmV2aWV3KTsgdGFyZ2V0PSQoJHN0YXRlLlRhcmdldCkuIg0KfQ0KDQpmdW5jdGlvbiBJbnZva2UtVG9hc3RBY3RpdmF0aW9uIHsNCiAgICBwYXJhbShbc3RyaW5nXSRVcmkpDQogICAgJGFjdGl2YXRpb24gPSBHZXQtVG9hc3RBY3RpdmF0aW9uIC1VcmkgJFVyaQ0KICAgIGlmICgkbnVsbCAtZXEgJGFjdGl2YXRpb24pIHsgdGhyb3cgJ1Vuc3VwcG9ydGVkIGFjdGl2YXRpb24gVVJJLicgfQ0KICAgICRyZWNvcmQgPSBSZWFkLVRvYXN0UmVjb3JkDQogICAgaWYgKCRudWxsIC1lcSAkcmVjb3JkIC1vciAkcmVjb3JkLlRva2VuIC1jbmUgJGFjdGl2YXRpb24uVG9rZW4pIHsgV3JpdGUtVG9hc3RMb2cgJ0lnbm9yaW5nIG9ic29sZXRlIHRvYXN0IHRva2VuLic7IHJldHVybiB9DQogICAgaWYgKCRhY3RpdmF0aW9uLkFjdGlvbiAtZXEgJ29wZW4nKSB7IFNob3ctUmVuYW1lVG9hc3QgLUlzUHJldmlldzooW2Jvb2xdJHJlY29yZC5QcmV2aWV3KTsgcmV0dXJuIH0NCiAgICAkc3RhdGUgPSBHZXQtVG9hc3ROYW1lU3RhdGUNCiAgICBpZiAoLW5vdCAoVGVzdC1SZXN0YXJ0QXV0aG9yaXphdGlvbiAtUmVjb3JkICRyZWNvcmQgLU5hbWVTdGF0ZSAkc3RhdGUgLVRva2VuICRhY3RpdmF0aW9uLlRva2VuKSkgew0KICAgICAgICBXcml0ZS1Ub2FzdExvZyAnUmVzdGFydCBpZ25vcmVkOiBwcmV2aWV3LCBleHBpcmVkL3VzZWQgdG9rZW4sIGNoYW5nZWQgbmFtZSwgb3IgcmVuYW1lIG5vIGxvbmdlciBwZW5kaW5nLicNCiAgICAgICAgUmVtb3ZlLVJlbmFtZVRvYXN0DQogICAgICAgIHJldHVybg0KICAgIH0NCiAgICAkcmVjb3JkLkNvbnN1bWVkID0gJHRydWUNCiAgICBTYXZlLVRvYXN0UmVjb3JkICRyZWNvcmQNCiAgICBXcml0ZS1Ub2FzdExvZyAnVXNlciBzZWxlY3RlZCBSZXN0YXJ0IG5vdy4gUmVxdWVzdGluZyByZXN0YXJ0IHdpdGhvdXQgZm9yY2UtY2xvc2luZyBhcHBsaWNhdGlvbnMuJw0KICAgICMgL3QgZ3JlYXRlciB0aGFuIHplcm8gaW1wbGllcyAvZi4gVXNlIC90IDAgYW5kIERPIE5PVCBhZGQgL2YuDQogICAgJHByb2Nlc3MgPSBTdGFydC1Qcm9jZXNzIC1GaWxlUGF0aCAoSm9pbi1QYXRoICRlbnY6V0lORElSICdTeXN0ZW0zMlxzaHV0ZG93bi5leGUnKSAtQXJndW1lbnRMaXN0IEAoJy9yJywnL3QnLCcwJykgLVdpbmRvd1N0eWxlIEhpZGRlbiAtV2FpdCAtUGFzc1RocnUNCiAgICBpZiAoJHByb2Nlc3MuRXhpdENvZGUgLW5lIDApIHsNCiAgICAgICAgJHJlY29yZC5Db25zdW1lZCA9ICRmYWxzZQ0KICAgICAgICBTYXZlLVRvYXN0UmVjb3JkICRyZWNvcmQNCiAgICAgICAgdGhyb3cgIlJlc3RhcnQgcmVxdWVzdCBmYWlsZWQgd2l0aCBleGl0IGNvZGUgJCgkcHJvY2Vzcy5FeGl0Q29kZSkuIFVzZSBTdGFydCA+IFBvd2VyID4gUmVzdGFydC4iDQogICAgfQ0KfQ0KDQpmdW5jdGlvbiBSZW1vdmUtVG9hc3RSZWdpc3RyYXRpb24gew0KICAgIFJlbW92ZS1SZW5hbWVUb2FzdA0KICAgIGZvcmVhY2ggKCRwYXRoIGluIEAoJHNjcmlwdDpVc2VyUm9vdCwgKCdIS0NVOlxTb2Z0d2FyZVxDbGFzc2VzXCcgKyAkc2NyaXB0OlByb3RvY29sKSwgKCdIS0NVOlxTb2Z0d2FyZVxDbGFzc2VzXEFwcFVzZXJNb2RlbElkXCcgKyAkc2NyaXB0OkFwcElkKSkpIHsNCiAgICAgICAgaWYgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJHBhdGgpIHsgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICRwYXRoIC1SZWN1cnNlIC1Gb3JjZSB9DQogICAgfQ0KICAgICRzaG9ydGN1dCA9IEpvaW4tUGF0aCAoW0Vudmlyb25tZW50XTo6R2V0Rm9sZGVyUGF0aCgnUHJvZ3JhbXMnKSkgJ0lUIERldmljZSBSZXN0YXJ0LmxuaycNCiAgICBpZiAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkc2hvcnRjdXQpIHsgUmVtb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICRzaG9ydGN1dCAtRm9yY2UgfQ0KICAgIFdyaXRlLVRvYXN0TG9nICdSZW1vdmVkIHVzZXIgbm90aWZpY2F0aW9uIHJlZ2lzdHJhdGlvbi4nDQp9DQoNCiMgTUFJTjogVXNlci1zZXNzaW9uIGVudHJ5IHBvaW50LiBOZXZlciBydW4gdGhpcyBzY3JpcHQgYXMgU1lTVEVNLg0KJG11dGV4ID0gJG51bGwNCiRvd25lZCA9ICRmYWxzZQ0KdHJ5IHsNCiAgICBpZiAoJFBTVmVyc2lvblRhYmxlLlBTRWRpdGlvbiAtbmUgJ0Rlc2t0b3AnKSB7IHRocm93ICdVc2UgV2luZG93cyBQb3dlclNoZWxsIDUuMSwgbm90IFBvd2VyU2hlbGwgNy4nIH0NCiAgICBpZiAoLW5vdCBbRW52aXJvbm1lbnRdOjpJczY0Qml0UHJvY2VzcykgeyB0aHJvdyAnVXNlIDY0LWJpdCBXaW5kb3dzIFBvd2VyU2hlbGwuJyB9DQogICAgJHNpZCA9IFtTZWN1cml0eS5QcmluY2lwYWwuV2luZG93c0lkZW50aXR5XTo6R2V0Q3VycmVudCgpLlVzZXIuVmFsdWUNCiAgICBpZiAoJHNpZCAtZXEgJ1MtMS01LTE4JyAtb3IgW0RpYWdub3N0aWNzLlByb2Nlc3NdOjpHZXRDdXJyZW50UHJvY2VzcygpLlNlc3Npb25JZCAtZXEgMCkgeyB0aHJvdyAnQW4gaW50ZXJhY3RpdmUgdXNlciBzZXNzaW9uIGlzIHJlcXVpcmVkLicgfQ0KICAgIGlmICgoJEV4cGVjdGVkU2lkIC1hbmQgJEV4cGVjdGVkU2lkIC1uZSAkc2lkKSAtb3INCiAgICAgICAgKCRFeHBlY3RlZFNlc3Npb25JZCAtYW5kICRFeHBlY3RlZFNlc3Npb25JZCAtbmUgW0RpYWdub3N0aWNzLlByb2Nlc3NdOjpHZXRDdXJyZW50UHJvY2VzcygpLlNlc3Npb25JZCkpIHsNCiAgICAgICAgdGhyb3cgJ1RoZSBzY2hlZHVsZWQgcmVtaW5kZXIgcmVhY2hlZCBhIGRpZmZlcmVudCB1c2VyIG9yIHNlc3Npb24uJw0KICAgIH0NCiAgICBXcml0ZS1Ub2FzdExvZyAiU3RhcnRlZCBzZXNzaW9uPSQoW0RpYWdub3N0aWNzLlByb2Nlc3NdOjpHZXRDdXJyZW50UHJvY2VzcygpLlNlc3Npb25JZCkgcHJldmlldz0kKFtib29sXSRQcmV2aWV3KS4iDQogICAgJHNjcmlwdDpUb2FzdFN0YWdlID0gJ2FjcXVpcmUgcmVtaW5kZXIgbXV0ZXgnDQogICAgJG11dGV4ID0gW1RocmVhZGluZy5NdXRleF06Om5ldygkZmFsc2UsICgnTG9jYWxcRGV2aWNlUmVuYW1lVG9hc3QtJyArICRzaWQpKQ0KICAgIHRyeSB7ICRvd25lZCA9ICRtdXRleC5XYWl0T25lKDUwMDApIH0gY2F0Y2ggW1RocmVhZGluZy5BYmFuZG9uZWRNdXRleEV4Y2VwdGlvbl0geyAkb3duZWQgPSAkdHJ1ZSB9DQogICAgaWYgKC1ub3QgJG93bmVkKSB7IHRocm93ICdBbm90aGVyIHJlbWluZGVyIGFjdGlvbiBpcyBzdGlsbCBydW5uaW5nLicgfQ0KICAgICRzY3JpcHQ6VG9hc3RTdGFnZSA9ICRNb2RlDQogICAgc3dpdGNoICgkTW9kZSkgew0KICAgICAgICAnU2hvdycgeyBTaG93LVJlbmFtZVRvYXN0IC1Jc1ByZXZpZXc6JFByZXZpZXcgfQ0KICAgICAgICAnQWN0aXZhdGUnIHsgSW52b2tlLVRvYXN0QWN0aXZhdGlvbiAtVXJpICRBY3RpdmF0aW9uVXJpIH0NCiAgICAgICAgJ0NsZWFudXAnIHsgUmVtb3ZlLVRvYXN0UmVnaXN0cmF0aW9uIH0NCiAgICB9DQogICAgZXhpdCAwDQp9IGNhdGNoIHsNCiAgICAkZmFpbHVyZSA9ICRfDQogICAgJHdoZXJlID0gJGZhaWx1cmUuSW52b2NhdGlvbkluZm8NCiAgICBXcml0ZS1Ub2FzdExvZyAoIkZBSUxFRCBzdGFnZT1bezB9XSBmaWxlPVt7MX1dIGxpbmU9ezJ9IGVycm9ySWQ9W3szfV0gbWVzc2FnZT1bezR9XSBzdGFjaz1bezV9XSIgLWYNCiAgICAgICAgJHNjcmlwdDpUb2FzdFN0YWdlLCAkd2hlcmUuU2NyaXB0TmFtZSwgJHdoZXJlLlNjcmlwdExpbmVOdW1iZXIsICRmYWlsdXJlLkZ1bGx5UXVhbGlmaWVkRXJyb3JJZCwNCiAgICAgICAgJGZhaWx1cmUuRXhjZXB0aW9uLk1lc3NhZ2UsICgkZmFpbHVyZS5TY3JpcHRTdGFja1RyYWNlIC1yZXBsYWNlICdbXHJcbl0rJywgJyB8ICcpKQ0KICAgIGV4aXQgMQ0KfSBmaW5hbGx5IHsNCiAgICBpZiAoJG93bmVkKSB7ICRtdXRleC5SZWxlYXNlTXV0ZXgoKSB9DQogICAgaWYgKCRudWxsIC1uZSAkbXV0ZXgpIHsgJG11dGV4LkRpc3Bvc2UoKSB9DQp9DQo='
$script:ToastPayloadSha256 = '9E80C0854C9B785EF8D682BDEE8335079DC5BCFF41437F00DEF357EC857CA468'

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

function Format-RenameNameState {
    param([Parameter(Mandatory)]$NameState)
    $active = $NameState.ActiveName
    $configured = $NameState.ConfiguredName
    $codes = ($active.ToCharArray() | ForEach-Object { 'U+{0:X4}' -f [int]$_ }) -join ' '
    $generic = Test-GenericWindowsComputerName -Name $active
    return ("build=1.2.3 pid={0} x64={1} active=[{2}] length={3} units=[{4}] configured=[{5}] pending={6} generic={7} processName=[{8}]" -f
        $PID, [Environment]::Is64BitProcess, $active, $active.Length, $codes, $configured, $NameState.PendingRename, $generic, $env:COMPUTERNAME)
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
        [DllImport("wtsapi32.dll", SetLastError=true, ExactSpelling=true)]
        private static extern bool WTSQueryUserToken(int sessionId, out IntPtr token);
        [DllImport("kernel32.dll", SetLastError=true, ExactSpelling=true)]
        private static extern bool CloseHandle(IntPtr handle);
        public static string GetSessionSid(int sessionId) {
            IntPtr token;
            if (!WTSQueryUserToken(sessionId, out token))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            try {
                using (var identity = new System.Security.Principal.WindowsIdentity(token))
                    return identity.User.Value;
            } finally { CloseHandle(token); }
        }
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
    param([ValidateRange(1,2147483647)][int]$SessionId)
    if ([Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
        return [DeviceNaming.SessionDiscovery]::GetSessionSid($SessionId)
    }
    # An elevated pilot shell can have different credentials from the desktop user.
    $shells = Get-CimInstance Win32_Process -Filter "Name='explorer.exe' AND SessionId=$SessionId" -ErrorAction Stop
    $owners = @(foreach ($shell in $shells) {
        $owner = Invoke-CimMethod -InputObject $shell -MethodName GetOwnerSid -ErrorAction Stop
        if ($owner.ReturnValue -eq 0 -and $owner.Sid) { $owner.Sid }
    })
    $unique = @($owners | Sort-Object -Unique)
    if ($unique.Count -ne 1) { throw "No unique Explorer owner SID for session $SessionId. Run the pilot check as SYSTEM." }
    return $unique[0]
}

function Start-RebootToastTaskInSession {
    param([string]$TaskName, [int]$SessionId)
    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    $task = $service.GetFolder('\').GetTask($TaskName)
    # TASK_RUN_USE_SESSION_ID. Omit user credentials to use the session's user.
    $run = $task.RunEx($null, 4, $SessionId, $null)
    if (!$run -or !$run.InstanceGuid) { throw "Scheduler returned no running instance for $TaskName." }
}

function Register-RebootToastTask {
    param([Parameter(Mandatory)][string]$UserSid, [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$SessionId)
    if ($UserSid -notmatch '\AS-1-\d+(?:-\d+)+\z' -or $UserSid -in 'S-1-5-18','S-1-5-19','S-1-5-20') { throw 'Invalid interactive user SID.' }
    $taskName = 'DeviceRename-RebootToast-' + $UserSid
    $powerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = '-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Mode Show -ExpectedSid {1} -ExpectedSessionId {2}' -f $ScriptPath, $UserSid, $SessionId
    $action = New-ScheduledTaskAction -Execute $powerShell -Argument $arguments
    $principal = New-ScheduledTaskPrincipal -GroupId 'S-1-5-32-545' -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 2) -MultipleInstances IgnoreNew
    try {
        [void](Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Description 'Show the pending rename reminder once in the selected interactive session.' -Force -ErrorAction Stop)
    } catch { throw "Register-ScheduledTask group=BUILTIN Users failed. $($_.Exception.Message)" }
    try {
        Start-RebootToastTaskInSession -TaskName $taskName -SessionId $SessionId
    } catch { throw "RunEx session=$SessionId failed. $($_.Exception.Message)" }
    return $taskName
}

function Show-PendingRenameReminder {
    param([Parameter(Mandatory)]$NameState, [switch]$ForceReminder, [switch]$ReportFailures)
    if (-not $NameState.PendingRename) { return }
    try {
        Write-NamingLog "build=1.2.3 checking reboot reminder for $($NameState.ActiveName) -> $($NameState.ConfiguredName)."
        Initialize-SessionDiscovery
        $sessions = @([DeviceNaming.SessionDiscovery]::ActiveUsers())
        if ($sessions.Count -eq 0) {
            $message = 'Pending rename; no active user for the toast task.'
            if ($ReportFailures) { throw $message }
            Write-NamingLog $message
            return
        }
        $key = Join-Path $script:StateRoot 'Notifications'
        if (-not (Test-Path -LiteralPath $script:StateRoot)) { [void](New-Item -Path $script:StateRoot -ErrorAction Stop) }
        if (-not (Test-Path -LiteralPath $key)) { [void](New-Item -Path $key -ErrorAction Stop) }
        $failures = @()
        $seen = @{}
        foreach ($session in $sessions) {
            try {
                $stage = 'reading session SID'
                $sid = Resolve-NotificationUserSid -SessionId $session.Id
                $stage = "reading reminder history for $sid"
                if ($seen.ContainsKey($sid)) { continue }
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
                    # Respect a successful/snoozed launch. Retry a confirmed failure of an older helper once.
                    if ($previous.PayloadSha256 -eq $script:ToastPayloadSha256) { continue }
                    $expectedTask = 'DeviceRename-RebootToast-' + $sid
                    if ($previous.TaskName -ne $expectedTask) { continue }
                    try {
                        $info = Get-ScheduledTaskInfo -TaskPath '\' -TaskName $expectedTask -ErrorAction Stop
                    } catch { continue }
                    if ($null -eq $info -or $info.LastTaskResult -ne 1) { continue }
                    Write-NamingLog "Retrying previous helper exit 1 for $sid with build 1.2.3."
                }
                $stage = 'staging user helper'
                $path = Get-RebootToastPayloadPath
                $stage = "scheduling task for SID $sid"
                $taskName = Register-RebootToastTask -UserSid $sid -ScriptPath $path -SessionId $session.Id
                $seen[$sid] = $true
                $stage = 'saving notification history'
                $record = @{ Version=$script:NotificationVersion; PayloadSha256=$script:ToastPayloadSha256; Account=$session.Account; Sid=$sid; Target=$NameState.ConfiguredName; Active=$NameState.ActiveName; Utc=[DateTime]::UtcNow.ToString('o'); TaskName=$taskName } | ConvertTo-Json -Compress
                [void](New-ItemProperty -LiteralPath $key -Name $valueName -Value $record -PropertyType String -Force -ErrorAction Stop)
                Write-NamingLog "Dispatched '$taskName' to session $($session.Id) as SID $sid. Check the user's Toast.log for display status."
            } catch {
                $message = "Session $($session.Id) failed while $stage. $($_.Exception.Message)"
                $failures += $message
                Write-NamingLog $message
            }
        }
        if ($ReportFailures -and $failures.Count) { throw ($failures -join ' | ') }
    } catch {
        Write-NamingLog "Reboot toast scheduling unavailable: $($_.Exception.Message)"
        if ($ReportFailures) { throw }
    }
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

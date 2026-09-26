' Run campus-login.ps1 (same folder as this vbs) with a hidden window (no console popup)
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & dir & "\campus-login.ps1"""
CreateObject("WScript.Shell").Run cmd, 0, False

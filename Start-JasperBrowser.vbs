Option Explicit
Dim fso, shell, home, powershell, scriptPath, commandLine
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
home = fso.GetParentFolderName(WScript.ScriptFullName)
powershell = shell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
scriptPath = fso.BuildPath(home, "Start-JasperBrowser.ps1")
commandLine = Chr(34) & powershell & Chr(34) & " -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & scriptPath & Chr(34)
shell.Run commandLine, 0, False

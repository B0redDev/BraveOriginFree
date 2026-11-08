Option Explicit
Dim shell, files, environment, script, command, result
Set shell = CreateObject("WScript.Shell")
Set files = CreateObject("Scripting.FileSystemObject")
script = files.BuildPath(files.GetParentFolderName(WScript.ScriptFullName), "src\launch.ps1")
' Run expands %VARIABLES% even inside quotes. Pass paths/URLs as environment data, not command text.
Set environment = shell.Environment("PROCESS")
environment("BRAVEORIGINFREE_SCRIPT") = script
environment("BRAVEORIGINFREE_TARGET") = ""
command = Chr(34) & shell.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe") & Chr(34) & _
    " -NoProfile -ExecutionPolicy Bypass -Command " & Chr(34) & _
    "& $env:BRAVEORIGINFREE_SCRIPT -Gui -Target $env:BRAVEORIGINFREE_TARGET; exit $LASTEXITCODE" & Chr(34)
If WScript.Arguments.Count > 1 Then
    MsgBox "Expected at most one URL or file path.", vbExclamation, "Brave Origin Free"
    WScript.Quit 1
End If
If WScript.Arguments.Count = 1 Then environment("BRAVEORIGINFREE_TARGET") = WScript.Arguments(0)
On Error Resume Next
result = shell.Run(command, 0, True)
If Err.Number <> 0 Then
    MsgBox "Could not start Brave Origin: " & Err.Description, vbCritical, "Brave Origin Free"
    WScript.Quit 1
End If
On Error GoTo 0
If result <> 0 Then
    MsgBox "Brave Origin could not start (exit " & result & "). For details, run this command in PowerShell:" & _
        vbCrLf & vbCrLf & "powershell.exe -NoProfile -ExecutionPolicy Bypass -File " & Chr(34) & script & Chr(34), _
        vbCritical, "Brave Origin Free"
End If
WScript.Quit result


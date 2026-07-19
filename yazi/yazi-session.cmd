@echo off
chcp 65001 >nul
set "YAZI_FILE_ONE=C:\Program Files\Git\usr\bin\file.exe"
powershell.exe -NoLogo -NoExit -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\larbs-windows\yazi\yazi-session.ps1"

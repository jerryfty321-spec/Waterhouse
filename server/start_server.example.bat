@echo off
REM Starts the Valheim dedicated server on the Waterhouse world, synced with GitHub.
REM Copy this file into your "Valheim dedicated server" folder, rename it (e.g.
REM my_start_headless_server.bat) and set the password below. Do NOT commit your copy:
REM this repo is public. See README.md.
REM Stop with CTRL-C (not by closing the window) so the final save is pushed.
REM NOTE: Minimum password length is 5 characters & Password cant be in the server name.
REM NOTE: Ports 2456-2458 (UDP) must be forwarded to this machine through your router & firewall.
REM World modifiers (stored in the world - every host should use the same ones). See README.md.
powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\ValheimSaves\worlds_local\Waterhouse\server\waterhouse_server.ps1" -ServerDir "%~dp0." -ServerName "My server" -Password "CHANGE_ME" -ExtraArgs "-modifier deathpenalty veryeasy -modifier resources more"
pause

@echo off
setlocal
cd /d "%~dp0"
start "" node server.mjs
timeout /t 1 /nobreak >nul
start "" http://127.0.0.1:4178
endlocal
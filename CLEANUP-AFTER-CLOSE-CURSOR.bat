@echo off
echo Removing aws-bootstrap folder...
rd /s /q "%~dp0aws-bootstrap" 2>nul
if exist "%~dp0aws-bootstrap" (
    echo FAILED: Folder is still in use. Close Cursor completely and run this again.
    pause
) else (
    echo Done. aws-bootstrap removed.
    del "%~f0"
    pause
)

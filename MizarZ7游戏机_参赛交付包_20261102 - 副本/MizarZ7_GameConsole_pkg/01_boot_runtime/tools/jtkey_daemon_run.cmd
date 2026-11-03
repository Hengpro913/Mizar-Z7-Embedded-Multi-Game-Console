@echo off
title Mizar Z7 - JTAG Key Daemon (do not close)
echo Starting xsdb key-injection daemon ...
echo.
"D:\Program_Files\AMD\2026.1\Vivado\bin\xsdb.bat" "%~dp0jtkey_daemon.tcl"
echo.
echo Daemon exited.
pause

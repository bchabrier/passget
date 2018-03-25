@echo off
setlocal EnableExtensions

rem password is in %password% variable

set field=%1
set group=%2
set entry=%3

rem echo Retrieving %field% of %group%/%entry% >&2

set inputcmd=^^^(echo.%password% ^^^& echo. ^^^& echo. ^^^)

if "%password%"=="" (
    set param=-guikeyprompt
) else (
    set param=-keyprompt
)

rem tokens= because return a string ala: Password: Key File: User Account (Y/N): <value>
for /F "tokens=6,*" %%a in ('%inputcmd% ^| D:\Dropbox\Keepass\KPScript ^
    -c:GetEntryString "D:\Dropbox\NewDatabase.kdbx" ^
    -Field:%field% ^
    -ref-Title:%entry% ^
    -refx-Group:%group% ^
    %param% ^
    ^| find /V "OK: Operation completed successfully." ^
    ^| find /V "To ignore a key component, simply press [Enter] without entering any string." ^
    ^| find /V "Enter the composite master key for the specified database:" ') do set value=%%b


echo.%value%


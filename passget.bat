@echo off
setlocal EnableExtensions
setlocal EnableDelayedExpansion

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

set err=1
set n=0
for /F "tokens=*" %%a in ('%inputcmd% ^| KPScript ^
    -c:GetEntryString "D:\Dropbox\NewDatabase.kdbx" ^
    -Field:%field% ^
    -ref-Title:%entry% ^
    -refx-Group:%group% ^
    %param% 2^>^&1') do (
        set line=%%a
        set /a n=!n!+1
        call set "line_!n!=!line!"
        call set "subline=%%line:Password: Key File: User Account (Y/N): E: =%%"
        if "!subline!"=="%%a" (
            call set "subline=%%line:Password: Key File: User Account (Y/N): =%%"   
            if not "!subline!"=="%%a" (
                set value=!subline!
                set err=0
            )
        )
        call set "subline=%%line:OK: Operation completed successfully.=%%"
        if not "!subline!"=="%%a" (
            set err=0
        )
        if "!subline!"=="%%a" if "%param%"=="-guikeyprompt" set value=%%a
    )

if %err%==1 (
    for /L %%i in (1,1,%n%) do call echo %%line_%%i%%>&2
) else (
    echo.%value%
)

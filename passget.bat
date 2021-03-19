@echo off

set debug=0

setlocal EnableDelayedExpansion 

if "!debug!"=="1" echo.%* >&2

for %%A in ("" "--help") do if "%1"==%%A (
    echo Usage: %0 [--help^|--set^|^<field^> ^<group^> ^<entry^>] >&2
    echo  --help:                  gives this help >&2
    echo  --set:                   asks for password and encrypts the 'password' variable >&2
    echo  ^<field^> ^<group^> ^<entry^>: gets the entry from keepass >&2
    exit /B
)

if not "%1"=="--set" goto end_set:
    if defined password goto next
        set "psCommand=powershell -Command "$pword = read-host 'Enter Password' -AsSecureString ; ^
            $BSTR=[System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pword); ^
                [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)""
        for /f "usebackq delims=" %%p in (`%psCommand%`) do set password=%%p
    :next
    shift /1
:end_set:

rem password is in %password% variable

if "%password%"=="" goto end_encode:
call :getMagic: magic
if "%password:~0,8%"=="!magic!" goto end_encode:

    rem encode password as it is not
    echo | set /p="Found password, encrypting it..." >&2

    rem get length of password
    call :strlen password strlen

    rem encode length as hex
    call cmd /c exit /b %strlen%
    set strlen_hex=%=exitcode%

    rem Create zero.tmp file with 1 character
    fsutil file createnew %TEMP%\zero.tmp 3 > NUL

    rem encrypt password
    set /A end=%strlen% - 1
    for /l %%C in (0,1,%end%) DO (
        set c=!password:~%%C,1!
        echo | set /p="X!c!X"> %TEMP%\char.tmp
        echo | set /p="." >&2
        for /F "tokens=2" %%a in ('fc /B %TEMP%\char.tmp %TEMP%\zero.tmp ^| findstr 00000001:') do (
            set "hex=!hex!%%a"
        )
    )
    echo. >&2


    call :getMagic: magic
    set enc_password=%magic%%strlen_hex%%hex%
    endlocal & set password=%enc_password%

    setlocal EnableDelayedExpansion 

    del %TEMP%\zero.tmp %TEMP%\char.tmp
:end_encode:

if "%1"=="" exit /B

set f=%~1
set g=%~2
set e=%~3
set var=VAL_%f%_%g%_%e%
set var=%var: =--WS--%
if defined %var% (
    set dec=pouet
    call :decrypt %var% dec
    if "!debug!"=="1" call echo.%var% = %%%var%%% decrypted to !dec!>&2
    echo.!dec!
    endlocal
    exit /B
)

set field=%1
set group=%2
set entry=%3

rem if password is encrypted, decrypt it

if not defined password goto :end_decode
if "%password%"=="" goto :end_decode
call :getMagic: magic
if not "%password:~0,8%"=="%magic%" goto :end_decode
    set "strlen_enc=%password:~8,8%"
    set "password=%password:~16%"
    set /a strlen=0x%strlen_enc%
    set /a end=2 * %strlen% - 1
    set p=
    setlocal EnableDelayedExpansion 
    for /l %%C in (0,2,%end%) DO (
        set c=!password:~%%C,2!
        set p=!p!0x!c!
    )
    for /F "delims==" %%i IN ('forfiles /p "%~dp0." /m "%~nx0" /c "cmd /c echo.%p%"') DO set "decoded_password=%%i"
    endlocal & set "password=%decoded_password%"
:end_decode:

call :getKeepassLastUsedFile kpdb

rem echo Retrieving %field% of %group%/%entry% >&2

set inputcmd=^^^(echo.%password% ^^^& echo. ^^^& echo. ^^^)

if "%password%"=="" (
    set param=-guikeyprompt
) else (
    set param=-keyprompt
)

setlocal EnableDelayedExpansion EnableExtensions
set err=1
set n=0
for /F "tokens=*" %%a in ('%inputcmd% ^| KPScript ^
    -c:GetEntryString "%kpdb%" ^
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
    if "!debug!"=="1" echo.%value%>&2
)
endlocal

exit /B

:strLen string len -- returns the length of a string
::                 -- string [in]  - variable name containing the string being measured for length
::                 -- len    [out] - variable to be used to return the string length
:: Many thanks to 'sowgtsoi', but also 'jeb' and 'amel27' dostips forum users helped making this short and efficient
:$created 20081122 :$changed 20101116 :$categories StringOperation
:$source https://www.dostips.com
(   SETLOCAL ENABLEDELAYEDEXPANSION
    set "str=A!%~1!"&rem keep the A up front to ensure we get the length and not the upper bound
                     rem it also avoids trouble in case of empty string
    set "len=0"
    for /L %%A in (12,-1,0) do (
        set /a "len|=1<<%%A"
        for %%B in (!len!) do if "!str:~%%B,1!"=="" set /a "len&=~1<<%%A"
    )
)
( ENDLOCAL & REM RETURN VALUES
    IF "%~2" NEQ "" SET /a %~2=%len%
)
EXIT /b


:decrypt string decrypted_string -- returns the decrypted string
::                 -- string              [in]  - string being decrypted
::                 -- decrypted_string    [out] - variable to be used to return the decrypted string
(   SETLOCAL ENABLEDELAYEDEXPANSION
    set "str=!%~1!"
    set "enc="

    if not defined str goto :end_decrypt
    if "!str!"=="" goto :end_decrypt
    call :getMagic: magic
    if not "!str:~0,8!"=="!magic!" goto :end_decrypt

    set "strlen_enc=!str:~8,8!"
    set "str=!str:~16!"
    set /a strlen=0x!strlen_enc!
    set /a end=2 * !strlen! - 1
    set p=
    for /l %%C in (0,2,!end!) DO (
        set c=!str:~%%C,2!
        set p=!p!0x!c!
    )

    for /F "delims==" %%i IN ('forfiles /p "%~dp0." /m "%~nx0" /c "cmd /c echo.!p!"') DO set "enc=%%i"
:end_decrypt
    rem
)
( ENDLOCAL & REM RETURN VALUES
    IF "%~2" NEQ "" SET %~2=%enc%
)
EXIT /b

:getKeepassPath thepath -- returns the path where Keepass is located
::                 -- path    [out] - variable to be used to return the path
(   SETLOCAL ENABLEDELAYEDEXPANSION
    set "thepath="
    for /F "delims==" %%i IN ('"where keepass"') DO set "thepath=%%i"
    set "thepath=!thepath:\KeePass.exe=!"
)
( ENDLOCAL & REM RETURN VALUES
    IF "%~1" NEQ "" SET %~1=%thepath%
)
EXIT /b

:getKeepassLastUsedFile kpdb -- returns the last used database used by Keepass
::                 -- path    [out] - variable to be used to return the database
(   SETLOCAL ENABLEDELAYEDEXPANSION
    set "kpdb="
    call :getKeepassPath kppath
    set "configfile=!kppath!\KeePass.config.xml"

    rem find in the file Application/LastUsedFile/Path
    for /F "tokens=1-3 delims=<> " %%a in ('type "!configfile!"') do (
        if "%%b"=="Application" set "inApplication=1"
        if "%%b"=="LastUsedFile" set "inLastUsedFile=1"
        if "!inApplication!!inLastUsedFile!%%b"=="11Path" set "kpdb=%%c"
        if "%%b"=="/LastUsedFile" set "inLastUsedFile="
        if "%%b"=="/Application" set "inApplication="
 
        )
    if "!kpdb:~0,1!"=="." set "kpdb=!kppath!\!kpdb!"
)
( ENDLOCAL & REM RETURN VALUES
    IF "%~1" NEQ "" SET %~1=%kpdb%
)
EXIT /b

:getMagic magic -- returns the magic number
::                 -- magic    [out] - variable to be used to return the magic
(   SETLOCAL ENABLEDELAYEDEXPANSION
    set "magic=F45A9B6C"
)
( ENDLOCAL & REM RETURN VALUES
    IF "%~1" NEQ "" SET %~1=%magic%
)
EXIT /b

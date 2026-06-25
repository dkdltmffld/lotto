@echo off
chcp 65001 >nul
rem ============================================================
rem  Data build: data/src/*.yaml  ->  data/*.json  (double-click)
rem  Edit a .yaml source, then double-click this to regenerate
rem  the .json that the game reads. Look for "errors 0" = success.
rem  (This file is ASCII on purpose; batch + Korean text breaks cmd.)
rem ============================================================
setlocal
set "GODOT=C:\Users\jaeyeop.im.SUPERCAT\Downloads\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe"
set "PROJ=%~dp0..\.."

if not exist "%GODOT%" (
  echo.
  echo [ERROR] Godot not found:
  echo    "%GODOT%"
  echo Open this .bat in Notepad and fix the GODOT path.
  echo.
  pause
  exit /b 1
)

echo Building  data/src/*.yaml  =^> data/*.json ...
echo.
"%GODOT%" --headless --path "%PROJ%" --script res://tools/build_data.gd
set "RC=%ERRORLEVEL%"
echo.
echo ------------------------------------------------------------
if "%RC%"=="0" (
  echo  OK : conversion done. JSON updated. ^(see "errors 0" above^)
) else (
  echo  FAILED : check errors above. Common cause = a quest id in
  echo  'order' that is missing/renamed in 'quests'. Fix yaml, retry.
)
echo ------------------------------------------------------------
echo.
pause
endlocal

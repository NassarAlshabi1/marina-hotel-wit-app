@echo off
setlocal enabledelayedexpansion
title Marina Hotel Desktop Launcher

chcp 65001 >nul

echo ===============================================
echo   تشغيل نظام مارينا - Flutter + PHP + MySQL
echo ===============================================

set "PROJECT_ROOT=%~dp0"
if "%PROJECT_ROOT:~-1%"=="\" set "PROJECT_ROOT=%PROJECT_ROOT:~0,-1%"

set "PORT=8080"
if not "%PHP_PORT%"=="" set "PORT=%PHP_PORT%"

set "XAMPP_DIR=%XAMPP_DIR%"
if "%XAMPP_DIR%"=="" set "XAMPP_DIR=C:\xampp"

set "PHP_EXE=%PHP_EXE%"
if "%PHP_EXE%"=="" (
  if exist "%XAMPP_DIR%\php\php.exe" (
    set "PHP_EXE=%XAMPP_DIR%\php\php.exe"
  ) else (
    set "PHP_EXE=php"
  )
)

set "FLUTTER_EXE=%FLUTTER_EXE%"
if "%FLUTTER_EXE%"=="" (
  set "FLUTTER_EXE=%PROJECT_ROOT%\mobile\build\windows\x64\runner\Release\marina_hotel_mobile.exe"
)

call :start_mysql
call :start_php
call :start_flutter

echo ===============================================
echo   تم التشغيل. يمكنك إغلاق هذه النافذة لاحقاً.
echo ===============================================
pause
exit /b

:start_mysql
echo [1/3] تشغيل MySQL...
if exist "%XAMPP_DIR%\mysql_start.bat" (
  call "%XAMPP_DIR%\mysql_start.bat"
  goto :eof
)

for %%S in (MySQL MySQL80 MariaDB) do (
  sc query "%%S" >nul 2>&1
  if !errorlevel! == 0 (
    net start "%%S" >nul 2>&1
  )
)

echo تم تنفيذ محاولة تشغيل MySQL.
exit /b

:start_php
echo [2/3] تشغيل PHP Server على المنفذ %PORT%...
start "PHP Server" /min "%PHP_EXE%" -S 127.0.0.1:%PORT% -t "%PROJECT_ROOT%"
exit /b

:start_flutter
echo [3/3] تشغيل تطبيق Flutter...
if exist "%FLUTTER_EXE%" (
  start "Flutter App" "%FLUTTER_EXE%"
) else (
  echo لم يتم العثور على ملف التطبيق:
  echo %FLUTTER_EXE%
  echo قم أولاً ببناء نسخة Windows:
  echo ^> cd mobile
  echo ^> flutter build windows --release
)
exit /b

@echo off
title Test Marina Hotel EXE
echo ========================================
echo    Testing Marina Hotel EXE Setup
echo ========================================
echo.
echo Testing files...
echo.

if exist "phpdesktop-chrome-57.0-rc-php-7.1.3\phpdesktop-chrome.exe" (
    echo [✓] phpdesktop-chrome.exe found
) else (
    echo [✗] phpdesktop-chrome.exe NOT found
)

if exist "phpdesktop-chrome-57.0-rc-php-7.1.3\www\login.php" (
    echo [✓] login.php found
) else (
    echo [✗] login.php NOT found
)

if exist "phpdesktop-chrome-57.0-rc-php-7.1.3\www\admin" (
    echo [✓] admin folder found
) else (
    echo [✗] admin folder NOT found
)

if exist "phpdesktop-chrome-57.0-rc-php-7.1.3\www\assets" (
    echo [✓] assets folder found
) else (
    echo [✗] assets folder NOT found
)

if exist "phpdesktop-chrome-57.0-rc-php-7.1.3\www\includes" (
    echo [✓] includes folder found
) else (
    echo [✗] includes folder NOT found
)

if exist "phpdesktop-chrome-57.0-rc-php-7.1.3\www\uploads" (
    echo [✓] uploads folder found
) else (
    echo [✗] uploads folder NOT found
)

if exist "phpdesktop-chrome-57.0-rc-php-7.1.3\www\data" (
    echo [✓] data folder found
) else (
    echo [✗] data folder NOT found
)

if exist "phpdesktop-chrome-57.0-rc-php-7.1.3\settings.json" (
    echo [✓] settings.json found
) else (
    echo [✗] settings.json NOT found
)

echo.
echo ========================================
echo    Test completed!
echo ========================================
echo.
echo If all files show [✓], your EXE is ready!
echo.
echo To run Marina Hotel:
echo 1. Go to: phpdesktop-chrome-57.0-rc-php-7.1.3\
echo 2. Run: START_MARINA_HOTEL.bat
echo 3. Or directly: phpdesktop-chrome.exe
echo.
echo Default login: admin / admin123
echo.
pause
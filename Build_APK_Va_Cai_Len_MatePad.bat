@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
title ChemNote - Build APK va Cai Len Huawei MatePad 11.5"S

echo ============================================================================
echo   CHEMNOTE - BUILD APK NATIVE 144Hz + M-PENCIL 3 CHO HUAWEI MATEPAD 11.5"S
echo ============================================================================
echo.

cd /d "%~dp0"

set "FLUTTER_CMD="

where flutter >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    set "FLUTTER_CMD=flutter"
    goto :found_flutter
)

for %%P in (
    "C:\src\flutter\bin\flutter.bat"
    "%USERPROFILE%\flutter\bin\flutter.bat"
    "%LOCALAPPDATA%\flutter\bin\flutter.bat"
    "C:\flutter\bin\flutter.bat"
    "D:\flutter\bin\flutter.bat"
) do (
    if exist "%%~P" (
        set "FLUTTER_CMD=%%~P"
        goto :found_flutter
    )
)

echo [!] Khong tim thay Flutter SDK tren may tinh nay.
echo.
echo Ban co 3 lua chon:
echo   [1] Tu dong cai dat Flutter SDK qua Windows Winget ngay bay gio
echo   [2] Dung ban 1-File / PWA (khong can cai Flutter): chay Chay_Server_Cai_Qua_WiFi.bat
echo       hoac gui truc tiep file ChemNote_MatePad_AllInOne.html sang MatePad!
echo   [3] Build APK tren dam may GitHub Actions (da co san .github\workflows\build-apk.yml)
echo.
set /p INSTALL_CHOICE="Nhap 1 de cai Flutter tu dong, hoac Enter de thoat: "
if "%INSTALL_CHOICE%"=="1" (
    echo [*] Dang cai dat Flutter SDK qua winget...
    winget install -e --id Google.Flutter
    echo [*] Sau khi cai xong, hay mo lai file .bat nay!
)
pause
exit /b 1

:found_flutter
echo [OK] Da tim thay Flutter: %FLUTTER_CMD%
echo.

if not exist "android\gradlew.bat" (
    echo [*] Dang khoi tao Gradle Wrapper va bao ve cau hinh 144Hz M-Pencil 3...
    if not exist "%TEMP%\chemnote_bak" mkdir "%TEMP%\chemnote_bak"
    copy /Y "android\app\src\main\AndroidManifest.xml" "%TEMP%\chemnote_bak\AndroidManifest.xml" >nul
    copy /Y "android\app\src\main\kotlin\com\chemnote\app\MainActivity.kt" "%TEMP%\chemnote_bak\MainActivity.kt" >nul
    copy /Y "android\app\build.gradle" "%TEMP%\chemnote_bak\app_build.gradle" >nul

    call "%FLUTTER_CMD%" create --platforms=android --org com.chemnote --project-name chemnote .

    copy /Y "%TEMP%\chemnote_bak\AndroidManifest.xml" "android\app\src\main\AndroidManifest.xml" >nul
    copy /Y "%TEMP%\chemnote_bak\MainActivity.kt" "android\app\src\main\kotlin\com\chemnote\app\MainActivity.kt" >nul
    copy /Y "%TEMP%\chemnote_bak\app_build.gradle" "android\app\build.gradle" >nul
)

echo [1/3] Dang tai cac thu vien Dart/Flutter (flutter pub get)...
call "%FLUTTER_CMD%" pub get
if %ERRORLEVEL% NEQ 0 (
    echo [LOI] flutter pub get that bai. Vui long kiem tra ket noi Internet.
    pause
    exit /b 1
)

echo.
echo [2/3] Dang dong goi APK Release cho Huawei MatePad 11.5"S (GMS-free)...
call "%FLUTTER_CMD%" build apk --release
if %ERRORLEVEL% NEQ 0 (
    echo [LOI] Qua trinh build APK gap su co. Vui long kiem tra JDK 17 / Android SDK.
    pause
    exit /b 1
)

if exist "build\app\outputs\flutter-apk\app-release.apk" (
    copy /Y "build\app\outputs\flutter-apk\app-release.apk" "ChemNote-MatePad-11.5s.apk" >nul
    echo.
    echo ============================================================================
    echo   [THANH CONG] Da tao file: d:\Downloads\ChemNote\ChemNote-MatePad-11.5s.apk
    echo ============================================================================
) else (
    echo [LOI] Khong tim thay file APK dau ra.
    pause
    exit /b 1
)

echo.
echo [3/3] Kiem tra ket noi USB voi Huawei MatePad qua ADB...
set "ADB_CMD="
if exist "%~dp0tools\platform-tools\adb.exe" (
    set "ADB_CMD=%~dp0tools\platform-tools\adb.exe"
) else (
    where adb >nul 2>&1
    if !ERRORLEVEL! EQU 0 set "ADB_CMD=adb"
)
if not "!ADB_CMD!"=="" (
    "!ADB_CMD!" get-state >nul 2>&1
    if !ERRORLEVEL! EQU 0 (
        echo [*] Phat hien MatePad dang cam cap USB! Dang cai dat truc tiep...
        "!ADB_CMD!" install -r "ChemNote-MatePad-11.5s.apk"
        if !ERRORLEVEL! EQU 0 (
            echo [HOAN TAT] Da cai ChemNote len Huawei MatePad thanh cong!
            pause
            exit /b 0
        )
    )
)

echo [*] Ban co the gui file "ChemNote-MatePad-11.5s.apk" sang MatePad qua:
echo     - Cap USB / Huawei Share / Zalo / Google Drive
echo     - Hoac chay "Chay_Server_Cai_Qua_WiFi.bat" de tai APK truc tiep qua Wi-Fi!
echo.
pause

@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
title ChemNote Pro v3.0.0 - May Chu Wi-Fi Cho Huawei MatePad 11.5"S

cd /d "%~dp0"

echo ============================================================================
echo   CHEMNOTE PRO v3.0.0 - CAI DAT NHANH LEN HUAWEI MATEPAD 11.5"S QUA WI-FI
echo ============================================================================
echo.
echo Tren Huawei MatePad 11.5"S (cung mang Wi-Fi voi may tinh nay), hay mo
echo trinh duyet Brave / Huawei Browser / Chrome va truy cap dia chi sau:
echo.

for /f "tokens=2 delims=:" %%A in ('ipconfig ^| findstr /C:"IPv4"') do (
    set "IP=%%A"
    set "IP=!IP: =!"
    echo   [1] Mo App ChemNote Pro v3.0.0 PWA ^(Khuyen dung^):
    echo       http://!IP!:8080/
    echo       -^> Nhan bieu tuong Cai App tren thanh dia chi hoac "Them vao man hinh chinh"
    echo.
    echo   [2] Tai 1 File Doc Lap ^(chay offline 100%% khong can mang^):
    echo       http://!IP!:8080/ChemNote_MatePad_AllInOne.html
    echo   ------------------------------------------------------------------------
)

echo.
echo Dang khoi dong may chu Wi-Fi HTTP tai cong 8080 (0.0.0.0:8080 - Nhan Ctrl+C de dung)...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\serve_matepad.ps1"

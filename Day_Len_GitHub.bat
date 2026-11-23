@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
title ChemNote Pro v3.0.0 - Day Ma Nguon Len GitHub (OTA Pages + Auto APK)

cd /d "%~dp0"

echo ============================================================================
echo   CHEMNOTE PRO v3.0.0 - DAY LEN https://github.com/quydnvocvach/ChemNote
echo ============================================================================
echo.

set "GIT_CMD="
where git >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    set "GIT_CMD=git"
    goto :found_git
)
for %%P in (
    "C:\Program Files\Git\cmd\git.exe"
    "C:\Program Files (x86)\Git\cmd\git.exe"
    "%LOCALAPPDATA%\Programs\Git\cmd\git.exe"
) do (
    if exist "%%~P" (
        set "GIT_CMD=%%~P"
        goto :found_git
    )
)

echo [*] Chua co Git tren may. Dang tu dong cai dat Git qua winget...
winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
if exist "C:\Program Files\Git\cmd\git.exe" (
    set "GIT_CMD=C:\Program Files\Git\cmd\git.exe"
    goto :found_git
)
echo [!] Vui long dong cua so nay va mo lai Day_Len_GitHub.bat sau khi cai Git xong.
pause
exit /b 1

:found_git
echo [OK] Da tim thay Git: %GIT_CMD%
echo.

if not exist ".git" (
    "%GIT_CMD%" init -b main
)

"%GIT_CMD%" config user.name "quydnvocvach"
"%GIT_CMD%" config user.email "quydnvocvach@users.noreply.github.com"

echo [1/3] Dang chuan bi tep tin (tu dong bo qua tools/platform-tools va file tam)...
"%GIT_CMD%" add .
"%GIT_CMD%" commit -m "Release ChemNote Pro v3.0.0 (PWA OTA + Audio Note Replay + PDF.js + Google Drive Sync + Flutter MatePad 11.5s)"

"%GIT_CMD%" remote remove origin >nul 2>&1
"%GIT_CMD%" remote add origin https://github.com/quydnvocvach/ChemNote.git

echo.
echo [2/3] Dang day len GitHub (neu trinh duyet hien dang nhap GitHub, hay chon Authorize)...
"%GIT_CMD%" push -u origin main --force

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ============================================================================
    echo   [THANH CONG] Da day ChemNote Pro v3.0.0 len GitHub!
    echo   - Repo: https://github.com/quydnvocvach/ChemNote
    echo   - Vao Settings -^> Pages -^> Source: GitHub Actions (chi lam 1 lan)
    echo   - Link cai app MatePad 11.5"S: https://quydnvocvach.github.io/ChemNote/
    echo   - Link tai APK tu dong: https://github.com/quydnvocvach/ChemNote/actions
    echo ============================================================================
) else (
    echo.
    echo [!] Day len GitHub chua hoan tat. Vui long kiem tra dang nhap GitHub va thu lai.
)
echo.
pause

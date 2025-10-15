@echo off
REM Build script for Opra - Cross-platform PDF Reader AI

setlocal enabledelayedexpansion

echo Building Opra - Cross-platform PDF Reader AI

if "%1"=="macos" goto build_macos
if "%1"=="windows" goto build_windows
if "%1"=="all" goto build_all
if "%1"=="" goto build_all
goto usage

:build_windows
echo Building Windows app...
cd windows
dotnet build -c Release
if errorlevel 1 exit /b 1
echo Windows build completed
cd ..
goto end

:build_macos
echo Building macOS app...
cd macos
xcodebuild -project Opra.xcodeproj -scheme Opra -configuration Release -derivedDataPath build
if errorlevel 1 exit /b 1
echo macOS build completed
cd ..
goto end

:build_all
call :build_macos
call :build_windows
goto end

:usage
echo Usage: %0 [macos^|windows^|all]
echo   macos   - Build macOS app only
echo   windows - Build Windows app only
echo   all     - Build everything (default)
exit /b 1

:end
echo Build completed successfully!

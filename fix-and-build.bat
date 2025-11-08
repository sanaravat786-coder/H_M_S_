@echo off
echo Fixing Android SDK configuration and building APK...

REM Set Android SDK path (no trailing spaces)
set ANDROID_HOME=C:\Users\sanar\AppData\Local\Android\Sdk
set ANDROID_SDK_ROOT=%ANDROID_HOME%
set PATH=%PATH%;%ANDROID_HOME%\platform-tools;%ANDROID_HOME%\tools

echo ANDROID_HOME: %ANDROID_HOME%

REM Remove any existing local.properties
del android\local.properties 2>nul

REM Create clean local.properties file
echo sdk.dir=C:/Users/sanar/AppData/Local/Android/Sdk > android\local.properties

echo Contents of local.properties:
type android\local.properties

echo Building React app...
call npm run build

echo Syncing Capacitor...
call npx cap sync android

echo Building APK...
cd android
call gradlew.bat assembleDebug --no-daemon

if %errorlevel% equ 0 (
    echo.
    echo ========================================
    echo   SUCCESS! APK BUILT!
    echo ========================================
    echo APK Location: app\build\outputs\apk\debug\app-debug.apk
    echo.
    if exist app\build\outputs\apk\debug\app-debug.apk (
        echo APK file found and ready!
        dir app\build\outputs\apk\debug\app-debug.apk
    ) else (
        echo APK file not found in expected location
        echo Searching for APK files...
        dir /s *.apk
    )
) else (
    echo BUILD FAILED - Error code: %errorlevel%
)

cd ..
pause

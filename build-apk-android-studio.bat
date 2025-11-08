@echo off
echo Setting up Android Studio build environment...

REM Set Android SDK path
set ANDROID_HOME=C:\Users\sanar\AppData\Local\Android\Sdk
set ANDROID_SDK_ROOT=%ANDROID_HOME%
set PATH=%PATH%;%ANDROID_HOME%\platform-tools;%ANDROID_HOME%\tools

echo ANDROID_HOME set to: %ANDROID_HOME%

REM Create local.properties file
echo sdk.dir=%ANDROID_HOME:\=/% > android\local.properties

echo Building React app...
call npm run build

echo Syncing Capacitor...
call npx cap sync android

echo Building APK with Gradle...
cd android
call gradlew.bat clean assembleDebug --stacktrace --info

if %errorlevel% equ 0 (
    echo.
    echo ========================================
    echo   APK BUILD SUCCESSFUL!
    echo ========================================
    echo APK Location: android\app\build\outputs\apk\debug\app-debug.apk
    echo.
    dir app\build\outputs\apk\debug\*.apk
) else (
    echo.
    echo ========================================
    echo   APK BUILD FAILED!
    echo ========================================
    echo Check the error messages above.
)

cd ..
pause

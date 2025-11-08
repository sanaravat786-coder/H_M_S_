@echo off
echo Building Hostel Management System APK...

echo Step 1: Building React app...
call npm run build
if %errorlevel% neq 0 (
    echo Failed to build React app
    exit /b 1
)

echo Step 2: Syncing with Capacitor...
call npx cap sync android
if %errorlevel% neq 0 (
    echo Failed to sync with Capacitor
    exit /b 1
)

echo Step 3: Building APK...
cd android
call gradlew assembleDebug --no-daemon --stacktrace
if %errorlevel% neq 0 (
    echo Failed to build APK
    cd ..
    exit /b 1
)

cd ..
echo APK built successfully!
echo Location: android\app\build\outputs\apk\debug\app-debug.apk

pause

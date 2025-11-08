# PowerShell script to create local.properties
$sdkPath = "C:\Users\sanar\AppData\Local\Android\Sdk"
$content = "sdk.dir=$($sdkPath.Replace('\', '/'))"
$content | Out-File -FilePath "android\local.properties" -Encoding ascii -NoNewline
Write-Host "Created local.properties with content:"
Get-Content "android\local.properties"

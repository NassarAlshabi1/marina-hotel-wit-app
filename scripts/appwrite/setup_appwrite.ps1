param(
  [string]$ProjectId = $env:PROJECT_ID,
  [string]$Endpoint = $env:APPWRITE_ENDPOINT,
  [string]$AndroidAppId = $env:ANDROID_APP_ID,
  [string]$IosBundleId = $env:IOS_BUNDLE_ID,
  [string]$MacOsBundleId = $env:MACOS_BUNDLE_ID,
  [string]$WindowsPackage = $env:WINDOWS_PACKAGE,
  [string]$LinuxPackage = $env:LINUX_PACKAGE,
  [string]$WebHostname = $env:WEB_HOSTNAME,
  [string]$TestUserEmail = $env:TEST_USER_EMAIL,
  [string]$TestUserPassword = $env:TEST_USER_PASSWORD,
  [string]$TestUserName = $env:TEST_USER_NAME
)

if (-not (Get-Command appwrite -ErrorAction SilentlyContinue)) {
  Write-Error "Appwrite CLI is not installed. Install it with 'npm install -g appwrite' and run this script again."
  exit 1
}

if (-not $ProjectId) { $ProjectId = "690ff0da0025518570c1" }
if (-not $Endpoint) { $Endpoint = "https://fra.cloud.appwrite.io/v1" }
if (-not $AndroidAppId) { $AndroidAppId = "com.marina.marina" }
if (-not $IosBundleId) { $IosBundleId = "com.aden.marina" }
if (-not $MacOsBundleId) { $MacOsBundleId = "com.aden.marina.desktop" }
if (-not $WindowsPackage) { $WindowsPackage = "marina_hotel" }
if (-not $LinuxPackage) { $LinuxPackage = "marina_hotel" }
if (-not $WebHostname) { $WebHostname = "localhost" }
if (-not $TestUserEmail) { $TestUserEmail = "user@appwrite.io" }
if (-not $TestUserPassword) { $TestUserPassword = "password" }
if (-not $TestUserName) { $TestUserName = "Test User" }

Write-Host "Appwrite environment setup"
Write-Host "Endpoint  : $Endpoint"
Write-Host "Project ID: $ProjectId" -ForegroundColor Cyan

function Invoke-AppwritePlatform {
  param(
    [string]$Type,
    [string]$Name,
    [string]$Key,
    [string]$Hostname
  )

  Write-Host "`n→ Creating platform $Type ($Key)"
  $args = @("projects","create-platform","--project-id",$ProjectId,"--type",$Type,"--name",$Name,"--key",$Key)
  if ($Hostname) { $args += @("--hostname",$Hostname) }
  $result = appwrite @args 2>$null
  if ($LASTEXITCODE -eq 0) {
    Write-Host "✔ Platform $Type ready"
  } else {
    Write-Warning "Platform $Type skipped (already exists or CLI returned a warning)."
  }
}

Invoke-AppwritePlatform -Type "flutter-android" -Name $AndroidAppId -Key $AndroidAppId
Invoke-AppwritePlatform -Type "flutter-ios" -Name $IosBundleId -Key $IosBundleId
Invoke-AppwritePlatform -Type "flutter-macos" -Name $MacOsBundleId -Key $MacOsBundleId
Invoke-AppwritePlatform -Type "flutter-windows" -Name $WindowsPackage -Key $WindowsPackage
Invoke-AppwritePlatform -Type "flutter-linux" -Name $LinuxPackage -Key $LinuxPackage
Invoke-AppwritePlatform -Type "flutter-web" -Name "Web ($WebHostname)" -Key $WebHostname -Hostname $WebHostname

if (Test-Path "appwrite.json") {
  Write-Host "`n→ Deploying collections and buckets defined in appwrite.json"
  appwrite deploy collection --all --yes 2>$null
  if ($LASTEXITCODE -ne 0) { Write-Warning "Unable to deploy collections (ensure definitions exist)." }
  appwrite deploy bucket --all --yes 2>$null
  if ($LASTEXITCODE -ne 0) { Write-Warning "Unable to deploy buckets (ensure definitions exist)." }
} else {
  Write-Warning "No appwrite.json found. Skipping collection/bucket deployment."
}

Write-Host "`n→ Creating default test user ($TestUserEmail)"
appwrite users create --user-id "unique()" --email $TestUserEmail --password $TestUserPassword --name $TestUserName 2>$null
if ($LASTEXITCODE -eq 0) {
  Write-Host "✔ Test user created"
} else {
  Write-Warning "Skipped creating test user (may already exist)."
}

Write-Host "`n✓ Appwrite project bootstrap complete. Update your Flutter configuration (AppwriteConfig) if you changed any values." -ForegroundColor Green

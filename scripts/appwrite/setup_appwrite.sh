#!/usr/bin/env bash
set -euo pipefail

if ! command -v appwrite >/dev/null 2>&1; then
  echo "✖ Appwrite CLI is not installed. Install it with 'npm install -g appwrite' and run this script again." >&2
  exit 1
fi

PROJECT_ID="${PROJECT_ID:-690ff0da0025518570c1}"
APPWRITE_ENDPOINT="${APPWRITE_ENDPOINT:-https://fra.cloud.appwrite.io/v1}"
ANDROID_APP_ID="${ANDROID_APP_ID:-com.marina.marina}"
IOS_BUNDLE_ID="${IOS_BUNDLE_ID:-com.aden.marina}"
WEB_HOSTNAME="${WEB_HOSTNAME:-localhost}"
WINDOWS_PACKAGE="${WINDOWS_PACKAGE:-marina_hotel}" 
LINUX_PACKAGE="${LINUX_PACKAGE:-marina_hotel}" 
MACOS_BUNDLE_ID="${MACOS_BUNDLE_ID:-com.aden.marina.desktop}" 
TEST_USER_EMAIL="${TEST_USER_EMAIL:-user@appwrite.io}" 
TEST_USER_PASSWORD="${TEST_USER_PASSWORD:-password}" 
TEST_USER_NAME="${TEST_USER_NAME:-Test User}"

cat <<EOF
Appwrite environment setup
===========================
Endpoint  : ${APPWRITE_ENDPOINT}
Project ID: ${PROJECT_ID}
EOF

create_platform() {
  local type="$1"
  local name="$2"
  local key="$3"
  shift 3

  echo "\n→ Creating platform ${type} (${key})"
  if appwrite projects create-platform --project-id "${PROJECT_ID}" --type "${type}" --name "${name}" --key "${key}" "$@" >/dev/null 2>&1; then
    echo "✔ Platform ${type} ready"
  else
    echo "⚠ Platform ${type} skipped (already exists or CLI returned a warning)"
  fi
}

create_platform flutter-android "${ANDROID_APP_ID}" "${ANDROID_APP_ID}"
create_platform flutter-ios "${IOS_BUNDLE_ID}" "${IOS_BUNDLE_ID}"
create_platform flutter-macos "${MACOS_BUNDLE_ID}" "${MACOS_BUNDLE_ID}"
create_platform flutter-windows "${WINDOWS_PACKAGE}" "${WINDOWS_PACKAGE}"
create_platform flutter-linux "${LINUX_PACKAGE}" "${LINUX_PACKAGE}"
create_platform flutter-web "Web (${WEB_HOSTNAME})" "${WEB_HOSTNAME}" --hostname "${WEB_HOSTNAME}"

if [ -f "appwrite.json" ]; then
  echo "\n→ Deploying collections and buckets defined in appwrite.json"
  appwrite deploy collection --all --yes || echo "⚠ Unable to deploy collections (ensure definitions exist)"
  appwrite deploy bucket --all --yes || echo "⚠ Unable to deploy buckets (ensure definitions exist)"
else
  echo "\n⚠ No appwrite.json found. Skipping collection/bucket deployment."
fi

echo "\n→ Creating default test user (${TEST_USER_EMAIL})"
if appwrite users create --user-id "unique()" --email "${TEST_USER_EMAIL}" --password "${TEST_USER_PASSWORD}" --name "${TEST_USER_NAME}" >/dev/null 2>&1; then
  echo "✔ Test user created"
else
  echo "⚠ Skipped creating test user (may already exist)"
fi

echo "\n✓ Appwrite project bootstrap complete. Update your Flutter configuration (AppwriteConfig) if you changed any values."

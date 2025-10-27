#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
flutter test test/services/google_drive_backup_service_test.dart

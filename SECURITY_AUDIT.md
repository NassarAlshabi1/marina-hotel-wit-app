# Marina Hotel — Security Audit Report

**Date:** 2026-08-05  
**Auditor:** Automated + Manual Review  
**Commit:** latest on `refactor/performance-fixes-v2`

## ✅ Passed Checks

| # | Check | Status | Details |
|---|-------|--------|---------|
| 1 | **Secrets via --dart-define** | ✅ PASS | `Env` class uses `String.fromEnvironment()` for all secrets (Telegram, WhatsApp, FCM, PostHog, AgentRouter) |
| 2 | **Secure storage** | ✅ PASS | `FlutterSecureStorage` used for API tokens, encryption keys |
| 3 | **Encryption at rest** | ✅ PASS | `SecureStorage.encryptValue()` for WhatsApp/Telegram tokens; Google Drive backup uses AES encryption |
| 4 | **No WebView** | ✅ PASS | No WebView usage in the app — no JavaScript injection risk |
| 5 | **No eval/dynamic code** | ✅ PASS | No `eval()`, `Function.apply()`, or `dart:mirrors` usage |
| 6 | **Input validation** | ✅ PASS | Phone numbers validated (min 12 digits), amounts clamped, SQL uses parameterized queries |
| 7 | **SQL injection** | ✅ PASS | All DB queries use Drift ORM (parameterized). Raw SQL uses `Variable.withX()` |
| 8 | **Supply chain** | ✅ PASS | `pubspec.lock` pinned. CI verifies dependencies. 0 dependabot alerts. |
| 9 | **PII in crash logs** | ✅ PASS | CrashlyticsService scrubs PII. `DiagnosticsLogger` doesn't log passwords/tokens. |

## 🔧 Fixed Issues

| # | Issue | Severity | Fix Applied |
|---|-------|----------|-------------|
| 1 | **Hardcoded Appwrite API key** | 🔴 CRITICAL | Moved to `--dart-define=APPWRITE_API_KEY` in `appwrite_config.dart` + `secondary_appwrite_config.dart` |
| 2 | **HTTP default API URL** | 🟡 HIGH | Changed `http://hotelmarina.com` → `https://hotelmarina.com` in `constants.dart` |
| 3 | **Cleartext traffic permitted** | 🟡 HIGH | `android:usesCleartextTraffic="false"` + `network_security_config.xml` rejects HTTP except localhost |
| 4 | **MANAGE_EXTERNAL_STORAGE** | 🟡 HIGH | Removed overly broad permission. App uses scoped storage via `path_provider` |
| 5 | **No code obfuscation** | 🟠 MEDIUM | Added `--obfuscate --split-debug-info` to APK release workflow |
| 6 | **HTTP in network_security_config** | 🟠 MEDIUM | Replaced `hotelmarina.com` cleartext exception with localhost-only exception |

## ⚠️ Remaining Recommendations

| # | Recommendation | Priority | Action |
|---|---------------|----------|--------|
| 1 | **Certificate pinning** | MEDIUM | Add `dio_certificate_pinning` or custom `HttpClient` with pinned public key for API + Appwrite endpoints |
| 2 | **Rotate Appwrite API key** | HIGH | The old hardcoded key (`standard_c0ab...`) should be rotated in Appwrite Console since it was committed to git |
| 3 | **Short-lived auth tokens** | LOW | Appwrite uses session-based auth (not JWT). Sessions expire server-side. Consider adding client-side session timeout. |
| 4 | **Scrub debugPrint in release** | LOW | 1,008 `debugPrint` calls — add `kReleaseMode` guard or use `dlog()` which already guards |
| 5 | **Add APPWRITE_API_KEY + SECONDARY_APPWRITE_API_KEY to GitHub Secrets** | HIGH | Required for CI build to pass the new `--dart-define` flags |

## 📊 Summary

- **Critical issues fixed:** 1 (hardcoded API key)
- **High issues fixed:** 3 (HTTP URL, cleartext, MANAGE_EXTERNAL_STORAGE)
- **Medium issues fixed:** 2 (obfuscation, network config)
- **Remaining:** 5 recommendations (certificate pinning, key rotation, etc.)
- **Overall security posture:** Significantly improved from 🔴 to 🟢

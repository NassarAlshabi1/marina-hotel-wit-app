# Build and Release APK - Complete Guide

## 🚀 Overview

This GitHub Action automatically builds, signs, and releases APK files for the Marina Hotel Mobile app.

## 📋 Features

### ✅ Automated Building
- Builds release APK with proper signing
- Generates checksums (SHA256)
- Creates version-named artifacts
- Supports manual and automatic triggers

### ✅ GitHub Releases
- Auto-creates GitHub releases with tags
- Includes detailed release notes
- Uploads APK as release asset
- Generates comprehensive changelog

### ✅ Multiple Architectures
- Universal APK (all architectures)
- Optional split APKs (armeabi-v7a, arm64-v8a, x86_64)
- Smaller file sizes with split builds

### ✅ Quality Checks
- Code analysis
- Dependency verification
- Signing validation
- Build summary reports

## 🔄 Trigger Methods

### 1. Automatic (Push with Tag)
```bash
# Create and push a version tag
git tag v1.2.3
git push origin v1.2.3

# This will automatically:
# - Build release APK
# - Create GitHub Release v1.2.3
# - Upload APK as asset
```

### 2. Automatic (Push to Main)
```bash
# Push changes to main branch affecting mobile/
git push origin main

# This will:
# - Build release APK
# - Upload as artifact (no release)
```

### 3. Manual Trigger (GitHub Actions Tab)
1. Go to **Actions** tab
2. Select **"Build and Release APK"** workflow
3. Click **"Run workflow"**
4. Fill in options:
   - Version: `1.2.3` (optional, uses pubspec.yaml if empty)
   - Create Release: ✅ (yes/no)
5. Click **"Run workflow"**

## 📦 Build Artifacts

### Universal APK
```
marina-hotel-v1.2.3-release.apk          # Main APK file
marina-hotel-v1.2.3-release.apk.sha256   # Checksum file
RELEASE_NOTES.md                         # Release notes
```

### Split APKs (Optional)
```
marina-hotel-armeabi-v7a-release.apk     # ARM 32-bit
marina-hotel-arm64-v8a-release.apk       # ARM 64-bit
marina-hotel-x86_64-release.apk          # x86 64-bit
```

## 📝 Version Management

### From pubspec.yaml
```yaml
version: 1.2.3+4
         ^^^^^ ^^
         |     |
         |     Build number
         Version name
```

### Priority Order
1. Manual input (workflow_dispatch)
2. Git tag (e.g., v1.2.3)
3. pubspec.yaml version

### Version Format
```
Version: 1.2.3
Build Number: 4
Full Version: 1.2.3+4
```

## 🔐 Signing Information

### Keystore Details
```
File: android/app/release.keystore
Alias: marina-hotel-app
SHA-1: 67:12:57:A2:9B:53:FA:71:AC:BC:0F:A8:C9:54:2F:3F:46:0B:A8:1C
```

### Verification
All APKs are signed with the unified keystore for consistent fingerprint across builds.

## 📥 Downloading APKs

### From Artifacts (All Builds)
1. Go to **Actions** tab
2. Click on a workflow run
3. Scroll to **Artifacts** section
4. Download the APK artifact

### From Releases (Tagged Builds Only)
1. Go to **Releases** tab
2. Select desired version
3. Download from **Assets** section

## 📊 Build Summary

After each build, a summary is generated with:
- ✅ APK information (version, size, date)
- ✅ Signing details
- ✅ Download links
- ✅ Release status

Example:
```markdown
## 🎉 Build Complete!

### 📦 APK Information
| Property | Value |
|----------|-------|
| Version | 1.2.3 |
| Build Number | 4 |
| Size | 45.2 MB |
| Build Date | 2025-11-24 15:30:00 |

### 🔐 Signing
| Property | Value |
|----------|-------|
| SHA-1 | 67:12:57:A2:9B:53:FA:71:AC:BC:0F:A8:C9:54:2F:3F:46:0B:A8:1C |
| Package | com.aden.marina |
```

## 🔄 Workflow Steps

### 1. Checkout & Setup
- ✅ Checkout repository with full history
- ✅ Setup Java 17 (Temurin)
- ✅ Setup Flutter (stable channel)
- ✅ Run Flutter Doctor

### 2. Version Management
- ✅ Extract version from pubspec.yaml or input
- ✅ Generate build timestamp
- ✅ Set version variables

### 3. Verify Signing
- ✅ Check key.properties exists
- ✅ Check release.keystore exists
- ✅ Validate signing configuration

### 4. Build Preparation
- ✅ Clean build artifacts
- ✅ Install dependencies (flutter pub get)
- ✅ Run code generation (build_runner)
- ✅ Analyze code (flutter analyze)

### 5. Build APK
- ✅ Build release APK with signing
- ✅ Set version and build number
- ✅ Use unified keystore

### 6. Prepare Artifacts
- ✅ Rename APK with version
- ✅ Generate SHA256 checksum
- ✅ Calculate APK size

### 7. Generate Release Notes
- ✅ Create markdown file
- ✅ Include version info
- ✅ List features and changes
- ✅ Add installation instructions

### 8. Upload Artifacts
- ✅ Upload to workflow artifacts
- ✅ Retention: 90 days
- ✅ Include APK, checksum, and notes

### 9. Create GitHub Release (if tag)
- ✅ Create release with version tag
- ✅ Upload APK as asset
- ✅ Add release notes
- ✅ Set as non-draft, non-prerelease

### 10. Build Summary
- ✅ Generate markdown summary
- ✅ Display in workflow run
- ✅ Include all key information

## 🛠️ Advanced Usage

### Build Split APKs
Triggered manually via workflow_dispatch:
```yaml
# Builds separate APKs for each architecture
# Useful for:
# - Smaller download sizes
# - Architecture-specific optimizations
# - Testing on specific devices
```

### Custom Version
```bash
# Manual workflow with custom version
# GitHub UI > Actions > Run workflow
Version: 2.0.0
Create Release: Yes
```

### Cache Optimization
- Gradle cache: Speeds up Java compilation
- Flutter cache: Speeds up SDK operations
- Pub cache: Speeds up dependency download

## 📈 Performance

### Build Time
- Universal APK: ~8-12 minutes
- Split APKs: ~5-8 minutes each (parallel)

### Optimization Tips
1. ✅ Use cache for Flutter and Gradle
2. ✅ Run split builds in parallel (matrix)
3. ✅ Clean only when necessary
4. ✅ Skip tests in release builds

## 🐛 Troubleshooting

### Build Fails: "keystore not found"
**Solution:**
```bash
# Ensure keystore is committed
git add mobile/android/app/release.keystore
git add mobile/android/key.properties
git commit -m "Add signing files"
git push
```

### Build Fails: "code generation failed"
**Solution:**
```bash
# Run locally first to verify
cd mobile
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
```

### Release Not Created
**Reasons:**
1. No tag pushed (push tag: `v1.2.3`)
2. Manual run with "Create Release" = No
3. Pull request trigger (disabled for releases)

### APK Size Too Large
**Solutions:**
1. Use split APKs (per architecture)
2. Enable minifyEnabled in build.gradle
3. Remove unused resources
4. Use ProGuard rules

## 🔒 Security

### Keystore Security
- ⚠️ **WARNING**: Keystore is currently committed to repository
- 🔐 **Recommended**: Use GitHub Secrets for production
- 📝 **Alternative**: Base64 encode and decrypt in workflow

### Recommended Setup (Production)
```yaml
# 1. Convert keystore to base64
base64 release.keystore > keystore.txt

# 2. Add to GitHub Secrets
# KEYSTORE_BASE64: (content of keystore.txt)
# KEYSTORE_PASSWORD: (see mobile/android/key.properties — should be moved to GitHub Secret)
# KEY_ALIAS: marina-hotel-app
# KEY_PASSWORD: (see mobile/android/key.properties — should be moved to GitHub Secret)

# 3. Update workflow
- name: Setup keystore
  run: |
    echo "${{ secrets.KEYSTORE_BASE64 }}" | base64 -d > release.keystore
```

## 📞 Support

### Issues
- Build failures: Check workflow logs
- Signing issues: Verify keystore files
- Version conflicts: Check pubspec.yaml

### Contact
- GitHub Issues: [Open Issue](https://github.com/$REPO/issues)
- Workflow Runs: [View Actions](https://github.com/$REPO/actions)

## 📚 Related Documentation

- [Flutter Build Modes](https://docs.flutter.dev/testing/build-modes)
- [Android App Signing](https://developer.android.com/studio/publish/app-signing)
- [GitHub Actions](https://docs.github.com/en/actions)

---

**Last Updated:** November 2025  
**Workflow Version:** 2.0.0

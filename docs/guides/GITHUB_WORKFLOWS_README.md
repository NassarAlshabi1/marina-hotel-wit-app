# GitHub Actions Workflows Documentation

This document provides comprehensive information about the GitHub Actions workflows for building Marina Hotel Flutter APKs.

## 🔧 Workflows Overview

### 1. Android Release Build (`android.yml`)
**Purpose**: Builds production-ready APKs for releases and main branch pushes.

**Triggers**:
- Push to `main`, `develop`, `release/**` branches
- Tags starting with `v*` (e.g., `v1.0.0`)
- Pull requests to `main`, `develop`
- Manual trigger with custom API URL

**Features**:
- ✅ Release signing (when secrets are configured)
- ✅ Optimized caching for faster builds
- ✅ Automatic GitHub releases for tags
- ✅ Comprehensive build summaries
- ✅ Error handling and validation

### 2. Android Debug Build (`android-debug.yml`)
**Purpose**: Builds debug APKs for development and testing.

**Triggers**:
- Push to development branches (`feature/**`, `bugfix/**`, `capy/**`)
- Pull requests to `main`, `develop`
- Changes to `mobile/**` directory only
- Manual trigger with custom API URL

**Features**:
- ✅ Fast debug builds (no signing required)
- ✅ Parallel validation job (analyze, format check)
- ✅ Path filtering to avoid unnecessary builds
- ✅ Branch-specific artifact naming

### 3. Auto Assign (`auto-assign.yml`)
**Purpose**: Automatically assigns issues and PRs to repository owner.

**Triggers**:
- New issues opened
- New pull requests opened

## 🔐 Required Repository Secrets

### For Release Builds (android.yml)

Configure these secrets in your repository settings (`Settings > Secrets and variables > Actions`):

| Secret Name | Description | Required | Example |
|-------------|-------------|----------|---------|
| `KEYSTORE_BASE64` | Base64-encoded keystore file | Yes* | `MIIE...` (base64 string) |
| `KEYSTORE_PASSWORD` | Keystore password | Yes* | `your_keystore_password` |
| `KEY_ALIAS` | Key alias name | Yes* | `upload` |
| `KEY_PASSWORD` | Key password | Yes* | `your_key_password` |
| `BASE_API_URL` | Default API endpoint URL | No | `https://api.marinaplaza.com/v1` |

**Note**: Signing secrets are optional. If not provided, debug signing will be used.

### How to Generate Signing Secrets

1. **Create a keystore** (if you don't have one):
   ```bash
   keytool -genkey -v -keystore upload-keystore.jks \
     -keyalg RSA -keysize 2048 -validity 10000 \
     -alias upload
   ```

2. **Convert keystore to base64**:
   ```bash
   base64 -i upload-keystore.jks | pbcopy  # macOS
   base64 -i upload-keystore.jks           # Linux
   ```

3. **Add secrets to GitHub**:
   - Go to `Settings > Secrets and variables > Actions`
   - Click "New repository secret"
   - Add each secret with its corresponding value

## 🚀 Build Artifacts

### Release Builds
- **Name**: `marina-hotel-release-v{build_number}-{commit_short}`
- **File**: `app-release.apk`
- **Retention**: 30 days
- **Auto-release**: For version tags (e.g., `v1.0.0`)

### Debug Builds
- **Name**: `marina-hotel-debug-{branch}-{build_number}-{commit_short}`
- **File**: `app-debug.apk`
- **Retention**: 14 days

## 🛠️ Manual Workflow Triggers

Both workflows support manual triggering with custom parameters:

1. Go to `Actions` tab in your repository
2. Select the desired workflow
3. Click "Run workflow"
4. Optionally specify a custom `BASE_API_URL`

## 📊 Build Status Badges

Add these badges to your README to show build status:

```markdown
![Android Release](https://github.com/Nassaralshabi/marina-hotel-wit-app/actions/workflows/android.yml/badge.svg)
![Android Debug](https://github.com/Nassaralshabi/marina-hotel-wit-app/actions/workflows/android-debug.yml/badge.svg)
```

## 🔍 Troubleshooting

### Common Issues

#### 1. Build Fails with "Android directory not found"
**Cause**: The Flutter project structure is invalid.
**Solution**: Ensure the `mobile/android/` directory exists and contains proper Flutter Android configuration.

#### 2. Code generation fails
**Cause**: Missing or corrupted generated files.
**Solution**: The workflow includes `--delete-conflicting-outputs` flag to handle this automatically.

#### 3. Keystore/signing errors
**Cause**: Invalid or missing signing secrets.
**Solution**: 
- Verify all signing secrets are correctly configured
- Check that the base64-encoded keystore is valid
- Ensure passwords match the keystore configuration

#### 4. Cache-related issues
**Cause**: Corrupted cache or dependency conflicts.
**Solution**: 
- Manual workflow runs can help isolate the issue
- The cache keys are automatically invalidated when dependencies change

### Debug Steps

1. **Check workflow logs**: Go to Actions tab and examine the failed step
2. **Verify project structure**: Ensure `mobile/` directory contains valid Flutter project
3. **Test locally**: Run the same Flutter commands locally to reproduce issues
4. **Clear cache**: Delete and recreate secrets if needed

## 📁 Project Structure

The workflows expect this project structure:

```
marina-hotel-wit-app/
├── mobile/                     # Flutter app directory
│   ├── android/               # Android configuration
│   │   ├── app/
│   │   │   ├── build.gradle   # App-level build configuration
│   │   │   └── upload-keystore.jks  # (Generated during build)
│   │   ├── build.gradle       # Project-level build configuration
│   │   └── key.properties     # (Generated during build)
│   ├── lib/                   # Flutter source code
│   ├── pubspec.yaml           # Flutter dependencies
│   └── test/                  # Tests
├── .github/workflows/         # GitHub Actions workflows
│   ├── android.yml           # Release builds
│   ├── android-debug.yml     # Debug builds
│   └── auto-assign.yml       # Auto assignment
└── README.md
```

## 🔄 Workflow Optimizations

### Performance Improvements
- **Caching**: Aggressive caching of Flutter, Pub, and Gradle dependencies
- **Path filtering**: Debug workflow only runs when `mobile/` directory changes
- **Parallel jobs**: Debug workflow includes parallel validation
- **Timeouts**: Reasonable timeouts to prevent stuck builds

### Resource Management
- **Artifact retention**: Different retention periods for release (30d) vs debug (14d)
- **Build numbers**: Uses GitHub run numbers for consistent versioning
- **Conditional steps**: Signing only runs when secrets are available

## 🆕 Recent Changes

### Fixed Issues
- ✅ Removed conflicting `Run.yml` workflow that created generic Android apps
- ✅ Simplified project preparation logic (removed complex conditionals)
- ✅ Improved error handling and validation
- ✅ Added comprehensive build summaries
- ✅ Optimized caching strategies
- ✅ Added path filtering for debug builds
- ✅ Fixed auto-assign workflow naming

### New Features
- ✅ Parallel validation job for debug builds
- ✅ Better branch filtering
- ✅ Improved artifact naming
- ✅ Comprehensive build summaries
- ✅ Support for manual API URL override

## 📞 Support

If you encounter issues with the workflows:
1. Check this documentation first
2. Examine the workflow logs in the Actions tab
3. Verify your project structure matches expectations
4. Test Flutter commands locally
5. Check repository secrets configuration

## 🔗 Related Documentation

- [Flutter Android Deployment](https://docs.flutter.dev/deployment/android)
- [GitHub Actions Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
- [Android App Signing](https://developer.android.com/studio/publish/app-signing)
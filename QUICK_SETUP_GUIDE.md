# 🚀 Quick Setup Guide for GitHub Actions Workflows

## ⚡ Get Started in 5 Minutes

### Step 1: Verify Project Structure ✅
Your Flutter project should be in the `mobile/` directory:
```
mobile/
├── android/
├── lib/
├── pubspec.yaml
└── test/
```

### Step 2: Configure Repository Secrets (Optional for Debug)

#### For Release Builds Only:
1. Go to `Settings > Secrets and variables > Actions`
2. Add these secrets:

| Secret | Value |
|--------|-------|
| `KEYSTORE_BASE64` | Your base64-encoded keystore |
| `KEYSTORE_PASSWORD` | Your keystore password |
| `KEY_ALIAS` | Your key alias |
| `KEY_PASSWORD` | Your key password |
| `BASE_API_URL` | Your API URL (optional) |

#### Quick Keystore Creation:
```bash
# Create keystore
keytool -genkey -v -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload

# Convert to base64
base64 -i upload-keystore.jks
```

### Step 3: Push Code and Build! 🎉

#### For Debug APK:
- Push to any `feature/`, `bugfix/`, or `capy/` branch
- Or manually trigger in Actions tab

#### For Release APK:
- Push to `main` or `develop` branch  
- Or create a tag: `git tag v1.0.0 && git push origin v1.0.0`

### Step 4: Download Your APK

1. Go to `Actions` tab
2. Click on your workflow run
3. Download APK from "Artifacts" section

## 🎯 Immediate Testing

### Test Debug Build (No Setup Required):
1. Create a branch: `git checkout -b feature/test-build`
2. Make any change in `mobile/` directory
3. Push: `git push origin feature/test-build`
4. ✅ Debug APK will be built automatically!

### Test Release Build:
1. Push to main branch or create a tag
2. ✅ Release APK will be built (uses debug signing without secrets)

## 🔧 Current Workflow Status

| Workflow | Status | Purpose |
|----------|---------|---------|
| `android.yml` | ✅ **Fixed** | Production APK builds |
| `android-debug.yml` | ✅ **Fixed** | Development APK builds |
| `auto-assign.yml` | ✅ **Fixed** | Auto-assign issues/PRs |
| `Run.yml` | ❌ **Disabled** | (Was conflicting - now disabled) |

## 💡 Pro Tips

- **Debug builds** are faster and don't need signing secrets
- **Release builds** are smaller and optimized for production
- Use **manual triggers** to test with different API URLs
- **Path filtering** prevents unnecessary builds when only docs change

## 🆘 Need Help?

- Check [GITHUB_WORKFLOWS_README.md](./GITHUB_WORKFLOWS_README.md) for detailed documentation
- Look at Actions logs if builds fail
- Ensure Flutter project is in `mobile/` directory
- Test Flutter commands locally first

## 🎉 You're All Set!

Your workflows are now optimized and ready to build Flutter APKs automatically. No more conflicts or generic Android apps - just proper Flutter builds! 🚀
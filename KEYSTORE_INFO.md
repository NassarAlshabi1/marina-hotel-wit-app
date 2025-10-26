# Marina Hotel App - Release Keystore Information

## Keystore Details
- **Location**: `mobile/android/app/release.keystore`
- **Key Properties**: `mobile/android/key.properties`
- **Type**: JKS (Java KeyStore)
- **Algorithm**: RSA-2048
- **Validity**: 10,000 days
- **Created**: October 26, 2025

## Signing Configuration
- **Store Password**: `Marina2025SecureKey`
- **Key Alias**: `marina-hotel-app`
- **Key Password**: `Marina2025SecureKey`

## Certificate Fingerprints
- **SHA-1**: `67:12:57:A2:9B:53:FA:71:AC:BC:0F:A8:C9:54:2F:3F:46:0B:A8:1C`
- **SHA-256**: `43:02:86:37:79:43:58:F9:FC:B2:74:C7:94:BE:66:0B:F0:44:F4:C6:29:EB:0B:CA:AD:19:EA:3A:EE:AB:8B:54`

## Certificate Subject
```
CN=Marina Hotel App, OU=IT, O=Marina Hotel, L=Riyadh, ST=Riyadh, C=SA
```

## Usage
- The keystore is committed to the repository and used directly by GitHub Actions
- No base64 encoding/decoding needed
- Compatible with Java 17+ environments
- Workflow automatically verifies keystore presence before building

## Security Note
This keystore is now part of the repository. For production apps, consider using GitHub Secrets for keystore management. However, for internal distribution and development, having the keystore in the repo can be acceptable.
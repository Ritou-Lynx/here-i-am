# Build Guide

Memex ships two flavors: `global` (overseas) and `cn` (China domestic). Currently they only differ by package name; more feature differences will follow.

| Flavor | Android Package | iOS Bundle ID |
|--------|----------------|---------------|
| global | `com.memexlab.memex` | `com.memexlab.memex` |
| cn | `com.memexlab.memex.cn` | `com.memexlab.memex.cn` |

## Prerequisites

- Flutter SDK ≥ 3.6.0
- Xcode 15+ (iOS)
- Android Studio (Android)

```bash
git clone https://github.com/memex-lab/memex.git
cd memex
flutter pub get
cd ios && pod install && cd ..
```

## Run

```bash
# Overseas
flutter run --flavor global

# China
flutter run --flavor cn
```

## Build

### Android

```bash
# APK
flutter build apk --flavor global --release
flutter build apk --flavor cn --release

# App Bundle
flutter build appbundle --flavor global --release
flutter build appbundle --flavor cn --release
```

Output path: `build/app/outputs/flutter-apk/memex_<flavor>_<version>_<build>.apk`

### iOS

```bash
flutter build ipa --flavor global --release
flutter build ipa --flavor cn --release
```

Or use the deploy script:

```bash
./deploy_ios.sh global
./deploy_ios.sh cn
```

## Signing

### Android

Each flavor uses its own signing key. Config files live under `android/`:

| Flavor | Properties File | Keystore File |
|--------|----------------|--------------|
| global | `android/key-global.properties` | `android/app/memex-global-release.keystore` |
| cn | `android/key-cn.properties` | `android/app/memex-cn-release.keystore` |

Properties file format:

```properties
storeFile=memex-<flavor>-release.keystore
storePassword=<your_password>
keyAlias=<your_alias>
keyPassword=<your_password>
```

Generate a new keystore:

```bash
keytool -genkeypair -v \
  -keystore android/app/memex-<flavor>-release.keystore \
  -alias <your_alias> \
  -keyalg RSA -keysize 2048 \
  -validity 10000
```

View signing info (MD5 / SHA1 / SHA256):

```bash
keytool -list -v -keystore android/app/memex-<flavor>-release.keystore
```

> ⚠️ Keystore and properties files are excluded in `.gitignore`. Never commit them to the repository.

### iOS

iOS signing is managed through your Apple Developer account. Register the App ID (`com.memexlab.memex.cn`) and create Provisioning Profiles in Xcode or the Apple Developer Portal.

## Flavor Detection in Dart

Use `AppFlavor` to branch on the current flavor at runtime:

```dart
import 'package:memex/config/app_flavor.dart';

if (AppFlavor.isCN) {
  // China-specific logic
}
```

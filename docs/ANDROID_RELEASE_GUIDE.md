# Android release guide

Set `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD` only in your secure CI or local environment. Do not commit a keystore or passwords. Then run `flutter build apk --release`. The expected output is `build/app/outputs/flutter-apk/app-release.apk`.

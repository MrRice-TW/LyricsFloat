# Android release signing / Android 固定簽章

The release APK uses a permanent private key. Never commit the keystore, password, or `key.properties` to Git. GitHub Actions reads the key only from repository Actions secrets and refuses to publish an APK when signing is missing or its certificate does not match the fingerprint below.

發行 APK 使用永久私鑰。請勿把金鑰、密碼或 `key.properties` 提交到 Git。GitHub Actions 只從儲存庫的 Actions Secrets 讀取，缺少簽章或憑證指紋不符就會停止發行。

## Local files / 本機檔案

- `android/signing/release-keystore.jks`: private signing key / 私有簽章金鑰
- `android/signing/password.txt`: key password / 金鑰密碼
- `android/key.properties`: local Gradle configuration / 本機建置設定

These files are ignored by Git. A second copy of the keystore and password is stored in `~/Documents/LyricsFloat-signing-backup` on the development Mac. Keep another encrypted or offline backup under your control. GitHub Secrets cannot be read back as a backup. If the private key is lost, future APKs cannot update apps installed with this certificate.

這些檔案都被 Git 忽略。開發用 Mac 的 `~/Documents/LyricsFloat-signing-backup` 有第二份金鑰與密碼。請再自行保留加密或離線備份；GitHub Secrets 設定後無法讀回，不能當作備份。遺失私鑰後，新 APK 無法更新已使用這張憑證的安裝版本。

## Upload to GitHub Actions / 上傳到 GitHub Actions

On the development Mac, install [GitHub CLI](https://cli.github.com/) if needed, sign in, then run:

```sh
brew install gh
gh auth login
./scripts/upload-android-signing-secrets.sh
```

The script uploads the keystore as `ANDROID_KEYSTORE_BASE64` and its password as `ANDROID_KEYSTORE_PASSWORD` to **MrRice-TW/LyricsFloat → Settings → Secrets and variables → Actions**. It reads both values from files through standard input, without printing them or putting them in shell history. Confirm that both names appear in the repository's Actions secrets before pushing the next `v*` tag.

腳本會把金鑰與密碼安全地上傳至 **MrRice-TW/LyricsFloat → Settings → Secrets and variables → Actions**，名稱分別是 `ANDROID_KEYSTORE_BASE64` 和 `ANDROID_KEYSTORE_PASSWORD`。它從本機檔案讀取，不會輸出內容或把內容寫進指令歷史。推送下一個 `v*` 標籤前，請確認兩項 Secret 都已出現在儲存庫。

## Certificate / 憑證

Expected SHA-256 certificate fingerprint:

`0B:EF:42:53:55:C9:21:31:1B:0B:4B:68:69:73:09:03:F9:0C:A7:EE:03:34:34:DE:27:D2:24:B3:92:E1:9D:E1`

This fingerprint is public and can be used to verify releases. APKs through `v1.2.3-beta` were signed with temporary debug keys. Back up or sync your lyrics, uninstall that version, and install the first APK signed by this permanent key once. Future APKs using this key can upgrade in place.

指紋可公開，用於核對發行檔。`v1.2.3-beta` 及以前由臨時測試金鑰簽署；先備份或同步歌詞，移除舊版，安裝第一個永久簽章 APK。之後只要使用同一把金鑰，即可覆蓋升級。

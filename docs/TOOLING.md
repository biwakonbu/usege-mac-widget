# Tooling Guide

`usege-mac-widget` のセットアップ/運用で使う CLI ツールの仕様です。

## 前提
- macOS
- Xcode (`xcodebuild` が使えること)
- Chrome
- （任意）`xcodegen`

## Makefile ターゲット

`/Users/biwakonbu/github/usege-mac-widget/Makefile`

### `make install EXTENSION_ID=<id>`
- 目的: Native Host + Usege.app のビルド、manifest + アプリ配置を一括実行
- 内部で実行:
  1. `make build-native-host`
  2. `./scripts/install_native_host.sh <host_binary> <EXTENSION_ID>`
  3. `make install-app`
- 配置先（既定）:
  - `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.usege.sync.host.json`
  - `~/Applications/Usege.app`
- 失敗条件:
  - `EXTENSION_ID` 未指定
  - `xcodebuild` 失敗

### `make build-native-host`
- 目的: `usege-native-host` バイナリのみビルド
- 出力:
  - `.derived/Build/Products/Debug/usege-native-host`

### `make build-app`
- 目的: `Usege.app` のみビルド
- 出力:
  - `.derived/Build/Products/Debug/Usege.app`

### `make install-app [INSTALL_DIR=...]`
- 目的: ビルド済み `Usege.app` をローカル配置
- 既定配置先:
  - `~/Applications/Usege.app`
- 上書き:
  - `INSTALL_DIR=/path/to/apps`

### `make run-app`
- 目的: `Usege.app` を起動
- 挙動:
  - `~/Applications/Usege.app` があればそれを起動
  - なければ `.derived/.../Usege.app` を起動

### `make reset-data`
- 目的: ローカル保存データを削除して誤データを完全初期化する
- 削除対象:
  - `~/Library/Application Support/Usege/usege.sqlite3*`
  - `~/Library/Application Support/Usege/widget_snapshot.json`
  - `~/Library/Application Support/UsegeNativeHost/inbox/*.json`
  - `defaults delete com.usege.macwidget.app provider_error_state_v1`（存在時のみ）

### `make test`
- 目的: Swift Unit Test + Chrome parser test をまとめて実行
- 内部で実行:
  - `make test-swift`
  - `make test-extension`

## スクリプト仕様

`/Users/biwakonbu/github/usege-mac-widget/scripts/install_native_host.sh`

### 使い方
```bash
./scripts/install_native_host.sh <native_host_binary_path> <chrome_extension_id>
```

### 環境変数
- `NATIVE_MESSAGING_HOST_DIR`:
  - 指定すると manifest 出力先を上書き
  - 未指定時は Chrome 既定パスを使用

### 生成ファイル
- `com.usege.sync.host.json`
- `allowed_origins` には `chrome-extension://<EXTENSION_ID>/` を設定

## 拡張 ID の取得手順
1. `chrome://extensions` を開く
2. Developer mode を ON
3. `Load unpacked` で `/Users/biwakonbu/github/usege-mac-widget/chrome-extension` を選択
4. 拡張カードの `ID` をコピー
5. 見えない場合は「詳細」ページの URL `?id=<EXTENSION_ID>` から取得

## トラブルシュート

### `Native host not found` / `Specified native messaging host not found`
- `make install EXTENSION_ID=<id>` を再実行
- manifest の配置先と `path` を確認

### `Access to the specified native messaging host is forbidden`
- `EXTENSION_ID` が誤っている可能性が高い
- 拡張を再読込して ID を再取得し、再インストール

### manifest のみテスト用に別ディレクトリへ出したい
```bash
NATIVE_MESSAGING_HOST_DIR=/tmp/usege-host \
make install EXTENSION_ID=<id>
```

### アプリ配置先を変更したい
```bash
make install EXTENSION_ID=<id> INSTALL_DIR=/path/to/apps
```

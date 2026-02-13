# usege mac widget MVP

Mac ネイティブの MenuBar + Widget で AI サービス使用量を可視化する MVP 実装です。

## 実装内容
- `UsegeApp` (SwiftUI MenuBar app)
- `UsegeWidgetExtension` (WidgetKit Medium widget)
- `UsegeNativeHost` (Chrome Native Messaging host)
- `chrome-extension` (MV3 extension, 5分同期)
- SQLite 永続化 + Keychain (`installation_id`) + Widget JSON 生成

## 対応プロバイダ
- Codex (`chatgpt.com/codex/settings/usage`)
- Claude
- Cursor
- Gemini
- Z.ai (`z.ai/manage-apikey/subscription`)
- Antigravity: MVP除外

## セットアップ
### 最短（`make install`）
1. Chrome 拡張を読み込み、拡張 ID を取得
- `chrome://extensions` を開く
- Developer mode を ON
- `Load unpacked` で `chrome-extension` を指定
- 拡張カードの `ID: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx` を控える
  - 見えない場合: 「詳細」を開いて URL の `?id=<EXTENSION_ID>` から取得

2. Native Host をビルド + manifest 配置
```bash
make install EXTENSION_ID=<YOUR_EXTENSION_ID>
```

3. UsegeApp を起動
```bash
open .derived/Build/Products/Debug/Usege.app
```

4. 反映確認（任意）
- `chrome://extensions` で `usege sync bridge` を一度リロード
- `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.usege.sync.host.json` が存在することを確認

### 手動
1. プロジェクト生成
```bash
xcodegen generate
```

2. Native host をビルド
```bash
xcodebuild -project UsegeMacWidget.xcodeproj -scheme UsegeNativeHost -configuration Debug -derivedDataPath .derived build
```

3. Chrome 拡張を読み込み
- `chrome://extensions` を開く
- Developer mode を ON
- `Load unpacked` で `chrome-extension` を指定
- 拡張カードの `ID: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx` を控える（見えない場合は「詳細」URLの `?id=...` を参照）

4. Native Messaging manifest をインストール
```bash
./scripts/install_native_host.sh \
  "$(pwd)/.derived/Build/Products/Debug/usege-native-host" \
  "<YOUR_EXTENSION_ID>"
```

5. UsegeApp を起動
```bash
open .derived/Build/Products/Debug/Usege.app
```

## 運用フロー
- Chrome 拡張が 5 分ごとに対象タブから DOM を抽出
- Native host (`com.usege.sync.host`) に `usage_snapshot` / `sync_error` を送信
- host が inbox に JSON を保存
- UsegeApp が inbox を取り込み、SQLite 反映 + Widget snapshot 再生成

## テスト
### Chrome parser
```bash
npm --prefix chrome-extension test
```

### Xcode unit tests
```bash
xcodebuild -project UsegeMacWidget.xcodeproj -scheme UsegeAppTests -destination 'platform=macOS' test
```

## 注意
- DOM parser は provider ごとに `*.v1` バージョンで管理。
- 取得失敗時は `AUTH_REQUIRED` / `PARSER_BROKEN` / `HOST_UNAVAILABLE` を扱う。
- Widget の stale 判定は `generated_at` / `captured_at` から 10 分超を stale とする。

## ツールドキュメント
- `make` / `install_native_host.sh` の仕様と運用: `docs/TOOLING.md`

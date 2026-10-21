# HermesMonitor

Hermes Agent の情報を表示する macOS メニューバーアプリです。メニューバーの稲妻アイコンから稼働状態、RSSメモリ、OS、作業ディレクトリ、作業マシーン、稼働時間、設定中のモデル、実行リース、cron予定を確認できます。

## ビルドと起動

```sh
cd /Volumes/V_INBOX-1/V_INBOX/HermesMonitor
zsh Scripts/build-app.sh
open build/HermesMonitor.app
```

`Package.swift` は Xcode でも開けます。アプリは `build/HermesMonitor.app` に生成されます。

## データと制限

- 設定モデル: `~/.hermes/config.yaml` の `model.default`。
- モデル変更: プロバイダーとモデルを選び「適用」を押します。Hermes本体の切替・保存処理を使い、新しいセッションから反映されます。
- ON/OFF: Hermes公式CLIの `hermes gateway start` / `hermes gateway stop` を呼び出します。進行中のGatewayタスクは停止時に中断されます。
- プロバイダー選択: 設定済み・認証済みのプロバイダーをプルダウン表示します。変更時はHermes本体の `switch_model` と `persist_model_selection` を使用し、接続先・APIモードも一緒に更新します。
- 通知: `~/.hermes/logs/errors.log` を読み、現在のGateway起動以降の警告・エラーを日本語で表示します。前回以前の警告やRemote Login停止後のSSH警告は「過去・解決済みの通知」内に分けます。macOS 15以降はmacOSの翻訳機能を使用し、利用できない場合は日本語の要約を表示します。通知本文は省略せず折り返し、パネル全体をスクロールできます。「原文を表示」で全文を確認できます。Hermes Desktop内部だけの一時的なトーストは対象外です。
- 稼働とメモリ: Hermes プロセスの `ps` 結果を使用します。メモリは検出した Hermes プロセスの RSS 合計です。
- OS: このMacのmacOSバージョン。作業マシーン: 稼働中Gatewayのホスト名を優先し、取得できない場合はこのMacのホスト名を表示します。
- 作業ディレクトリ: 実行中セッションの `cwd` を優先し、なければ直近セッションの `cwd` を「直近のセッション」と明示して表示します。セッションに `cwd` がなければ「—」です。
- 稼働時間: 稼働中Gatewayのハートビートに記録された開始時刻から計算します。Gatewayが確認できない場合は「—」です。
- 実行中: `~/.hermes/state.db` の有効な `session_turn_leases`。実行リースがないアイドルセッションは表示しません。
- 実行予定: `~/.hermes/cron/jobs.json` の有効なジョブ。ファイルがなければ空表示です。
- Ollama などローカルモデルにはAPI利用枠がないため「利用枠なし」と表示します。他プロバイダーは取得できない場合、数値を推測せず「プロバイダーから取得不可」と表示します。

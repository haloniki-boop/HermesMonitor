# Tailscale 経由のリモート接続

このMacの Hermes API と SSH は、Tailscale Serve で tailnet 内だけに公開する。
LAN / インターネットへ直接待ち受けない。

| サービス | 接続先 | Mac内の待受 | 認証 |
|---|---|---|---|
| SSH | `hal-mini.tailf1db88.ts.net:22` | `127.0.0.1:2222` | 公開鍵のみ |
| Hermes API | `http://hal-mini.tailf1db88.ts.net:8642/v1` | `127.0.0.1:8642` | `API_SERVER_KEY` Bearer |

Codex Pet からこの API を使う手順は [[Hermes_Agent_Mac_mini_設定情報]] を参照する。Tailscale IP の例は `100.78.3.66`。

macOSの標準「リモートログイン」はオフのまま。SSHはユーザーLaunchAgent
`~/Library/LaunchAgents/local.hermes.tailnet-sshd.plist` が起動する。
その設定・ホスト鍵・接続元公開鍵は `~/.hermes/ssh/` にある。
ログイン中のユーザーセッションで稼働するため、ログアウト中はSSHに接続できない。

接続元Macから:

```sh
ssh -i ~/.ssh/id_ed25519_hermes -o IdentitiesOnly=yes halmini@hal-mini.tailf1db88.ts.net
```

初回接続時のSSHホスト鍵フィンガープリント:
`SHA256:RmBkps0m4YBTclTSwBJQM/LQ+v3tP56MKPUdF36uyg8`

Hermes APIキーは `~/.hermes/.env` の `API_SERVER_KEY` に保存されている。
値をチャットやリポジトリに貼らないこと。APIはエージェントのターミナル操作を含む
強い権限を与えるため、接続元Macでのみ安全に保管する。

サーバー側での状態確認:

```sh
/Applications/Tailscale.app/Contents/MacOS/Tailscale serve status
launchctl print gui/$(id -u)/local.hermes.tailnet-sshd
hermes gateway status
```

Tailscale経由の公開を停止する場合:

```sh
/Applications/Tailscale.app/Contents/MacOS/Tailscale serve --tcp=22 off
/Applications/Tailscale.app/Contents/MacOS/Tailscale serve --tcp=8642 off
```

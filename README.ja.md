# Windows Maintenance Skill

[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md)

[MIT License](LICENSE) · [CI](https://github.com/Sorasukiawa/windows-maintenance-skill/actions)

Codex 向けの Windows メンテナンス用 skill です。読み取り専用の情報収集、ディレクトリ分類、JSON／中国語 Markdown レポートの生成、変更前後のスナップショット比較を行う PowerShell ツールが含まれています。

初回の公開プレビューです。「情報を取得できた」「システムが正常」「更新が成功した」「不具合が解消した」を別々に判断し、確認できる証拠を残します。スクリプトがすべてのアプリを自動更新したり、キャッシュを削除したり、ファームウェアを書き換えたりすることはありません。

## 主な機能

- System、Storage、Drivers、Software、Startup、Stability、Security の 7 分野をローカルで調査。
- 時間と項目数に上限を設けたディレクトリ調査。ジャンクションなどの再解析ポイントを除外し、一部の依存関係キャッシュ、生成物、プロジェクト情報、ユーザーデータを分類。
- 失敗、不完全な結果、空の結果、タイムアウトを区別。不明な値をゼロや正常として扱わない設計。
- 同じ PC・取得元・範囲の完全な結果だけを比較。ユーザーに依存する情報ではアカウントと権限昇格状態も確認。
- 個別更新、設定移行、ドライバーの割り当て確認、修復後の再検証、障害調査資料の保全、復元手順を案内。

マザーボードの BIOS を一律に除外するルールはありません。呼び出す際に今回の対象範囲を指定してください。実際の書き換えには、対象機器への操作権限、メーカーが示す適用条件、復旧手段の確認が必要です。

## インストールと利用

Codex で次のように依頼します。

```text
$skill-installer https://github.com/Sorasukiawa/windows-maintenance-skill の skills/windows-maintenance をインストールしてください。
```

手動の場合は、リポジトリ内の `skills/windows-maintenance` を、利用するホストが対応する skill ディレクトリへコピーします。同名の skill がある場合は、設定を比較してバックアップを取ってください。現在の Codex 公式ドキュメントでは、ユーザー用の場所として `~/.agents/skills` が案内されています。[公式ドキュメント](https://learn.chatgpt.com/docs/build-skills)

```text
$windows-maintenance この Windows PC を調査し、レポートと更新候補をまとめてください。
$windows-maintenance この PC を更新・整理してください。今回はマザーボードの BIOS を更新しないでください。
```

4 言語の紹介は同じ機能を説明しています。skill 本文は主に簡体字中国語で、自動生成される Markdown レポートも中国語です。スクリプトは Codex とは独立して Windows PowerShell 5.1 または PowerShell 7 で実行できます。

## スクリプトの実行とテスト

リポジトリのルートで実行します。

```powershell
$runDir = Join-Path $env:TEMP ('maintenance-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runDir -ErrorAction Stop | Out-Null
& .\skills\windows-maintenance\scripts\Collect-MaintenanceSnapshot.ps1 -OutputBase (Join-Path $runDir 'before')
```

新しい JSON と Markdown レポートを生成するだけで、更新のインストールや PC のクリーンアップは行いません。ディレクトリ調査と変更前後の比較例は[簡体字中国語の説明](README.zh-CN.md)、詳細な引数は[ツール文書](skills/windows-maintenance/references/automation.md)を参照してください。

```powershell
& .\tests\Invoke-CI.ps1 -WorkDirectory (Join-Path $env:TEMP ('maintenance-ci-' + [guid]::NewGuid().ToString('N')))
```

CI は Windows 上の PowerShell 5.1 と 7 で、構文と参照先の検査、新機能の 31 項目、既存ヘルパーの 15 項目を検証します。テストには隔離したデータを使用し、実行環境の更新・修復・クリーンアップは行いません。GitHub 上での実行結果は Actions ページで確認できます。

## 制限とプライバシー

オンラインの更新候補、Store／ポータブルアプリ、実行中のプログラムのバージョン、完全な SMART／温度情報、DISM／SFC の判定、ファームウェアの適合性、設定の反映、負荷時の安定性は別途確認が必要です。ローカルでのテスト成功は、すべての PC やメーカーの更新ツールへの対応を保証しません。

親子ディレクトリの容量は重複するため、そのまま合計できません。論理サイズは解放可能な容量ではなく、分類結果は削除の許可を意味しません。レポートは既存ファイルを上書きしません。

レポートにはローカルパス、ユーザーや機器の識別情報、イベント内容が含まれる場合があります。手元で保管し、問題を報告する際は機密情報を除いた最小限の再現データだけを添付してください。完全なレポート、ダンプ、認証情報は公開しないでください。[SECURITY.md](SECURITY.md) と [CONTRIBUTING.md](CONTRIBUTING.md) も参照してください。

Codex の支援を受けて開発し、スクリプトテストと独立した利用シナリオで確認しています。再現可能な修正や他の環境での検証結果を歓迎しますが、サポートの応答時間は保証していません。[MIT License](LICENSE) で公開しています。

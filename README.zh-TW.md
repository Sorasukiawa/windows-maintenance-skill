# Windows Maintenance Skill

[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md)

[MIT License](LICENSE) · [CI](https://github.com/Sorasukiawa/windows-maintenance-skill/actions)

供 Codex 使用的 Windows 電腦維護 skill，提供可獨立執行的 PowerShell 工具：唯讀盤點、目錄分類、JSON／中文 Markdown 報告，以及前後快照比較。

目前為首次公開預覽版。它將「查詢完成」「系統健康」「更新成功」與「故障已修復」分開判斷，保留可核對的證據。腳本不會自動更新所有軟體、刪除快取或寫入韌體。

## 主要功能

- 七類本機盤點：System、Storage、Drivers、Software、Startup、Stability、Security。
- 有時間與項目數限制的目錄統計，略過重新解析點（如目錄連接），區分部分相依套件快取、產生檔、專案中繼資料與使用者資料。
- 記錄失敗、不完整、空結果與逾時；未知值保持未知。
- 僅比較同一電腦、相同來源的完整快照；與使用者相關的查詢也核對帳號及提升權限狀態。
- 提供精確更新、設定遷移、驅動程式繫結、修復複查、故障證據保留及還原流程指引。

主機板 BIOS 沒有固定排除規則。每次呼叫時指定範圍；實際寫入韌體仍須符合具體裝置的授權、官方適用條件與復原要求。

## 安裝與使用

在 Codex 中輸入：

```text
$skill-installer 從 https://github.com/Sorasukiawa/windows-maintenance-skill 安裝 skills/windows-maintenance
```

也可下載倉庫，將 `skills/windows-maintenance` 複製到宿主支援的技能目錄。已有同名 skill 時先比對及備份；目前 Codex 官方文件列出的使用者目錄為 `~/.agents/skills`。[官方說明](https://learn.chatgpt.com/docs/build-skills)

```text
$windows-maintenance 全面檢查這台 Windows 電腦，先整理報告與更新候選。
$windows-maintenance 更新並清理這台電腦，這次不更新主機板 BIOS。
```

四語介紹對應相同功能；skill 正文目前仍以簡體中文為主，自動產生的 Markdown 報告也是中文。腳本可脫離 Codex，在 Windows PowerShell 5.1 或 PowerShell 7 執行。

## 獨立執行與測試

在倉庫根目錄執行：

```powershell
$runDir = Join-Path $env:TEMP ('maintenance-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runDir -ErrorAction Stop | Out-Null
& .\skills\windows-maintenance\scripts\Collect-MaintenanceSnapshot.ps1 -OutputBase (Join-Path $runDir 'before')
```

這只會產生新的 JSON 與 Markdown 報告，不會安裝更新或清理電腦。更多目錄統計及前後比較範例見[簡中說明](README.zh-CN.md)，完整參數見[工具文件](skills/windows-maintenance/references/automation.md)。

```powershell
& .\tests\Invoke-CI.ps1 -WorkDirectory (Join-Path $env:TEMP ('maintenance-ci-' + [guid]::NewGuid().ToString('N')))
```

CI 在 Windows 上分別使用 PowerShell 5.1 與 7，執行語法／引用檢查、31 項新版行為斷言及 15 項原有輔助函式斷言。測試只使用隔離資料，不更新、修復或清理測試主機。託管執行結果以倉庫 Actions 頁面為準。

## 限制與隱私

線上更新候選、Store／可攜式軟體、執行中程式版本、完整 SMART／溫度、DISM／SFC 結論、韌體適用性、設定是否生效及負載穩定性，都需要另外驗證。本機測試不代表所有電腦或廠商更新工具均已驗證。

父子目錄大小不能直接相加；邏輯大小不等於可釋放空間。分類不授予刪除許可，報告也不覆寫既有證據。

報告可能包含本機路徑、使用者／裝置識別資訊及事件內容。請留在本機，回報問題時只提供去識別化的最小重現資料，不公開完整報告、轉儲或憑證。詳見 [SECURITY.md](SECURITY.md) 與 [CONTRIBUTING.md](CONTRIBUTING.md)。

專案由 Codex 協助開發，並經腳本測試與獨立情境複核。歡迎提供可重現的修正與更多機器上的驗證結果；目前不承諾支援回應時間。採用 [MIT License](LICENSE)。

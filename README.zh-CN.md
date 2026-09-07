# Windows Maintenance Skill

[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md)

[MIT License](LICENSE) · [CI](https://github.com/Sorasukiawa/windows-maintenance-skill/actions)

面向 Codex 的 Windows 电脑维护 skill：提供可运行的只读采集、目录盘点和前后对比脚本，并指导软件、驱动、系统修复及固件维护中的验证和回退。

当前是首次公开预览。它的价值在于把“采集完成”“设备健康”“更新成功”和“故障已修复”分开处理，保留可核查的证据。脚本不会自动升级所有软件、清空缓存或刷写固件。

## 能做什么

| 能力 | 实现 |
|---|---|
| 本地整机盘点 | Windows、主板/BIOS、CPU/内存、磁盘、驱动、软件登记、自启动、事件与 Defender 状态 |
| 目录分类 | 识别部分依赖/生成缓存、项目元数据与用户资料；统计逻辑大小并跳过连接点 |
| JSON 和中文报告 | 保留查询来源、错误、时间、完整性及未知值 |
| 前后对比 | 同机、同来源、同用户/权限范围下比较；失败或不完整时输出 Incomparable |
| 维护指导 | 精确更新、配置迁移、驱动绑定、系统修复复查、清理证据和回退 |

主板 BIOS 没有固定排除规则。每次调用时说明范围；实际更新或刷写按具体对象的授权、官方适用性和恢复条件执行。

## 安装与调用

在 Codex 中使用内置 `$skill-installer`，让它从本仓库安装 `skills/windows-maintenance`。也可下载仓库，将该文件夹复制到当前 Codex 支持的用户技能目录；已有同名 skill 时先比较并备份，避免覆盖定制。当前官方文档列出的用户目录是 `~/.agents/skills`，其他宿主请使用其实际支持的位置。[Codex 技能文档](https://learn.chatgpt.com/docs/build-skills)

```text
$skill-installer 从 https://github.com/Sorasukiawa/windows-maintenance-skill 安装 skills/windows-maintenance
```

示例请求：

```text
$windows-maintenance 全面检查这台 Windows 电脑，先整理报告和更新候选。
$windows-maintenance 更新和清理这台电脑，这次不更新主板 BIOS。
$windows-maintenance 最近有黑屏，先保留故障证据，再处理可独立完成的软件更新。
```

四语介绍对应相同功能；Skill 正文目前仍以简中为主，自动生成的 Markdown 报告也是中文。PowerShell 脚本不依赖模型，可单独运行。推荐先阅读 [SKILL.md](skills/windows-maintenance/SKILL.md) 和[工具范围](skills/windows-maintenance/references/automation.md)。

## 独立运行脚本

在仓库根目录执行，要求 Windows PowerShell 5.1 或 PowerShell 7。基本采集不自动提权；权限失败会明确记录。报告输出到新文件，不覆盖已有证据。

```powershell
$runDir = Join-Path $env:TEMP ('maintenance-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runDir -ErrorAction Stop | Out-Null
$scripts = Join-Path (Get-Location) 'skills\windows-maintenance\scripts'

& (Join-Path $scripts 'Collect-MaintenanceSnapshot.ps1') -OutputBase (Join-Path $runDir 'before')

# 这里只用仓库本身演示目录统计；换成你明确选定的目录。
& (Join-Path $scripts 'Measure-MaintenanceDirectories.ps1') -Path (Get-Location).Path -OutputBase (Join-Path $runDir 'space')

# 完成维护后，重新采集相关分组，再比较相同来源的结果。
& (Join-Path $scripts 'Collect-MaintenanceSnapshot.ps1') -Groups System,Storage,Drivers,Software -OutputBase (Join-Path $runDir 'after')
& (Join-Path $scripts 'Compare-MaintenanceSnapshots.ps1') -BeforePath (Join-Path $runDir 'before.json') -AfterPath (Join-Path $runDir 'after.json') -OutputBase (Join-Path $runDir 'diff')
```

`ReportDepth` 只限制目录报告层级，统计仍读取更深的普通文件。父子目录大小不能相加；逻辑大小与卷空闲变化也不等于可释放空间。分类结果不授权删除。

## 验证与限制

CI 在 Windows 上分别使用 PowerShell 5.1 和 PowerShell 7，运行语法/引用检查、31 项新版行为测试及 15 项原有辅助函数测试。所有测试只使用临时夹具，包含连接点、失败/超时、未知值、不同来源、大小写参数和报告保存场景。

```powershell
& .\tests\Invoke-CI.ps1 -WorkDirectory (Join-Path $env:TEMP ('maintenance-ci-' + [guid]::NewGuid().ToString('N')))
```

本地验证包含 Windows 11 上的七组采集和两个 PowerShell 版本；不代表所有硬件、Windows 版本或更新器都经过测试。GitHub Actions 的实际结果以仓库 Actions 页面为准。

以下内容仍需要维护时按具体目标补证：在线更新候选、Store/便携软件、活动进程版本、完整 SMART/温度、DISM/SFC 结论、固件适用性、应用配置采用及游戏/负载稳定性。健康标签不能代替硬件测试，安装器成功不能代替实际版本与功能验证。

报告会包含本机路径、软件/设备标识、用户 SID 和事件内容。保留在本机；提交 issue 前提供脱敏的最小复现，勿上传完整系统报告、转储、令牌或账户数据。参见 [SECURITY.md](SECURITY.md)。

## 贡献

欢迎提交带复现步骤和回归测试的修正，尤其是更多硬件/厂商工具的验证结果。先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。当前不承诺厂商级支持或响应时间。

项目在 Codex 辅助下开发，并经过脚本测试和独立场景复核。公开仓库仅包含通用技能、代码与测试，不包含开发机器的维护报告。采用 [MIT License](LICENSE)。

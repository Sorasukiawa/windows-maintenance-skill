# 采集与对比工具

适用于 Windows PowerShell 5.1 与 PowerShell 7。无第三方运行库要求，无安装、删除、注册表修改、服务停止、固件刷写或自动提权。报告路径必须是现有本地目录下的新文件，工具拒绝覆盖已有报告。

## 一次可复用的流程

`$skillDir` 为当前 skill 所在目录，`$runDir` 为本轮工作目录；不要硬编码某位用户的个人路径。

```powershell
$runDir = Join-Path (Get-Location) ('work\maintenance-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $runDir -ErrorAction Stop | Out-Null
$scripts = Join-Path $skillDir 'scripts'
& (Join-Path $scripts 'Collect-MaintenanceSnapshot.ps1') -OutputBase (Join-Path $runDir 'before')

# 只在本轮已选定目录时扫描；以下路径变量须来自实际用户范围。
& (Join-Path $scripts 'Measure-MaintenanceDirectories.ps1') -Path $selectedDirectories -OutputBase (Join-Path $runDir 'space-before')

# 完成已授权变更后，只复查相关分组；同一比较中的来源需要一致。
& (Join-Path $scripts 'Collect-MaintenanceSnapshot.ps1') -Groups System,Storage,Drivers,Software -OutputBase (Join-Path $runDir 'after')
& (Join-Path $scripts 'Compare-MaintenanceSnapshots.ps1') -BeforePath (Join-Path $runDir 'before.json') -AfterPath (Join-Path $runDir 'after.json') -OutputBase (Join-Path $runDir 'diff')
```

如果需要可比较的空间变化，使用相同目录与 ReportDepth 再扫描一次，将两份 `space-*.json` 交给比较脚本。

## 覆盖范围与限制

| 分组 | 自动采集 | 仍要按需补证 |
|---|---|---|
| System | Windows 构建、主板、BIOS、CPU、内存、常见待重启信号 | DISM/SFC、恢复环境、厂商重启要求、BIOS 更新适用性 |
| Storage | 固定卷总量/空闲量、磁盘型号/固件/健康标签 | 全量 SMART、实际温度、负载和厂商固件候选 |
| Drivers | PnP 绑定 INF/版本/签名字段及问题码 | 官方适用版本、硬件功能、驱动回退资源 |
| Software | 当前用户及机器 32/64 位卸载登记 | Store、便携版、其他用户、活动进程版本、自更新器和在线候选 |
| Startup | WMI 启动登记、非 Microsoft 路径的计划任务及参数 | StartupApproved、生效状态、入口是否仍有用途 |
| Stability | 指定窗口 System 日志严重/错误事件及原 XML | 转储分析、Application/其他频道、负载稳定性和根因 |
| Security | Defender 自报状态、产品与签名版本 | 第三方防护状态和完整安全审计 |

每组通过隔离的 PowerShell Job 采集，默认 45 秒，`-GroupTimeoutSeconds` 可设 1–60 秒；超时标为 TimedOut，继续其他组。超时组不保留尚未形成完整查询记录的中间输出，不作为空结果处理。权限不足记 Failed/Partial，不自动提权重试。

事件默认 14 天、最多 200 条。达到上限或日志可用历史不足时标 Partial；即使完整，也只说明所选频道、级别和窗口。滚动事件窗口不生成移除/恢复差异。

目录默认共用 30 秒、最多访问 100000 个条目；`ReportDepth` 默认 3，仅限制输出层级，统计会继续读取更深层的普通文件。时间上限是协作式的，单次文件系统 I/O 阻塞可能超时；不是强制进程截止。拒绝重叠根目录及根路径上的重解析点，枚举中跳过链接。运行期间不要把被扫目录改成连接点。

目录行包含子目录，不能把父子大小相加；只能合计互不重叠的 `RootSummary`。逻辑大小可能重复计算硬链接，不等于物理占用或可回收量。权限失败、条目上限及超时使结果不完整。

分类是筛选线索：有 package.json 的 node_modules 标为 DependencyCache；__pycache__ 为 GeneratedPythonCache；.git 为 RepositoryMetadata；模型、存档、下载等标为 UserData；build/dist 需要项目标记仍只标 BuildOutputReview；其余 NeedsReview。所有条目的 `DeletionAuthorized` 均为 false。删除仍需核对用途、当前占用、配置与授权，不运行第三方深度清理预设。

## 数据格式与比较

快照 `Schema=windows-maintenance.snapshot/v1`：

- `ToolVersion`：采集工具版本；`MachineKey`：本机 MachineGuid 的 SHA-256，仅用于本机快照关联，仍不应公开分享；读取失败为 null，禁止自动跨快照对比。
- `CapturedUtc`：整份采集结束时间；每个 Collection 有各自 Started/Finished。
- `Collections[]`：Name、Scope、QueryStatus、Complete、Data、Errors。
- 软件、自启动、安全组的 Scope 包含当前用户 SID 与提权状态；换用户或权限上下文后不把不同可见范围当成相同来源。报告中的用户/设备标识及事件内容仅留本地，分享前脱敏。
- `Data[].Key`：来源内稳定标识。卸载登记用 hive/view/subkey，驱动用设备 ID。不要按显示名或版本号作为身份。
- `null` 是未知，不改写为 0、false 或“健康”。JSON 包含完整数据；中文 Markdown 每组最多预览 80 项，原始事件 XML 留在 JSON。

差异 `Schema=windows-maintenance.comparison/v1`：

- 必须是支持的 schema 和同一个非空 MachineKey。系统重装改变 MachineGuid 后需重新建基线；克隆系统相同 GUID 也不能证明是同一实物机器，操作者仍需核对来源。
- 只有两次都有唯一分组、相同 Scope、完整 Succeeded/Empty 才逐项比较。Failed/Partial/TimedOut、漏选分组和重复 Key 均为 Incomparable，不补空数组伪装完整。
- 忽略记录顺序和对象属性顺序，保留 null 与 0 的区别；重复身份不取最后一项冒充确定结果。
- Added/Removed/Changed 表示观测差异。卸载登记变化、卷空闲变化、驱动版本变化仍需领域验证，不能直接写“升级成功”“已卸载”或“清理释放”。

## 继续执行与验证

继续任务时先读取最近的 JSON/中文维护记录，按分组重采失败、超时或确有变化的部分，使用新 OutputBase 保存。比较前确认来源相同；未重采的组保持未比较。工具不自动重放安装、恢复配置或删除命令，也不把旧快照当作最新删除许可。

自动报告是证据底稿，不代替变更记录。实际更新和配置备份/恢复仍按 [更新与修复](update-repair.md) 执行，并填写每项的原因、影响、回退、实际版本与功能验证。

运行 `scripts/Test-Maintenance.ps1 -WorkDirectory <现有测试目录>` 可验证比较、路径边界、超时、分类及报告保存行为。测试只创建独立夹具、连接点和报告，不执行真实更新/清理；兼容性或测试通过不等于电脑故障已修复。

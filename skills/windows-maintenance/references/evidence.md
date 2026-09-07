# 证据与采集

## 状态契约

每个记录保留 `Name`、`Started`、`Finished`、查询范围、数据、错误与原始日志位置。
把以下状态分开：

| 层次 | 判断依据 |
|---|---|
| 查询状态 | Succeeded / Empty / Partial / Failed / TimedOut；空值保持 null |
| 执行结果 | 原生进程和实际安装子进程退出码，已知重启返回码另记 |
| 对象状态 | DISM/SFC 结论、版本、绑定、服务状态等领域证据 |
| 稳定性 | 观察起止、实际负载、是否复发、相关新增事件 |

`Success=true` 只是包装器字段，不能覆盖错误文本、空数组或损坏结论。
`Get-StorageReliabilityCounter` 空结果表示未取得数据；null 不代表错误为零。
温度最高值不是当前温度；Healthy 标签不能替代全量 SMART 或负载测试。

## PowerShell 与原生程序

PowerShell 查询使用 `-ErrorAction Stop`，异常写入记录；不要用 SilentlyContinue 把权限错误变成空结果。
允许部分成功的批量查询按对象分别捕获，再生成 Partial；保留成功项和失败项。
Get-WinEvent 的 `NoMatchingEventsFound` 可记“本窗口无匹配”，其他异常必须记查询失败。
PowerShell 5.1 不会因为原生 EXE 返回非零自动进入 catch；退出后立即保存 `$LASTEXITCODE`。
通过 Start-Process 启动时用 PassThru 取得进程，再等待并刷新退出码；后台辅助进程使用 Hidden。
对于启动安装子进程后提前退出的安装器，还要核验子进程完成和实际应用状态。

长任务把原始输出、状态文件与进度写到工作目录；工具输出被截断不应造成证据丢失。
状态至少区分 started/running/completed/failed，写完成时间，不以“进程消失”替代成功。
先做脚本 AST 解析，再执行管理员脚本；权限失败记录失败，不伪装成功或绕过 UAC。

### SFC 中文输出

保留首次输出的原始字节与本轮 CBS 时间范围。对已产生乱码的日志，先检查原始文件及已有解码记录。
先识别 BOM/UTF-16LE 或具体代码页，再选择解码；将解码方法、可信度和来源一并记录。
历史日志可能是 UTF-16LE 字节被 CP936 解码后再次保存，简单“改成 UTF-8”不能恢复。
如果不可无损恢复，以对应时段 CBS 或新的只读验证补证，不猜结论，更不为解决乱码重复修复。
有可追溯的恢复结论时说明其来源；内容尚不可靠时保持 Unknown。
DISM 可用 `/English` 减少本地化解析歧义。DISM/SFC 退出码 0 仍需阅读实际健康结论。

## 事件数量与关联

保留窗口起止、时区、日志名、Provider、Id、RecordId、设备实例 ID 和必要原始 XML。
达到 `MaxEvents` 的结果是下限。需要完整总数时缩窄到有关 Provider/事件，在整个指定窗口分页或无上限查询。
若日志已滚动丢失，也要说明可用历史起点；不能声称覆盖丢失期间。
重复 NVIDIA 错误条数不等于独立崩溃次数；Kernel-Power 41 不等于电源故障。
设备当前 OK 不否定历史断连。变更后的日志按维护开始时间筛选，不靠清空日志来判定改善。

## 模块用法

```powershell
# $skillDir 是当前技能目录，$candidateRoot 是本轮明确选定的现存本地目录。
Import-Module (Join-Path $skillDir 'scripts\Maintenance.ReadOnly.psm1') -Force
$record = Invoke-MaintenanceRead -Name 'volumes' -Action {
    Get-Volume -ErrorAction Stop | Select-Object DriveLetter,Size,SizeRemaining
}
$record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $recordPath -Encoding UTF8
$size = Get-MaintenanceTreeSize -Path $candidateRoot -MaxSeconds 30
$validated = Resolve-MaintenanceChildPath -Root $candidateRoot -Path $selectedFile
```

模块不会安装、删除、修改注册表或自动选择清理目录。导入不会采集系统。
`Invoke-MaintenanceRead` 接受可信只读 PowerShell 查询；不要传原生 EXE，也不要在 Action 内压制错误。
此函数不把返回对象中的业务错误转换为 Failed；仍需读该接口自己的 ResultCode 等字段。
单独使用底层函数时由调用者另加 Scope、RawLog 和领域结论；整机入口已补充 Scope 和完整性字段，详见 [采集与对比工具](automation.md)。原生进程字节采集仍需按实际工具处理。
目录 Complete 仅指已读完“普通条目、排除重解析点”的范围；超时或访问错误会置 false。
时间限制是枚举过程中检查的协作式限制，单次文件系统 I/O 阻塞可能超过时限；它不是强制进程超时。
逻辑长度可能重复计算硬链接，不能视为物理占用或保证可释放空间。
路径工具仅支持现存、完整限定的本地盘符路径；拒绝根目录本身、越界目标及路径上的重解析点。
工具不会锁定文件或证明目标未被使用。真正移动/删除前再次核验最终绝对路径与最新状态。
跨盘移动不是普通改名；同盘隔离可回退但不释放空间，二者不可混报。

### 清单时间戳的跨版本比较

新版 PowerShell 的 ConvertFrom-Json 可能把 ISO 时间自动转换为 DateTime；不要将清单中的值与实时 ToString('o') 做字符串相等比较。
对带时区的清单时间和实际 LastWriteTimeUtc，都转换成 UTC 的 Ticks 后比较；DateTimeOffset 可使用 UtcDateTime.Ticks。
没有时区信息时先确认清单语义，不把本地时间擅自当 UTC。支持 DateKind 的版本也可保留字符串后显式解析。
文件已变化、精度丢失或时间无法可靠比较时，重新核对该条候选并跳过未确认项，不能据字符串格式差异批量误判。

## 中文维护记录

报告开头写本轮授权范围、仍排除事项、开始/结束时间与总体结果。
主要内容使用以下表格，保留与本轮变更有关的证据链接：

| 对象 | 变更前 | 实际操作与原因 | 结果/错误 | 影响 | 回退方法 | 验证与限制 |
|---|---|---|---|---|---|---|

记录每个已执行项及未完成原因。可恢复隔离记录原路径/新路径；永久删除明确说明恢复依赖什么。
空间报告分别列候选逻辑量、成功处理量和同一卷空闲变化；说明后台写入会影响差值。
保留转储在本机；共享报告或证据包前去除无关账户、设备序列号与用户内容。

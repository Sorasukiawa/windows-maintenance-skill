# Windows 维护技能开发约定

先读 `CONTRIBUTING.md` 与 `SECURITY.md`。技能入口是 `skills/windows-maintenance/SKILL.md`；主验证入口为 `tests/Invoke-CI.ps1`。

- PowerShell 脚本沿用 UTF-8 BOM，以兼容 Windows PowerShell 5.1 中文。Markdown 使用 UTF-8。
- 脚本改动按贡献指南验证 Windows PowerShell 5.1 与 PowerShell 7；macOS 上的静态检查不冒称 Windows 原生验证。
- 隔离夹具不更新或清理运行机器。失败查询不等于空结果，目录分类不授予删除许可；维护动作、版本和功能分别留证。
- 不提交真实软件清单、事件 XML、转储、个人路径、设备标识或配置备份。保留已有多语言介绍和字段契约。

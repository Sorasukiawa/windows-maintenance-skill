# Windows Maintenance Skill

[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md)

[MIT License](LICENSE) · [CI](https://github.com/Sorasukiawa/windows-maintenance-skill/actions)

A Windows maintenance skill for Codex, with standalone PowerShell tools for read-only inventory, directory classification, JSON/Chinese Markdown reports, and snapshot comparison.

This is an initial public preview. It separates successful collection from system health, update verification, and demonstrated stability. It does not automatically update every application, delete caches, or flash firmware.

## Capabilities

- Seven local collection groups: System, Storage, Drivers, Software, Startup, Stability, and Security.
- Bounded directory inventory with reparse-point exclusion and conservative classification.
- Explicit failed, partial, empty, and timed-out query states; unknown values remain unknown.
- Same-machine, same-source comparison with user/elevation context for user-dependent collections.
- Maintenance guidance for precise updates, configuration migration, driver binding, repair verification, evidence preservation, and rollback.

Motherboard BIOS is not excluded by default. Define the scope when invoking the skill; actual device flashing still requires applicable authorization and verified vendor instructions.

## Use with Codex

Ask Codex's `$skill-installer` to install `skills/windows-maintenance` from this repository. For manual installation, copy that folder into a skill location supported by your host, comparing and backing up any existing customization first. Current Codex documentation lists `~/.agents/skills` as the user location. See the [official skill documentation](https://learn.chatgpt.com/docs/build-skills).

```text
$skill-installer Install skills/windows-maintenance from https://github.com/Sorasukiawa/windows-maintenance-skill
```

```text
$windows-maintenance Audit this Windows PC and report applicable update candidates.
$windows-maintenance Update and clean this PC; exclude motherboard BIOS this time.
```

The four introductions describe the same functionality. The skill instructions remain primarily Simplified Chinese, and generated Markdown reports are Chinese. The scripts run independently of Codex on Windows PowerShell 5.1 and PowerShell 7. See the detailed [tool contract](skills/windows-maintenance/references/automation.md).

## Standalone quick start

Run from the repository root:

```powershell
$runDir = Join-Path $env:TEMP ('maintenance-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runDir -ErrorAction Stop | Out-Null
& .\skills\windows-maintenance\scripts\Collect-MaintenanceSnapshot.ps1 -OutputBase (Join-Path $runDir 'before')
```

This writes new JSON and Markdown reports. It does not install updates or clean the computer. See [the longer examples](README.zh-CN.md) for directory inventory and before/after comparison.

## Run tests

From the repository root:

```powershell
& .\tests\Invoke-CI.ps1 -WorkDirectory (Join-Path $env:TEMP ('maintenance-ci-' + [guid]::NewGuid().ToString('N')))
```

The Windows CI matrix runs syntax/reference validation, 31 inventory/comparison/reporting assertions, and 15 original helper assertions in both PowerShell versions. Fixtures are isolated; CI does not update, repair, or clean the runner. Check the repository's Actions page for actual hosted-run results.

## Boundaries

Online update availability, Store/portable applications, active executable versions, full SMART/temperature readings, DISM/SFC conclusions, firmware applicability, configuration adoption, and load stability need separate evidence. A health label is not a full hardware test. An installer exit code is not proof that the intended version is active.

Directory sizes are logical, can overlap their parents, and are not guaranteed reclaimable space. Classification never authorizes deletion. Reports refuse to overwrite existing files.

Reports can contain local paths, user/device identifiers and event contents. Keep them local and use sanitized minimal reproductions in issues; do not publish full reports or dumps. See [SECURITY.md](SECURITY.md) and [CONTRIBUTING.md](CONTRIBUTING.md).

Developed with Codex assistance and tested with scripts and independent application scenarios. Local validation on Windows 11 does not establish compatibility with every machine or vendor updater. No support SLA is promised. Licensed under [MIT](LICENSE).

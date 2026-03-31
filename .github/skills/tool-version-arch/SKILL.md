---
name: tool-version-arch
description: 'Understand the Windows tool version management architecture for ssd-testkit. Use when: adding a new tool version, uploading to Nexus, managing NAS storage, checking Nexus repo config, understanding tools-registry.yaml layout, choco pack/install workflow, NAS directory structure, version naming conventions.'
argument-hint: 'tool name or operation (e.g. "smicli upgrade", "upload nupkg", "NAS paths")'
---

# Tool Version Architecture

## What This Skill Covers

- 工具版本命名與 `tools-registry.yaml` 結構
- NAS 路徑、帳號、目錄設計
- Nexus 各 repository 用途與操作
- 新增工具版本的完整流程
- choco pack → upload → install 的端到端流程

---

## Architecture Overview

```
[ssd-testkit repo]          [Nexus choco-hosted]      [NAS]
bin\installers\<tool>\      →  choco pack             ssd-testkit-source\
  <version>\                →  upload .nupkg          ├── installers\  (原始資料夾)
    *.exe / *.sys           →  choco install           ├── zip\         (壓縮備份)
                                                        └── nupkg\       (套件備份)
bin\chocolatey\packages\
  <id>\
    <id>.nuspec             ←── 版本決策唯一來源
    tools\                        ↓
      chocolateyInstall.ps1  packages.config (git)
    <version>\
      <id>.<version>.nupkg  ←── 本地快取 / Nexus 下載
```

**三個地方各司其職：**

| 地方 | 角色 | 版本控管 |
|------|------|---------|
| NAS `installers/` | 原始 binary 備份 | 資料夾名稱即版本，只增不刪 |
| Nexus `choco-hosted` | 可下載的套件倉庫 | 多版本並存，Nexus 管理 |
| `packages.config` (git) | **決定要用哪個版本** | git 控管，唯一決策點 |

---

## References

- [NAS 儲存設計](./references/nas-storage.md) — IP、帳號、密碼、目錄結構、掛載設定
- [Nexus Repository 設定](./references/nexus-repos.md) — repos 清單、上傳/下載/安裝指令
- [版本命名與 tools-registry.yaml](./references/version-naming.md) — 命名規則、欄位說明、各工具當前版本

---

## Quick Procedures

### 新增工具版本（完整）

1. 將 binary 放入 `bin\installers\<Tool>\<version>\`
2. 壓縮成 `.zip` → 備份到 NAS `ssd-testkit-source\windows\zip\`
3. 備份資料夾到 NAS `ssd-testkit-source\windows\installers\`
4. 更新 `bin\chocolatey\packages\<id>\<id>.nuspec` 版本號
5. 更新 `tools\chocolateyInstall.ps1` 的 `$toolVersion`
6. `choco pack` → 產生 `.nupkg`
7. 執行 `tool-manager\upload_tools_to_nexus.ps1` 上傳到 Nexus
8. 備份 `.nupkg` 到 NAS `ssd-testkit-source\windows\nupkg\`
9. 更新 `lib\testtool\tools-registry.yaml` 的 `version` 欄位
10. 更新 `packages.config` 版本號 → git commit

### 安裝工具（test case 執行前）

```powershell
cd C:\ssd-testkit
.\tool-manager\prepare_testcase.bat
# 或指定 testcase：
.\tool-manager\prepare_testcase.ps1 stc1685_burnin
```

### 上傳到 Nexus

```powershell
cd C:\ssd-testkit
.\tool-manager\upload_tools_to_nexus.bat
```

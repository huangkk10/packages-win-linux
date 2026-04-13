# 版本命名規則與 tools-registry.yaml

## 版本命名規則

本專案有**兩套版本號**並存：

| 層次 | 格式 | 範例 | 說明 |
|------|------|------|------|
| **Installer 資料夾版本** | `v<YYYYMMDD><Suffix>` | `v20260213C` | 供應商提供的 build tag |
| **Chocolatey 套件版本** | `<YYYY>.<M>.<D>[.<Build>]` | `2026.2.13` | NuGet 規範版本，對應 installer 日期 |

### 對應關係範例

| 工具 | Installer 版本 | Chocolatey 版本 |
|------|--------------|----------------|
| SmiCli | `v20260213C` | `2026.2.13` |
| SmiWinTools | `v20260213C` | `2026.2.13.1`（同日期但不同工具用 `.1` 區分） |
| BurnIn | `10.2.1004` | `10.2.1004`（供應商版本直接使用） |
| CrystalDiskInfo | `8.17.13` | `8.17.13` |
| PHM | `V4.22.0_B25.02.06.02_H` | `4.22.0` |
| WindowsADK | `26100.0.0`（Windows Build） | `26100.0.0` |

### ZIP 備份命名

```
<ToolName>-<InstallerVersion>.zip
# 範例：
SmiCli-v20260213C.zip
BurnIn-10.2.1004.zip
WindowsADK-26100.0.0.zip
```

## tools-registry.yaml 欄位說明

位置：`lib\testtool\tools-registry.yaml`（Windows）/ `tools-registry.yaml`（Linux repo）

```yaml
tools:
  <id>:                        # Chocolatey package id（小寫，與 .nuspec 一致）
    version: <choco-version>   # Chocolatey 版本號（必填，供 prepare_testcase / upload 使用）
    install_dir: <path>        # 安裝後的目錄（偵測是否已安裝的依據）
    binaries: [<exe>]          # 偵測已安裝的目標執行檔（在 install_dir 底下）
    env_var: <VAR_NAME>        # 安裝後設定的環境變數（選填）
    bin_dir: <name>            # 舊設計保留欄位（目前不使用）
    source_dir: <path>         # 舊設計保留欄位（目前不使用）
    nexus_path: <path>         # 舊設計保留欄位（目前不使用）
```

> 若 `binaries` 為空，prepare_testcase 改以 `install_dir` 是否存在作為判斷依據。

## 當前工具清單

```yaml
tools:
  smicli:
    version: 2026.2.13
    install_dir: C:\\tools\\SmiCli
    binaries: [SmiCli2.exe]
    env_var: SMICLI_PATH

  smiwintools:
    version: 2026.2.13.1
    install_dir: C:\\tools\\SmiWinTools
    env_var: SMIWINTOOLS_PATH

  burnin:
    version: 10.2.1004
    install_dir: C:\\Program Files\\BurnInTest
    env_var: BURNIN_PATH

  cdi:
    version: 8.17.13
    install_dir: C:\\tools\\CrystalDiskInfo
    binaries: [DiskInfo64.exe, DiskInfo32.exe]
    env_var: CDI_PATH

  phm:
    version: 4.22.0
    install_dir: C:\\Program Files\\PowerhouseMountain
    env_var: PHM_PATH

  windows-adk:
    version: 26100.0.0
    install_dir: C:\\Program Files (x86)\\Windows Kits\\10\\Windows Performance Toolkit
    binaries: [wpr.exe, wpa.exe, xbootmgr.exe]

  git:
    version: 2.44.0
    install_dir: C:\\tools\\git

  net-7-sdk:
    version: 7.0.410
    install_dir: C:\\tools\\net_7_sdk

  playwright-browsers:
    version: 1.58.0
    install_dir: C:\\tools\\playwright-browsers
```

## tools.yaml（per test case）

位置：`tests\integration\test_case\<name>\Config\tools.yaml`

```yaml
tools:
  - id: smicli
  - id: windows-adk
  - id: cdi
```

只列 id，其餘欄位（version、install_dir、binaries）由 `tools-registry.yaml` 提供。

## chocolateyInstall.ps1 設計

本專案的 .nupkg 是**搬運包裝**，不內嵌 binary：

```powershell
# bin\chocolatey\packages\smicli\tools\chocolateyInstall.ps1
$toolVersion = "v20260213C"          # ← 升版時只改這行
$toolName    = "SmiCli"
$srcDir      = Join-Path $env:SSD_TESTKIT_ROOT "bin\installers\$toolName\$toolVersion"
$dstDir      = "C:\tools\SmiCli"

Copy-Item "$srcDir\*" $dstDir -Recurse -Force
[Environment]::SetEnvironmentVariable("SMICLI_PATH", $dstDir, "Machine")
```

安裝時從 `%SSD_TESTKIT_ROOT%\bin\installers\` 複製，所以每台開發機都需要 `bin\installers\` 的實際檔案。

## 升版 Checklist

升版 smicli 從 `2026.2.13` → `2026.4.1` 為例：

| # | 動作 | 路徑 |
|---|------|------|
| 1 | 放入 installer 執行檔 | `bin\installers\SmiCli\v20260401A\` |
| 2 | 備份 installer 到 NAS | `ssd-testkit-source\windows\installers\SmiCli\v20260401A\` |
| 3 | 壓縮備份到 NAS | `ssd-testkit-source\windows\zip\SmiCli-v20260401A.zip` |
| 4 | 更新 nuspec version | `bin\chocolatey\packages\smicli\smicli.nuspec` |
| 5 | 更新 `$toolVersion` | `bin\chocolatey\packages\smicli\tools\chocolateyInstall.ps1` |
| 6 | `choco pack` | 產生 `smicli.2026.4.1.nupkg` |
| 7 | 上傳到 Nexus | `upload_tools_to_nexus.ps1` |
| 8 | 備份 .nupkg 到 NAS | `ssd-testkit-source\windows\nupkg\smicli.2026.4.1.nupkg` |
| 9 | 更新 tools-registry.yaml | `version: 2026.4.1` |
| 10 | 更新 packages.config → git commit | `<package id="smicli" version="2026.4.1" />` |

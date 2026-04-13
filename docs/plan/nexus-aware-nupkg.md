# Nexus-Aware nupkg 升級

**目標**：修改所有工具的 `chocolateyInstall.ps1`，加入 Nexus fallback，讓沒有 ssd-testkit 的 PC 也能正常 `choco install`。

**決策**：方案 A — 在 ssd-testkit（develop branch）修改 + repack，packages-win-linux 負責上傳。

**狀態**：✅ 完成（2026-04-13）— 待最終乾淨 PC 驗證。

---

## 架構說明

### 修改後的行為

```
chocolateyInstall.ps1 執行時：

if (SSD_TESTKIT_ROOT 有設定) {
    → 原有行為：從本地 bin/installers/ 找 binary（開發環境）
} else {
    → 新行為：從 Nexus raw-windows-tools 下載 zip，解壓後安裝（任意 PC）
}
```

### Repos 分工

| Repo | 職責 |
|------|------|
| `ssd-testkit` | 唯一 nupkg 來源，負責 choco pack |
| `packages-win-linux` | 上傳 binary zip 到 Nexus、上傳 nupkg 到 Nexus |

---

## 前置條件

### Nexus 新增 Repo
需建立 `raw-windows-tools`（raw hosted）用於存放 binary zip。

```bash
# 在 Linux server 上執行
curl -sk -u "admin:1.a" -X POST \
  "https://127.0.0.1/service/rest/v1/repositories/raw/hosted" \
  -H "Content-Type: application/json" \
  -d '{"name":"raw-windows-tools","online":true,"storage":{"blobStoreName":"default","strictContentTypeValidation":false,"writePolicy":"ALLOW"}}'
```

### 工作環境
- ssd-testkit clone 在 Windows PC（有 `choco` 可用）
- Windows PC 可連到 Nexus（或事後由 Linux 上傳）

---

## Nexus raw-windows-tools 現有內容

```
/BurnIn/10.2.1004/BurnIn-10.2.1004.zip
/CrystalDiskInfo/8.17.13/CrystalDiskInfo-8.17.13.zip
/PHM/4.22.0/PHM-V4.22.0.zip
/PlaywrightBrowsers/1.58.0/playwright-browsers-1.58.0.zip
/SmiCli/v20260213C/SmiCli-v20260213C.zip
/SmiWinTools/v20260213B/SmiWinTools-v20260213B.zip
/SmiWinTools/v20260213C/SmiWinTools-v20260213C.zip
/WindowsADK/26100/WindowsADK-26100.0.0.zip
/git/2.44.0/git-2.44.0.zip
/net_7_sdk/7.0.410/net-7-sdk-7.0.410.zip
```

## ssd-testkit 修改的檔案（develop branch）

來源：`/home/owner/Codes/ssd-testkit`  
修改模式：`if ($toolkitRoot) { 本地 } else { iwr 從 Nexus 下載 }`

| 工具 | 路徑 | nupkg 版本 |
|------|------|-----------|
| burnin | `bin/chocolatey/packages/burnin/10.2.1004/tools/chocolateyInstall.ps1` | 10.2.1004 |
| cdi | `bin/chocolatey/packages/cdi/8.17.13/tools/chocolateyInstall.ps1` | 8.17.13 |
| git | `bin/chocolatey/packages/git/2.44.0/tools/chocolateyInstall.ps1` | 2.44.0 |
| net-7-sdk | `bin/chocolatey/packages/net-7-sdk/7.0.410/tools/chocolateyInstall.ps1` | 7.0.410 |
| phm | `bin/chocolatey/packages/phm/4.22.0/tools/chocolateyInstall.ps1` | 4.22.0 |
| playwright-browsers | `bin/chocolatey/packages/playwright-browsers/1.58.0/tools/chocolateyInstall.ps1` | 1.58.0 |
| smiwintools | `bin/chocolatey/packages/smiwintools/2026.2.13/tools/chocolateyInstall.ps1` | 2026.2.13 |
| smiwintools | `bin/chocolatey/packages/smiwintools/2026.2.13.1/tools/chocolateyInstall.ps1` | 2026.2.13.1 |
| windows-adk | `bin/chocolatey/packages/windows-adk/26100.0.0/tools/chocolateyInstall.ps1` | 26100.0.0 |

## 狀態追蹤

- [x] 建立 Nexus `raw-windows-tools` repo
- [x] 建立 `scripts/upload/upload_tools_zip.sh`
- [x] 修改 9 個 chocolateyInstall.ps1（ssd-testkit develop）
- [x] zip repack 9 個 nupkg（Linux，zip 工具）
- [x] 備份 9 個 nupkg 到 NAS（`windows/nupkg/`）
- [x] 上傳 9 個 nupkg 到 Nexus `choco-hosted`
- [x] 壓縮 3 個缺少的 binary zip（NAS installers → NAS zip）
- [x] 上傳 10 個 binary zip 到 Nexus `raw-windows-tools`
- [x] 清除舊 `/windows-tools/` 前綴重複項目
- [ ] 驗證（乾淨 PC，無 ssd-testkit）

## 最終驗證步驟

在一台**沒有 ssd-testkit 的 Windows PC** 執行：

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
iwr http://10.252.170.171/b -UseBasicParsing | iex

choco install cdi --yes
choco install smiwintools --yes
choco install windows-adk --yes
```

預期：不報 `SSD_TESTKIT_ROOT` 錯誤，binary 從 Nexus 下載安裝。

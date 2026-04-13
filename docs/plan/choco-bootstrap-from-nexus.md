# Chocolatey 從內網安裝計畫

**目標：** 全新 Windows PC，不需要外網，一條指令完成 Chocolatey 安裝  
**方案：** 將 `chocolatey.nupkg` 與 `bootstrap.ps1` 上傳到 Nexus `raw-windows-bootstrap`  
**狀態：** ✅ 完成（2026-04-13）

---

## 架構

```
全新 Windows **PC**
     │
     │  一條指令
     ▼
iwr https://nexus.internal/b | iex
     │
     ▼
Nexus raw-windows-bootstrap
  ├── b.ps1              ← bootstrap 入口（極短 URL）
  └── chocolatey.nupkg   ← Chocolatey 本體
     │
     ▼
1. 下載 chocolatey.nupkg
2. 離線安裝 Chocolatey
3. 登錄 Nexus 為 choco 來源
4. 完成 → 可執行 choco install <tool>
```

---

## Step 1：Nexus 建立 `raw-windows-bootstrap` repository

在 Nexus UI 或用 API 建立：

| 欄位 | 值 |
|------|---|
| Name | `raw-windows-bootstrap` |
| Format | Raw (Hosted) |
| Blob Store | `default` |
| Deployment policy | Allow redeploy |

> 也可沿用現有的 `raw-linux-tools`，但建議分開以便權限管理。

---

## Step 2：取得 `chocolatey.nupkg`

從現有 Windows 機器（10.8.113.3）複製，或從 Chocolatey 官網下載一次後存入 NAS：

```bash
# 從 Windows 機器 scp 取回
scp administrator@10.8.113.3:"C:/ssd-testkit/bin/chocolatey/installer/chocolatey.nupkg" \
    /tmp/chocolatey.nupkg
```

備份到 NAS：
```bash
cp /tmp/chocolatey.nupkg \
   /mnt/nas-mdt/Team/PQ1-3/tool/ssd-testkit-source/windows/nupkg/
```

---

## Step 3：撰寫 `b.ps1`（bootstrap 入口）

存放位置：`packages/windows/bootstrap/b.ps1`（此 repo 版控）

```powershell
# b.ps1 — Chocolatey 內網 Bootstrap
# 用法（以 IP 直接呼叫，不需要事先設定 hosts）：
#   Set-ExecutionPolicy Bypass -Scope Process -Force
#   [Net.ServicePointManager]::ServerCertificateValidationCallback={$true}
#   iwr https://10.252.170.171/b -UseBasicParsing | iex

param(
    [string]$NexusIp  = "10.252.170.171",
    [string]$NexusHost = "nexus.internal",
    [string]$Repo     = "raw-windows-bootstrap"
)

$ErrorActionPreference = 'Stop'
# 略過 self-signed SSL 驗證（bootstrap 階段尚未匯入 CA）
[Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
if ($PSVersionTable.PSVersion.Major -ge 6) {
    $PSDefaultParameterValues['Invoke-WebRequest:SkipCertificateCheck'] = $true
    $PSDefaultParameterValues['Invoke-RestMethod:SkipCertificateCheck']  = $true
}

# [0/4] 自動寫入 hosts（若尚未存在）
$hostsFile = "$env:SystemRoot\System32\drivers\etc\hosts"
$hostsEntry = "$NexusIp`t$NexusHost"
if (-not (Select-String -Path $hostsFile -Pattern ([regex]::Escape($NexusHost)) -Quiet)) {
    Write-Host "[0/4] 寫入 hosts：$hostsEntry"
    Add-Content $hostsFile "`n$hostsEntry"
} else {
    Write-Host "[0/4] hosts 已有 $NexusHost，略過"
}

$NexusUrl = "https://$NexusIp"
$base     = "$NexusUrl/repository/$Repo"
$tmp      = "$env:TEMP\choco-bootstrap"
$nupkg    = "$tmp\chocolatey.nupkg"

New-Item -ItemType Directory -Force -Path $tmp | Out-Null

Write-Host "[1/4] 下載 chocolatey.nupkg ..."
Invoke-WebRequest "$base/chocolatey.nupkg" -OutFile $nupkg -UseBasicParsing

Write-Host "[2/4] 安裝 Chocolatey ..."
$env:ChocolateyInstall = 'C:\ProgramData\chocolatey'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$extractDir = "$tmp\choco-extracted"
[System.IO.Compression.ZipFile]::ExtractToDirectory($nupkg, $extractDir)
& "$extractDir\tools\chocolateyInstall.ps1"

# 重新載入 PATH
$env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
            [System.Environment]::GetEnvironmentVariable('Path','User')

Write-Host "[3/4] 登錄 Nexus 為 choco 來源 ..."
choco source add `
  --name="nexus" `
  --source="https://$NexusHost/repository/choco-hosted" `
  --priority=1 -y
choco source disable --name="chocolatey" 2>$null

Write-Host "[4/4] 完成！"
Write-Host ""
Write-Host "安裝工具範例："
Write-Host "  choco install windows-adk --version 26100.0.0 -y"
Write-Host "  choco install burnin       --version 10.2.1004  -y"
```

---

## Step 4：上傳到 Nexus

```bash
# 在 Linux 伺服器執行
NEXUS="https://127.0.0.1"
REPO="raw-windows-bootstrap"
AUTH="admin:1.a"

# 上傳 bootstrap 腳本
curl -sk -u "$AUTH" -X PUT \
  "$NEXUS/repository/$REPO/b.ps1" \
  --upload-file packages/windows/bootstrap/b.ps1

# 上傳 chocolatey 本體
curl -sk -u "$AUTH" -X PUT \
  "$NEXUS/repository/$REPO/chocolatey.nupkg" \
  --upload-file /tmp/chocolatey.nupkg

echo "驗證："
curl -sk -u "$AUTH" "$NEXUS/repository/$REPO/" | grep -o 'href="[^"]*"'
```

---

## Step 5：Nginx 加短路徑（讓指令更短）

編輯 `nexus/nginx/nexus.conf`，在 server 區塊加入：

```nginx
# Chocolatey bootstrap 短路徑：https://nexus.internal/b
location = /b {
    return 302 /repository/raw-windows-bootstrap/b.ps1;
}
```

重載 nginx：
```bash
docker exec nexus-nginx nginx -s reload
```

---

## Step 6：新 PC 安裝（最終操作）

以 **系統管理員** 開啟 PowerShell，貼上**一行**執行：

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; iwr http://10.252.170.171/b -UseBasicParsing | iex
```

> 腳本會自動：寫入 hosts → 下載 chocolatey.nupkg → 安裝 Chocolatey → 登錄 Nexus 來源

完成後即可安裝任何工具：

```powershell
choco install windows-adk --version 26100.0.0 -y
choco install burnin --version 10.2.1004 -y
```

---

## 工作項目

| # | 工作 | 負責 | 狀態 |
|---|------|------|------|
| 1 | 建立 Nexus `raw-windows-bootstrap` repository | Infra | ✅ 完成 |
| 2 | 從 Windows 機器取得 `chocolatey.nupkg` | Dev | ✅ 完成（從外網下載，備份至 NAS） |
| 3 | 建立 `packages/windows/bootstrap/b.ps1` | Dev | ✅ 完成 |
| 4 | 上傳 `b.ps1` + `chocolatey.nupkg` 到 Nexus | Dev | ✅ 完成 |
| 5 | Nginx 加 `/b` 短路徑並重載 | Infra | ✅ 完成 |
| 6 | 在測試 PC 驗證兩步安裝流程 | Dev | ⬜ 待驗證 |
| 7 | 備份 `chocolatey.nupkg` 到 NAS `ssd-testkit-source/windows/nupkg/` | Dev | ✅ 完成 |

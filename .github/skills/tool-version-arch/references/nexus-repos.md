# Nexus Repository 設定

## 連線資訊

| 項目 | 值 |
|------|---|
| Nexus IP（對外） | `10.252.170.171` |
| Nexus hostname | `nexus.internal` |
| HTTPS Port | `443`（nginx 反向代理） |
| Admin 帳號 | `admin` / `1.a` |
| Uploader 帳號 | `uploader` / `Uploader@2026` |
| Docker 位置 | Linux host，`nexus/docker/docker-compose.yml` |

> Windows 機器用 `https://nexus.internal`；Linux 本機用 `https://127.0.0.1`

## Repository 清單

| Repo 名稱 | 格式 | Blob Store | 用途 |
|-----------|------|------------|------|
| `choco-hosted` | NuGet | default（本機） | .nupkg 主倉庫 |
| `choco-hosted-nas` | NuGet | nas-blob（NAS） | .nupkg NAS 版（大容量） |
| `raw-windows-tools` | Raw | default | 舊版 zip 上傳（已棄用） |
| `raw-linux-tools` | Raw | default | Linux binary（待用） |
| `raw-linux-tools-nas` | Raw | nas-blob | Linux binary NAS 版（待用） |

**目前使用：`choco-hosted`（Windows 工具主要倉庫）**

## Blob Store

| 名稱 | 類型 | 路徑 | 對應 NAS |
|------|------|------|---------|
| `default` | Local | `/nexus-data/blobs/default` | 不在 NAS |
| `nas-blob` | File | `/nexus-nas-blob` | `/mnt/nas-mdt/Team/PQ1-3/tool/ssd-testkit-nexus/` |

## 上傳 .nupkg 到 Nexus

### 方式 A：透過腳本（推薦）

```powershell
# 從 Windows 執行
cd C:\ssd-testkit
.\tool-manager\upload_tools_to_nexus.bat
```

腳本邏輯（`tool-manager\upload_tools_to_nexus.ps1`）：
1. 讀 `lib\testtool\tools-registry.yaml` 取 id + version
2. 找 `bin\chocolatey\packages\<id>\<version>\<id>.<version>.nupkg`
3. 若不存在，從 `<id>.nuspec` 執行 `choco pack`
4. POST 到 `choco-hosted` 的 REST API

### 方式 B：curl 手動上傳（從 Linux）

```bash
curl -sk --max-time 60 -u "admin:1.a" \
  -X POST "https://127.0.0.1/service/rest/v1/components?repository=choco-hosted" \
  -F "nuget.asset=@/path/to/smicli.2026.2.13.nupkg;type=application/octet-stream" \
  -w "\nHTTP:%{http_code}\n"
# 成功回傳 HTTP:204
```

## 下載 .nupkg 從 Nexus

### URL 格式

```
https://nexus.internal/repository/choco-hosted/<id>/<version>
```

範例：
```
https://nexus.internal/repository/choco-hosted/smicli/2026.2.13
```

### PowerShell 下載

```powershell
$headers = @{ Authorization = "Basic " + [Convert]::ToBase64String(
    [Text.Encoding]::ASCII.GetBytes("admin:1.a")) }

Invoke-WebRequest `
  -Uri "https://nexus.internal/repository/choco-hosted/smicli/2026.2.13" `
  -Headers $headers `
  -OutFile "C:\ssd-testkit\bin\chocolatey\packages\smicli\2026.2.13\smicli.2026.2.13.nupkg"
```

## 安裝工具（choco install）

### 從本地快取（推薦，離線可用）

```powershell
choco install smicli `
  --source "C:\ssd-testkit\bin\chocolatey\packages\smicli\2026.2.13" `
  -y --no-progress
```

### 直接從 Nexus

```powershell
choco install smicli `
  --source "https://nexus.internal/repository/choco-hosted" `
  --version 2026.2.13 `
  -y --no-progress
```

### 透過 prepare_testcase（test case 執行前）

```powershell
cd C:\ssd-testkit
.\tool-manager\prepare_testcase.ps1 stc2557_adk_s3s4s5
# 自動下載 .nupkg → 檢查 binary → choco install
```

## 查詢已上傳套件

```bash
# 列出 choco-hosted 所有套件
curl -sk -u "admin:1.a" \
  "https://127.0.0.1/service/rest/v1/components?repository=choco-hosted" | \
  python3 -c "
import sys, json
d = json.load(sys.stdin)
for i in sorted(d['items'], key=lambda x: x['name']):
    print(f\"{i['name']:20s} {i['version']}\")
"
```

## choco pack（打包 .nupkg）

```powershell
cd C:\ssd-testkit\bin\chocolatey\packages\smicli\2026.2.13
choco pack smicli.nuspec
# 產生 smicli.2026.2.13.nupkg
```

## 驗證 Nexus 連線

```bash
# 列出所有 repos
curl -sk -u "admin:1.a" "https://127.0.0.1/service/rest/v1/repositories" | \
  python3 -c "import sys,json; [print(r['name'], r['format']) for r in json.load(sys.stdin)]"

# 確認 blob store
curl -sk -u "admin:1.a" "https://127.0.0.1/service/rest/v1/blobstores" | \
  python3 -c "import sys,json; [print(b['name'], b['type']) for b in json.load(sys.stdin)]"
```

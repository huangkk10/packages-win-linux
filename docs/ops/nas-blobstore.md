# NAS Blob Store 設定操作手冊

**對應計畫：** [PLAN.md § Phase 2.5](../PLAN.md)  
**目的：** 將 Nexus 大型檔案（.nupkg、Linux binary）的 blob 儲存移到 NAS，避免佔用 Nexus 主機本地磁碟  
**採用方案：** B — 建新 repository 並行，驗證 OK 後再切換（零停機）

---

## 環境資訊

| 項目 | 值 |
|------|---|
| NAS IP | 10.250.0.1 |
| SMB Share | `mdt` |
| NAS 使用者 | `mdt` |
| NAS 密碼 | `p@ssw0rd` |
| NAS 目標路徑 | `\\10.250.0.1\mdt\Team\PQ1-3\tool\ssd-testkit-nexus` |
| Linux 掛載點 | `/mnt/nas-mdt` |
| Nexus 容器內路徑 | `/nexus-nas-blob` |
| Nexus URL | `https://10.252.170.171` |
| Nexus Admin | `admin` / `1.a` |

---

## NAS 目錄結構與版本管理

### 目錄結構

```
\\10.250.0.1\mdt\Team\PQ1-3\tool\
├── ssd-testkit-nexus/              ← Nexus blob store（即時讀寫，不手動動）
├── ssd-testkit-backup/             ← nexus-data volume 每日快照
│   ├── nexus-data-20260330.tar.gz
│   └── nexus-data-20260331.tar.gz
└── ssd-testkit-source/             ← 原始檔靜態備份（人工管理）
    ├── windows/
    │   ├── installers/             ← 照搬 bin\installers，保留原始資料夾名稱
    │   │   ├── BurnIn/
    │   │   │   └── 10.2.1004/
    │   │   ├── PHM/
    │   │   │   └── V4.22.0_B25.02.06.02_H/
    │   │   ├── SmiCli/
    │   │   │   ├── v20251114A/     ← 舊版保留（rollback 用）
    │   │   │   └── v20260213C/     ← 當前版本
    │   │   ├── SmiWinTools/
    │   │   │   ├── v20260213B/
    │   │   │   └── v20260213C/
    │   │   ├── CrystalDiskInfo/8.17.13/
    │   │   ├── net_7_sdk/7.0.410/
    │   │   ├── playwright-browsers/1.58.0/
    │   │   └── WindowsADK/
    │   │       ├── 19041/
    │   │       └── 22000/
    │   └── nupkg/                  ← Chocolatey .nupkg 備份
    │       ├── burnin.10.2.1004.nupkg
    │       ├── smicli.2026.2.13.nupkg
    │       └── ...
    └── linux/
        └── (Phase 3 新增)
```

### 版本管理原則

NAS 是**靜態備份倉庫**，不是版本管理系統。三個地方各司其職：

| 地方 | 角色 | 版本控管方式 |
|------|------|------------|
| **NAS `installers/`** | 原始安裝檔備份 | 資料夾名稱即版本，只增不刪 |
| **Nexus `choco-hosted-nas`** | 可下載的套件倉庫 | 多版本並存，Nexus 管理 |
| **ssd-testkit `packages.config`** | **決定要用哪個版本** | git 控管，唯一決策點 |

### 新增工具版本完整流程

以下以 **SmiCli v20260401A → Chocolatey 版本 2026.4.1** 為例說明所有必要動作。

---

#### 背景：.nupkg 的運作方式

本專案的 .nupkg 是**搬運包裝**，不內嵌 binary：

```
安裝時：choco install smicli → 執行 chocolateyInstall.ps1
    → 從 %SSD_TESTKIT_ROOT%\bin\installers\SmiCli\v20260401A\ 複製檔案到 C:\tools\SmiCli\
    → 設定 SMICLI_PATH 環境變數
```

代表每台開發機的 ssd-testkit repo 下仍需要 `bin\installers\` 的實際檔案。

---

#### 完整步驟

**Step A：準備 installer 檔案**

```
在 ssd-testkit repo：
bin\installers\SmiCli\v20260401A\
    SmiCli2.exe
    SmiCli2.pdb
    WinIo64.sys
    WinIoEx.sys
```

**Step B：備份到 NAS**

在 Windows PC（10.8.113.3）執行，或透過 Linux 中繼：

```powershell
# 在 Windows 直接執行
net use Z: \\10.250.0.1\mdt /user:mdt "p@ssw0rd"
robocopy C:\ssd-testkit\bin\installers\SmiCli\v20260401A `
  Z:\Team\PQ1-3\tool\ssd-testkit-source\windows\installers\SmiCli\v20260401A `
  /E /Z
net use Z: /delete
```

**Step C：建立 Chocolatey 套件定義**

複製現有版本資料夾作為模板：

```
bin\chocolatey\packages\smicli\
└── 2026.4.1\                      ← 新建，複製自 2026.2.13\
    ├── smicli.nuspec
    └── tools\
        ├── chocolateyInstall.ps1
        └── chocolateyUninstall.ps1
```

修改 `smicli.nuspec`（更新 version、title、description）：

```xml
<version>2026.4.1</version>
<title>SmiCli2 (v20260401A)</title>
<description>... Tool version: v20260401A ...</description>
```

修改 `tools\chocolateyInstall.ps1`（只改 `$toolVersion`）：

```powershell
$toolVersion = "v20260401A"   # ← 改這行
```

**Step D：打包成 .nupkg**

在 Windows PC 上執行（需安裝 Chocolatey）：

```powershell
cd C:\ssd-testkit\bin\chocolatey\packages\smicli\2026.4.1
choco pack smicli.nuspec
# 產生 smicli.2026.4.1.nupkg
```

或在 Linux 使用 `nuget` CLI（需先把 nuspec/tools 複製到 Linux）：

```bash
nuget pack smicli.nuspec
```

**Step E：上傳到 Nexus**

從 Linux 執行：

```bash
# 先把 .nupkg 從 Windows 拉過來
sshpass -p "1.a" scp -o StrictHostKeyChecking=no \
  "administrator@10.8.113.3:C:/ssd-testkit/bin/chocolatey/packages/smicli/2026.4.1/smicli.2026.4.1.nupkg" \
  /tmp/

# 上傳到 Nexus
curl -sk --max-time 60 -u "admin:1.a" \
  -X POST "https://127.0.0.1/service/rest/v1/components?repository=choco-hosted-nas" \
  -F "nuget.asset=@/tmp/smicli.2026.4.1.nupkg;type=application/octet-stream" \
  -w "\nHTTP:%{http_code}\n"
# 預期 HTTP:204
```

**Step F：備份 .nupkg 到 NAS**

```bash
cp /tmp/smicli.2026.4.1.nupkg \
   /mnt/nas-mdt/Team/PQ1-3/tool/ssd-testkit-source/windows/nupkg/
```

**Step G：更新 packages.config 並 git commit**

在 ssd-testkit repo：

```xml
<!-- bin/chocolatey/config/packages.config -->
<package id="smicli" version="2026.4.1" />
```

```bash
git add bin/chocolatey/packages/smicli/2026.4.1/
git add bin/installers/SmiCli/v20260401A/
git add bin/chocolatey/config/packages.config
git commit -m "chore: upgrade smicli to 2026.4.1 (v20260401A)"
```

---

#### 動作清單總覽

| # | 動作 | 位置 | 必要？ |
|---|------|------|--------|
| A | 放入 installer 檔案到 `bin\installers\` | ssd-testkit repo | ✅ |
| B | 備份 installer 到 NAS `ssd-testkit-source` | NAS | 建議 |
| C | 新建 nuspec + chocolateyInstall.ps1 | ssd-testkit repo | ✅ |
| D | `choco pack` 打包成 .nupkg | Windows 或 Linux | ✅ |
| E | 上傳 .nupkg 到 Nexus `choco-hosted-nas` | Linux curl | ✅ |
| F | 備份 .nupkg 到 NAS `ssd-testkit-source/nupkg` | NAS | 建議 |
| G | 更新 `packages.config` 版本號 | ssd-testkit repo | ✅ |
| H | git commit | ssd-testkit repo | ✅ |

> **舊版本要刪嗎？**  
> NAS 只增不刪；Nexus 多版本並存。`packages.config` 的 git 歷史保留所有過去版本記錄，
> 任何時間點 checkout 舊 commit，都能從 NAS 或 Nexus 找到對應版本的檔案。

---

## Step 1：NAS 開機自動掛載（/etc/fstab）

```bash
# 建立認證檔（密碼不寫在 fstab 明文中）
sudo tee /etc/samba/nas-mdt.creds > /dev/null <<EOF
username=mdt
password=p@ssw0rd
EOF
sudo chmod 600 /etc/samba/nas-mdt.creds

# 建立掛載點
sudo mkdir -p /mnt/nas-mdt

# 加入 /etc/fstab
echo "//10.250.0.1/mdt  /mnt/nas-mdt  cifs  credentials=/etc/samba/nas-mdt.creds,uid=1000,gid=1000,dir_mode=0777,file_mode=0666,vers=3.0,iocharset=utf8,_netdev,x-systemd.automount  0  0" \
  | sudo tee -a /etc/fstab

# 立即測試掛載
sudo mount -a && echo "fstab mount OK"
ls /mnt/nas-mdt/Team/PQ1-3/tool/ssd-testkit-nexus/
```

---

## Step 2：更新 docker-compose.yml 加入 NAS volume

`nexus/docker/docker-compose.yml` 的 nexus service volumes 已加入：

```yaml
volumes:
  - nexus-data:/nexus-data
  - /mnt/nas-mdt/Team/PQ1-3/tool/ssd-testkit-nexus:/nexus-nas-blob
```

重啟容器套用：

```bash
cd nexus/docker
docker compose down
docker compose up -d
docker compose ps

# 確認 volume 已掛入容器
docker exec nexus ls /nexus-nas-blob
```

---

## Step 3：在 Nexus 建立 NAS File Blob Store

```bash
curl -sk --max-time 15 -u "admin:1.a" \
  -X POST "https://127.0.0.1/service/rest/v1/blobstores/file" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "nas-blob",
    "path": "/nexus-nas-blob",
    "softQuota": null
  }' -w "\nHTTP:%{http_code}\n"
# 預期 HTTP:204
```

驗證：
```bash
curl -sk -u "admin:1.a" "https://127.0.0.1/service/rest/v1/blobstores" | \
  python3 -c "import sys,json; [print(b['name'], b['type']) for b in json.load(sys.stdin)]"
```

---

## Step 4：建立使用 NAS blob store 的 Repositories

### 4a. choco-hosted-nas（NuGet）

```bash
curl -sk --max-time 15 -u "admin:1.a" \
  -X POST "https://127.0.0.1/service/rest/v1/repositories/nuget/hosted" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "choco-hosted-nas",
    "online": true,
    "storage": {
      "blobStoreName": "nas-blob",
      "strictContentTypeValidation": true,
      "writePolicy": "allow"
    }
  }' -w "\nHTTP:%{http_code}\n"
# 預期 HTTP:204
```

### 4b. raw-linux-tools-nas（Raw）

```bash
curl -sk --max-time 15 -u "admin:1.a" \
  -X POST "https://127.0.0.1/service/rest/v1/repositories/raw/hosted" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "raw-linux-tools-nas",
    "online": true,
    "storage": {
      "blobStoreName": "nas-blob",
      "strictContentTypeValidation": false,
      "writePolicy": "allow"
    }
  }' -w "\nHTTP:%{http_code}\n"
# 預期 HTTP:204
```

---

## Step 5：重新上傳 .nupkg 到 choco-hosted-nas，並備份原始檔到 NAS

### 5a. 上傳到 Nexus

```bash
# 從 Linux 直接上傳（/tmp/nupkg_upload 已有撈好的檔案）
SUCCESS=0; FAILED=0
for nupkg in $(find /tmp/nupkg_upload -name "*.nupkg" | sort); do
    name=$(basename "$nupkg")
    printf "  %-50s " "$name"
    status=$(curl -sk --max-time 60 -u "admin:1.a" \
      -X POST "https://127.0.0.1/service/rest/v1/components?repository=choco-hosted-nas" \
      -F "nuget.asset=@${nupkg};type=application/octet-stream" \
      -o /tmp/up_result.json -w "%{http_code}")
    if [[ "$status" == "204" ]]; then echo "OK"; ((SUCCESS++))
    else echo "FAILED (HTTP $status)"; ((FAILED++)); fi
done
echo "Upload: $SUCCESS OK, $FAILED FAILED"
```

若 `/tmp/nupkg_upload` 已清除，重新從 Windows 撈取：

```bash
mkdir -p /tmp/nupkg_upload && \
sshpass -p "1.a" scp -o StrictHostKeyChecking=no -r \
  "administrator@10.8.113.3:C:/ssd-testkit/bin/chocolatey/packages" \
  /tmp/nupkg_upload/
```

### 5b. 備份原始 .nupkg 到 NAS（災難復原用）

```bash
# 建立 NAS 備份目錄
mkdir -p /mnt/nas-mdt/Team/PQ1-3/tool/ssd-testkit-source/nupkg

# 複製所有 .nupkg（原始檔靜態存檔）
cp /tmp/nupkg_upload/packages/**/*.nupkg \
   /mnt/nas-mdt/Team/PQ1-3/tool/ssd-testkit-source/nupkg/ 2>/dev/null || \
find /tmp/nupkg_upload -name "*.nupkg" -exec cp {} \
   /mnt/nas-mdt/Team/PQ1-3/tool/ssd-testkit-source/nupkg/ \;

echo "Backed up nupkg files:"
ls -lh /mnt/nas-mdt/Team/PQ1-3/tool/ssd-testkit-source/nupkg/
```

> **注意：** `ssd-testkit-source/` 是靜態存檔，Nexus 不會直接讀取。  
> 用途：當 Nexus 損毀需要重建時，從此處取回 .nupkg 重新上傳。

---

## Step 6：驗證 NAS 上存在 blob 檔案

```bash
# Linux 端確認 NAS 路徑有資料
ls -lh /mnt/nas-mdt/Team/PQ1-3/tool/ssd-testkit-nexus/
du -sh /mnt/nas-mdt/Team/PQ1-3/tool/ssd-testkit-nexus/

# Nexus API 確認 choco-hosted-nas 套件數量
curl -sk -u "admin:1.a" \
  "https://127.0.0.1/service/rest/v1/components?repository=choco-hosted-nas" | \
  python3 -c "
import sys,json
d=json.load(sys.stdin)
print(f'Total: {len(d[\"items\"])}')
for i in sorted(d['items'],key=lambda x:x['name']): print(f'  {i[\"name\"]:30s} {i[\"version\"]}')
"
```

---

## Step 7：更新 ssd-testkit sources.config

在 `ssd-testkit` 專案的 `bin/chocolatey/config/sources.config` 中，將 nexus URL 改為：

```yaml
nexus:
  type: nuget_v3
  url: "https://10.252.170.171/repository/choco-hosted-nas/"
  api_key_env: "NEXUS_API_KEY"
```

---

## Rollback

若 NAS 出現問題，直接修改 `sources.config` 切回：

```yaml
# 切回本地 disk 版本
nexus:
  url: "https://10.252.170.171/repository/choco-hosted/"
```

或切回 offline 模式：

```yaml
active_source: offline
```

---

## Step 8：設定 nexus-data 每日自動備份（cron）

`nexus-data` volume 存放 Nexus 設定、user/role、DB metadata，需定期備份到 NAS。

```bash
# 建立備份目錄
sudo mkdir -p /mnt/nas-mdt/Team/PQ1-3/tool/ssd-testkit-backup

# 建立備份 script
sudo tee /usr/local/bin/nexus-backup.sh > /dev/null <<'EOF'
#!/bin/bash
set -e
BACKUP_DIR="/mnt/nas-mdt/Team/PQ1-3/tool/ssd-testkit-backup"
DATE=$(date +%Y%m%d)
DEST="${BACKUP_DIR}/nexus-data-${DATE}.tar.gz"

# 確認 NAS 已掛載
if ! mountpoint -q /mnt/nas-mdt; then
  echo "ERROR: NAS not mounted at /mnt/nas-mdt" >&2
  exit 1
fi

# 停止 Nexus 保證資料一致性（備份後自動重啟）
docker stop nexus
docker run --rm \
  -v docker_nexus-data:/data:ro \
  -v "${BACKUP_DIR}:/backup" \
  alpine tar czf "/backup/nexus-data-${DATE}.tar.gz" -C /data .
docker start nexus

echo "Backup OK: ${DEST}"

# 保留最近 14 天，刪除舊備份
find "${BACKUP_DIR}" -name "nexus-data-*.tar.gz" -mtime +14 -delete
EOF
sudo chmod +x /usr/local/bin/nexus-backup.sh
```

```bash
# 加入 cron（每天 02:00 執行）
(sudo crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/nexus-backup.sh >> /var/log/nexus-backup.log 2>&1") \
  | sudo crontab -
sudo crontab -l
```

手動測試備份：

```bash
sudo /usr/local/bin/nexus-backup.sh
ls -lh /mnt/nas-mdt/Team/PQ1-3/tool/ssd-testkit-backup/
```

> **crontab 的存活性說明：**  
> crontab 設在 **Linux host**（`sudo crontab`），不在容器內。  
> - `docker compose restart` / `down && up` → **不影響**，host cron 繼續跑  
> - Linux host 重開機 → **不影響**，儲存於 `/var/spool/cron/crontabs/root`  
> - **換新主機（災難復原）** → 需要重新執行 Step 1 + Step 8 的設定指令

### 換新主機時需重新執行的步驟

```bash
# 1. 安裝必要套件
sudo apt-get install -y cifs-utils

# 2. 重建 NAS 認證檔
sudo mkdir -p /etc/samba
sudo tee /etc/samba/nas-mdt.creds > /dev/null <<'EOF'
username=mdt
password=p@ssw0rd
EOF
sudo chmod 600 /etc/samba/nas-mdt.creds

# 3. 重建 fstab（掛載 NAS）
sudo mkdir -p /mnt/nas-mdt
echo "//10.250.0.1/mdt  /mnt/nas-mdt  cifs  credentials=/etc/samba/nas-mdt.creds,uid=1000,gid=1000,dir_mode=0777,file_mode=0666,vers=3.0,iocharset=utf8,_netdev,x-systemd.automount  0  0" \
  | sudo tee -a /etc/fstab
sudo mount -a

# 4. 重建 backup script
sudo cp /path/to/repo/scripts/nexus-backup.sh /usr/local/bin/nexus-backup.sh
sudo chmod +x /usr/local/bin/nexus-backup.sh

# 5. 重建 crontab
(sudo crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/nexus-backup.sh >> /var/log/nexus-backup.log 2>&1") \
  | sudo crontab -
```

---

## NAS 目錄結構總覽

```
\\10.250.0.1\mdt\Team\PQ1-3\tool\
├── ssd-testkit-nexus/        ← Nexus blob store（即時，Nexus 直接讀寫）
├── ssd-testkit-backup/       ← nexus-data volume 每日快照（保留 14 天）
│   ├── nexus-data-20260330.tar.gz
│   └── nexus-data-20260331.tar.gz
└── ssd-testkit-source/       ← 原始 .nupkg 靜態備份（每次新增工具更新）
    └── nupkg/
        ├── burnin.10.2.1004.nupkg
        └── ...
```

---

## 災難復原流程

### 情境 A：主機磁碟壞掉，NAS 正常

```bash
# 1. 新機器啟動容器（空 nexus-data）
cd nexus/docker && docker compose up -d

# 2. 還原最新備份
LATEST=$(ls -t /mnt/nas-mdt/Team/PQ1-3/tool/ssd-testkit-backup/nexus-data-*.tar.gz | head -1)
docker stop nexus
docker run --rm -v docker_nexus-data:/data -v "$(dirname $LATEST):/backup" \
  alpine tar xzf "/backup/$(basename $LATEST)" -C /data
docker start nexus
# Nexus 設定、user、DB 恢復，blob 仍在 NAS 原路徑，直接可用
```

### 情境 B：NAS blob 也損毀

```bash
# 從 source 備份重新上傳
find /mnt/nas-mdt/Team/PQ1-3/tool/ssd-testkit-source/nupkg -name "*.nupkg" | while read f; do
  curl -sk --max-time 60 -u "admin:1.a" \
    -X POST "https://127.0.0.1/service/rest/v1/components?repository=choco-hosted-nas" \
    -F "nuget.asset=@${f};type=application/octet-stream" -w "%{http_code}\n"
done
```

---

## 驗收 Checklist

- [x] `/etc/fstab` 設定（含 `dir_mode=0777`），重開機後 NAS 自動掛載
- [x] `docker exec nexus ls /nexus-nas-blob` 有回應且可寫入
- [x] Nexus blob store `nas-blob` 建立完成（Web UI → Admin → Blob Stores）
- [x] `choco-hosted-nas` repository 存在
- [x] `raw-linux-tools-nas` repository 存在
- [x] 11 個 .nupkg 上傳到 `choco-hosted-nas` 完成
- [x] NAS `ssd-testkit-source/windows/nupkg/` 有 11 個 .nupkg 原始檔
- [x] NAS `ssd-testkit-source/windows/installers/` 有 7.8GB 原始工具（robocopy 完成）
- [x] cron 設定完成（每天 02:00），`nexus-backup.sh` 手動測試 56MB 成功
- [x] NAS `ssd-testkit-backup/` 有 `nexus-data-20260330.tar.gz`
- [ ] `bootstrap.ps1 -Source nexus` 能從 `choco-hosted-nas` 下載安裝（Phase 2.2 時驗證）

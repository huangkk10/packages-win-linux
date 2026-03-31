# NAS 儲存設計

## 連線資訊

| 項目 | 值 |
|------|---|
| NAS IP | `10.250.0.1` |
| SMB Share | `mdt` |
| NAS 使用者 | `mdt` |
| NAS 密碼 | `p@ssw0rd` |
| NAS 根路徑 | `\\10.250.0.1\mdt\Team\PQ1-3\tool\` |
| Linux 掛載點 | `/mnt/nas-mdt` |
| Nexus 容器內路徑 | `/nexus-nas-blob` |

## NAS 目錄結構

```
\\10.250.0.1\mdt\Team\PQ1-3\tool\
├── ssd-testkit-nexus/              ← Nexus blob store（Nexus 直接讀寫，不手動動）
├── ssd-testkit-backup/             ← nexus-data volume 每日快照（保留 14 天）
│   ├── nexus-data-20260330.tar.gz
│   └── nexus-data-YYYYMMDD.tar.gz
└── ssd-testkit-source/             ← 原始檔靜態備份（人工管理）
    └── windows/
        ├── installers/             ← 照搬 bin\installers，保留原始資料夾名稱
        │   ├── SmiCli/
        │   │   ├── v20251114A/     ← 舊版保留（rollback 用）
        │   │   └── v20260213C/     ← 當前版本
        │   ├── SmiWinTools/v20260213C/
        │   ├── BurnIn/10.2.1004/
        │   ├── CrystalDiskInfo/8.17.13/
        │   ├── PHM/V4.22.0_B25.02.06.02_H/
        │   ├── WindowsADK/26100.0.0/
        │   ├── net_7_sdk/7.0.410/
        │   └── playwright-browsers/1.58.0/
        ├── zip/                    ← 壓縮版備份（供手動下載 / 緊急取用）
        │   ├── SmiCli-v20260213C.zip
        │   ├── SmiWinTools-v20260213C.zip
        │   └── <ToolName>-<Version>.zip
        └── nupkg/                  ← Chocolatey .nupkg 靜態備份
            ├── smicli.2026.2.13.nupkg
            ├── burnin.10.2.1004.nupkg
            └── <id>.<version>.nupkg
```

**各目錄用途對比：**

| 目錄 | 誰寫 | 用途 |
|------|------|------|
| `ssd-testkit-nexus/` | Nexus 自動 | blob store 實體檔案，不手動操作 |
| `ssd-testkit-backup/` | cron 每日 | nexus-data volume 備份，災難復原用 |
| `ssd-testkit-source/installers/` | 人工 robocopy | 原始 binary 靜態存檔，只增不刪 |
| `ssd-testkit-source/zip/` | 人工壓縮 | 壓縮備份，方便單檔下載 |
| `ssd-testkit-source/nupkg/` | 人工複製 | .nupkg 靜態存檔，Nexus 損毀時重新上傳 |

## Linux 掛載設定

### /etc/fstab

```
//10.250.0.1/mdt  /mnt/nas-mdt  cifs
  credentials=/etc/samba/nas-mdt.creds,
  uid=1000,gid=1000,
  dir_mode=0777,file_mode=0666,
  vers=3.0,iocharset=utf8,
  _netdev,x-systemd.automount  0  0
```

### /etc/samba/nas-mdt.creds (chmod 600)

```
username=mdt
password=p@ssw0rd
```

### 掛載指令

```bash
sudo mount -a   # 依 fstab 掛載
# 或手動測試
sudo mount -t cifs //10.250.0.1/mdt /mnt/nas-mdt \
  -o credentials=/etc/samba/nas-mdt.creds,vers=3.0
```

## Windows 連線（robocopy）

```powershell
net use Z: \\10.250.0.1\mdt /user:mdt "p@ssw0rd"
robocopy C:\ssd-testkit\bin\installers\SmiCli\v20260213C `
  Z:\Team\PQ1-3\tool\ssd-testkit-source\windows\installers\SmiCli\v20260213C `
  /E /Z
net use Z: /delete
```

## 每日自動備份（cron）

備份腳本：`/usr/local/bin/nexus-backup.sh`  
執行時間：每天 02:00  
保留期限：14 天

```bash
# 手動執行
sudo /usr/local/bin/nexus-backup.sh

# 查看 crontab 設定
sudo crontab -l
```

## 災難復原

**情境 A：主機磁碟壞，NAS 正常**
→ 裝新機、啟動 Docker、從 `ssd-testkit-backup/` 最新快照還原 nexus-data

**情境 B：NAS blob 也損毀**
→ 從 `ssd-testkit-source/nupkg/` 重新上傳所有 .nupkg 至 Nexus

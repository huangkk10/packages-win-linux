# Nexus Bootstrap README 計畫

**目標：** 使用者只需一個 URL，就能看到「如何裝 Chocolatey」與「所有可用工具」，不需進 Nexus UI  
**方案：** 在 `raw-windows-bootstrap` 放入包含完整資訊的 `README.txt`，配合 Nginx `/readme` 短路徑  
**狀態：** ✅ 完成（2026-04-13）

---

## 使用者入口（目標：只需一個 URL）

```
使用者只需記住一個地址：

    http://10.252.170.171/readme

打開即可看到：
  1. 如何安裝 Chocolatey（一行指令）
  2. 所有可用工具清單 + 各自的 choco install 指令

Nexus UI 只給管理員用，一般使用者不需進入。
```

---

## Repository 選擇依據

| Repository | 格式 | 現有內容 | 適合放 README？ |
|------------|------|----------|---------------|
| `choco-hosted` | NuGet | 所有工具 `.nupkg` | ❌ Raw 檔案不支援 |
| `raw-windows-bootstrap` | Raw | `b.ps1` + `chocolatey.nupkg` | ✅ **選此** |
| `raw-linux-tools` | Raw | Linux binary（待用） | ❌ 不相關 |

---

## 存取方式

| 入口 | URL |
|------|-----|
| **主要入口** | `http://10.252.170.171/readme` |
| 完整路徑 | `https://10.252.170.171/repository/raw-windows-bootstrap/README.txt` |
| Nexus UI Browse | Browse → `raw-windows-bootstrap` → 點 `README.txt` |

---

## README.txt 內容規劃

存放位置：`packages/windows/bootstrap/README.txt`（此 repo 版控）

```
================================================================
  Windows 工具安裝說明（內網）
  Nexus: https://10.252.170.171   更新日期: 2026-04-13
================================================================

【第一次使用】先安裝 Chocolatey

  以系統管理員開啟 PowerShell，執行一行：

    Set-ExecutionPolicy Bypass -Scope Process -Force; iwr http://10.252.170.171/b -UseBasicParsing | iex

  自動完成：寫入 hosts → 安裝 Chocolatey → 登錄 Nexus 來源

----------------------------------------------------------------
【可用工具清單】

  工具名稱                版本            安裝指令
  ---------------------------------------------------------------
  Windows ADK          26100.0.0       choco install windows-adk        --version 26100.0.0 -y
  BurnIn Test          10.2.1004       choco install burnin             --version 10.2.1004  -y
  CrystalDiskInfo      8.17.13         choco install cdi                --version 8.17.13    -y
  SmiCli               2026.2.13       choco install smicli             --version 2026.2.13  -y
  SmiWinTools          2026.2.13.1     choco install smiwintools        --version 2026.2.13.1 -y
  PHM                  4.22.0          choco install phm                --version 4.22.0     -y
  .NET 7 SDK           7.0.410         choco install net-7-sdk          --version 7.0.410    -y
  Playwright Browsers  1.58.0          choco install playwright-browsers --version 1.58.0    -y

  一次安裝全部工具：
    choco install windows-adk burnin cdi smicli smiwintools phm net-7-sdk playwright-browsers -y

----------------------------------------------------------------
【查詢所有可用版本】

  choco search --source "https://nexus.internal/repository/choco-hosted" --all-versions

================================================================
```

---

## Step 1：建立 `README.txt`

存放位置：`packages/windows/bootstrap/README.txt`

---

## Step 2：上傳到 Nexus

```bash
cd /home/owner/Codes/packages-win-linux
curl -sk -u "admin:1.a" -X PUT \
  "https://127.0.0.1/repository/raw-windows-bootstrap/README.txt" \
  --upload-file packages/windows/bootstrap/README.txt \
  -w "HTTP:%{http_code}\n"
```

---

## Step 3：Nginx 加 `/readme` 短路徑

編輯 `nexus/nginx/nexus.conf`，在 HTTP server 區塊加入：

```nginx
location = /readme {
    proxy_pass http://nexus:8081/repository/raw-windows-bootstrap/README.txt;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    # 強制瀏覽器顯示文字而非下載
    add_header Content-Type "text/plain; charset=utf-8";
    add_header Content-Disposition "inline";
}
```

重載 nginx：
```bash
cd nexus/docker && docker compose exec nginx nginx -s reload
```

---

## Step 4：驗證

```bash
# 確認可取得
curl -s "http://10.252.170.171/readme" | head -5

# 確認 Nexus UI Browse 可見
curl -sk -u "admin:1.a" \
  "https://127.0.0.1/service/rest/v1/search?repository=raw-windows-bootstrap" | \
  python3 -c "import sys,json; [print(a['path']) for i in json.load(sys.stdin)['items'] for a in i['assets']]"
```

預期輸出：
```
/README.txt
/b.ps1
/chocolatey.nupkg
```

---

## 工作項目

| # | 工作 | 狀態 |
|---|------|------|
| 1 | 建立 `packages/windows/bootstrap/README.txt` | ✅ 完成 |
| 2 | 上傳 `README.txt` 到 Nexus `raw-windows-bootstrap` | ✅ 完成 |
| 3 | Nginx HTTP server 加 `/readme` 短路徑 | ✅ 完成 |
| 4 | reload nginx | ✅ 完成 |
| 5 | 驗證 `http://10.252.170.171/readme` 可正常瀏覽 | ✅ 完成 |

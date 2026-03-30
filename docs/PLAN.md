# Nexus 版本管理伺服器建置計畫

**目標 Repository：** https://github.com/huangkk10/ssd-testkit (branch: develop)  
**文件日期：** 2026-03-30  
**文件狀態：** 進行中（Phase 2）

| Phase | 狀態 |
|-------|------|
| Phase 0 前置準備 | ✅ 完成 |
| Phase 1 Nexus 伺服器建置 | ✅ 完成（2026-03-30） |
| Phase 2 Windows Chocolatey 整合 | 🔄 進行中 |
| Phase 3 Linux 套件管理 | ⬜ 待做 |
| Phase 4 Python 依賴統一 | ⬜ 待做 |
| Phase 5 Onboarding | ⬜ 待做 |

**Nexus 伺服器：** https://10.252.170.171  
**Nexus 版本：** Community 3.77.0-08

---

## 一、現狀分析

### ssd-testkit 目前的工具依賴

| 分類 | 工具 / 套件 | 版本 | 平台 |
|------|------------|------|------|
| 測試工具 | BurnIn Test (`bit.exe`) | 10.2.1004 | Windows |
| 測試工具 | CrystalDiskInfo (`cdi`) | 8.17.13 | Windows |
| 測試工具 | SmiCli (`SmiCli2.exe`) | 2026.2.13 | Windows |
| 測試工具 | SmiWinTools | 2026.2.13.1 | Windows |
| 測試工具 | Powerhouse Mountain (PHM) | 4.22.0 | Windows |
| 系統工具 | Windows ADK | 26100.0.0 (Win11 24H2) | Windows |
| 執行環境 | .NET 7 SDK | 7.0.410 | Windows |
| 瀏覽器 | Playwright Browsers | 1.58.0 | Windows |
| Python | pytest, pywin32, pywinauto, playwright, Pillow, psutil, WMI ... | 見 requirements.txt | Windows |

### 已完成的 Chocolatey 基礎建設

```
bin/chocolatey/
├── installer/
│   └── bootstrap.ps1          # 一鍵 bootstrap：裝 choco → 設定來源 → 安裝套件
├── scripts/
│   ├── install_choco.ps1      # 離線安裝 Chocolatey 本體（從 .nupkg）
│   └── install_packages.ps1   # 從指定來源安裝所有套件
├── packages/
│   ├── burnin/10.2.1004/      # 各套件 .nupkg + chocolateyInstall.ps1
│   ├── cdi/8.17.13/
│   ├── windows-adk/26100.0.0/
│   ├── smicli/                # (多版本)
│   ├── smiwintools/
│   ├── phm/4.22.0/
│   ├── playwright-browsers/1.58.0/
│   └── net-7-sdk/7.0.410/
└── config/
    ├── environment.config     # active_source: offline | nexus | nas
    ├── sources.config         # 三種來源定義（已預留 nexus 設定位置）
    └── packages.config        # 要安裝的套件清單（XML）
```

**目前模式：** `active_source: offline`（本地資料夾）  
**已預留：** `sources.config` 中已有 Nexus NuGet Hosted 設定位置（URL 佔位符）  
**缺少：**
- Nexus 伺服器尚未建立
- Linux 沒有對應的套件管理機制
- Python 依賴尚未納入統一管理

---

## 二、目標架構

```
┌─────────────────────────────────────────────────────────────────┐
│                     Nexus Repository Manager                    │
│                                                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌────────────────┐  │
│  │  choco-hosted   │  │   pypi-proxy    │  │  raw-hosted    │  │
│  │  (NuGet v3)     │  │  (PyPI mirror)  │  │  (Linux bins)  │  │
│  │                 │  │                 │  │  apt-proxy     │  │
│  │  .nupkg files   │  │  pip packages   │  │  (apt mirror)  │  │
│  └────────┬────────┘  └────────┬────────┘  └───────┬────────┘  │
└───────────┼────────────────────┼───────────────────┼───────────┘
            │                    │                   │
     ┌──────┴──────┐      ┌──────┴──────┐    ┌──────┴──────┐
     │   Windows   │      │  Windows /  │    │    Linux    │
     │  bootstrap  │      │    Linux    │    │  bootstrap  │
     │ (choco +    │      │ (pip install│    │ (bash/apt + │
     │  bootstrap  │      │  -i nexus)  │    │  raw bins)  │
     │  .ps1)      │      └─────────────┘    └─────────────┘
     └─────────────┘
```

**核心原則：**
- 開發者只需能連到 Nexus，不需要公網網路
- 一個指令完成環境建置（Windows: `bootstrap.ps1`，Linux: `bootstrap.sh`）
- Nexus 作為 proxy 或 hosted，統一管理所有版本

---

## 三、工作計畫

### Phase 0：前置準備與規劃（評估）

**目標：** 決定 Nexus 部署方式與網路規劃

- [ ] 決定 Nexus 部署位置（實體機 / VM / Docker）
- [ ] 決定 Nexus 的 hostname / IP（例如 `nexus.internal` 或 `10.x.x.x:8081`）
- [ ] 確認 ssd-testkit 開發主機到 Nexus 的網路通路
- [ ] 確認是否需要 HTTPS（建議 self-signed + CA trust）
- [ ] 確認 Nexus 儲存空間需求（估算所有 .nupkg + Python packages 大小）

**產出：**
- 部署環境決定書（一頁）
- Nexus hostname / port 確認

---

### Phase 1：Nexus 伺服器建置

**目標：** 建立可用的 Nexus Repository Manager

#### 1.1 安裝 Nexus（推薦 Docker Compose）

```yaml
# docker-compose.yml 範例
version: "3.8"
services:
  nexus:
    image: sonatype/nexus3:latest
    container_name: nexus
    ports:
      - "8081:8081"     # Web UI / NuGet / PyPI
      - "8082:8082"     # Docker (可選)
    volumes:
      - nexus-data:/nexus-data
    restart: unless-stopped

volumes:
  nexus-data:
```

#### 1.2 建立 Repository

| Repository 名稱 | 類型 | 格式 | 用途 |
|----------------|------|------|------|
| `choco-hosted` | hosted | nuget | Windows Chocolatey .nupkg |
| `pypi-proxy` | proxy | pypi | 代理 PyPI，pip install 快取 |
| `pypi-hosted` | hosted | pypi | 內部自製 Python 套件（選用） |
| `pypi-group` | group | pypi | 合併 proxy + hosted，提供單一 URL |
| `raw-linux-tools` | hosted | raw | Linux 二進位工具（tar.gz / .sh） |
| `apt-proxy` | proxy | apt | 代理 Ubuntu/Debian apt 套件（選用） |

#### 1.3 建立使用者與 API Key

```
角色規劃：
- admin        : Nexus 管理員
- uploader     : 上傳套件（CI/CD 用）
- developer    : 只讀下載（開發者用）

每個 developer 需要：username + password（或 API token）
```

#### 1.4 設定 HTTPS（建議）

- 使用 Nginx reverse proxy + Let's Encrypt / self-signed
- 開發者匯入 CA 憑證（Windows: `certutil`，Linux: `update-ca-certificates`）

**驗收條件：**
- [x] Nexus Web UI 可正常登入（https://10.252.170.171）
- [x] `choco-hosted` repository 存在
- [x] `pypi-group` repository 可用
- [x] `raw-linux-tools` repository 存在

---

### Phase 2：Windows Chocolatey 整合（Nexus）

**目標：** 讓 `bootstrap.ps1 -Source nexus` 可正常運作  
**狀態：** 🔄 進行中

#### 2.1 上傳 .nupkg 到 Nexus

**來源機器（ssd-testkit Windows PC）**

| 項目 | 內容 |
|------|------|
| IP | 10.8.113.3 |
| 使用者 | administrator |
| 專案路徑 | `C:\ssd-testkit\bin\chocolatey\packages\` |
| SSH | Port 22（已確認可用） |

**上傳方式：從 Linux 伺服器 SSH 撈檔後批次上傳（`scripts/upload/upload_nupkg.sh`）**

```bash
# 在 packages-win-linux 根目錄執行（所有預設值已內建）
bash scripts/upload/upload_nupkg.sh

# 如需自訂：
bash scripts/upload/upload_nupkg.sh \
  --nexus-url https://10.252.170.171 \
  --win-host  10.8.113.3 \
  --win-user  administrator \
  --win-pass  1.a \
  --win-path  "C:/ssd-testkit/bin/chocolatey/packages"
```

腳本流程：
1. SSH 進 Windows 列出所有 `.nupkg`
2. `scp` 複製到 Linux 暫存
3. `curl` 批次 POST 到 Nexus `choco-hosted`
4. 清除暫存

#### 2.2 修改 `sources.config`（ssd-testkit 內）

```yaml
# 將佔位符替換為實際 Nexus URL
nexus:
  type: nuget_v3
  url: "https://10.252.170.171/repository/choco-hosted/"
  api_key_env: "NEXUS_API_KEY"
```

#### 2.3 修改 `environment.config`（或透過 bootstrap 參數切換）

```yaml
# 切換為 nexus 模式
active_source: nexus
```

或使用參數：
```powershell
.\bootstrap.ps1 -Source nexus
```

#### 2.4 Nexus API Key 設定

開發者在 Windows 機器設定一次即可（以 `developer` 帳號為例）：
```powershell
$cred = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("developer:Developer@2026"))
[System.Environment]::SetEnvironmentVariable("NEXUS_API_KEY", $cred, "Machine")
```

**驗收條件：**
- [ ] 所有 .nupkg 上傳到 `choco-hosted-nas` 可在 Web UI Browse 看到
- [ ] `bootstrap.ps1 -Source nexus` 在全新 Windows 機器可完整執行
- [ ] 所有套件從 Nexus 下載安裝成功
- [ ] 不需要公網連線

#### 2.5 NAS Blob Store（大型檔案儲存）

**背景：** .nupkg / Linux binary 體積大，不適合放在 Nexus 主機本地磁碟，改用 NAS 集中管理。

**採用方案 B（建新 repo 並行，驗證 OK 後切換）— 零停機**

| 項目 | 值 |
|------|---|
| NAS IP | 10.250.0.1 |
| Share | `mdt` |
| 使用者 | mdt |
| 目標路徑 | `\\10.250.0.1\mdt\Team\PQ1-3\tool\ssd-testkit-nexus` |
| Linux 掛載點 | `/mnt/nas-mdt` |
| Nexus 容器內路徑 | `/nexus-nas-blob` |

**執行步驟（詳見 [docs/ops/nas-blobstore.md](ops/nas-blobstore.md)）：**

1. 設定 `/etc/fstab` 讓 NAS 開機自動掛載
2. 重啟 Nexus 容器（套用新 volume `/nexus-nas-blob`）
3. Nexus API 建立 NAS File Blob Store（路徑 `/nexus-nas-blob`）
4. 建立使用 NAS blob 的新 repositories：
   - `choco-hosted-nas`（NuGet hosted）
   - `raw-linux-tools-nas`（Raw hosted）
5. 從 Windows PC 重新上傳 .nupkg 到 `choco-hosted-nas`
6. 驗證 NAS 上確實存在 blob 檔案
7. 更新 `ssd-testkit sources.config` 切換到 `choco-hosted-nas`
8. 舊的 `choco-hosted`（local disk）可保留作 fallback

**驗收條件：**
- [ ] NAS 開機自動掛載正常
- [ ] Nexus blob store `nas-blob` 建立完成
- [ ] `choco-hosted-nas` 可上傳並瀏覽套件
- [ ] NAS 路徑下可看到實際的 blob 檔案
- [ ] `bootstrap.ps1 -Source nexus` 能從 `choco-hosted-nas` 下載

---

### Phase 3：Linux 套件管理（Nexus）

**目標：** Linux 開發機也能透過 Nexus 安裝所有測試工具

#### 3.1 盤點 Linux 需要的工具

| 工具 | 取得方式 | 計畫 Nexus 路徑 |
|------|---------|----------------|
| Python 3.x | apt-proxy | `nexus/apt-proxy` |
| pip packages (requirements.txt) | pypi-group | `nexus/pypi-group/simple/` |
| Playwright browsers | raw-linux-tools | `raw-linux-tools/playwright/` |
| SMI tools (如有 Linux 版本) | raw-linux-tools | `raw-linux-tools/smicli/` |
| 其他 binary 工具 | raw-linux-tools | `raw-linux-tools/<tool>/` |

> **注意：** ssd-testkit 目前主要在 Windows 上執行，需確認哪些測試可在 Linux 運行，再決定 Linux 工具清單。

#### 3.2 建立 `bin/linux/` 目錄結構（類比 Chocolatey）

```
bin/linux/
├── bootstrap.sh               # 一鍵 bootstrap
├── config/
│   ├── environment.config     # active_source: nexus | offline
│   ├── sources.config         # Nexus raw-linux-tools URL
│   └── packages.config        # 要安裝的工具清單（YAML/JSON）
└── scripts/
    ├── install_pip_packages.sh    # pip install from Nexus PyPI
    ├── install_raw_tools.sh       # 從 Nexus raw 下載二進位工具
    └── setup_playwright.sh        # Playwright Linux browser setup
```

#### 3.3 `bootstrap.sh` 流程設計

```bash
#!/usr/bin/env bash
# bootstrap.sh
# 1. 讀取 environment.config（active_source）
# 2. 設定 pip source → Nexus PyPI group
# 3. pip install -r requirements.txt
# 4. 下載 raw binary 工具（Playwright browsers 等）
# 5. 驗證安裝結果
```

#### 3.4 上傳 Linux binary 到 Nexus raw-linux-tools

```bash
# 範例：上傳 Playwright Linux browser bundle
curl -u uploader:password \
  --upload-file playwright-linux-1.58.0.tar.gz \
  http://nexus.internal:8081/repository/raw-linux-tools/playwright/1.58.0/playwright-linux.tar.gz
```

**驗收條件：**
- [ ] Linux 機器執行 `bootstrap.sh` 可完整建立開發環境
- [ ] `pip install -r requirements.txt` 從 Nexus 下載
- [ ] 所需 binary 工具可從 Nexus 獲取

---

### Phase 4：Python 依賴統一（Windows + Linux）

**目標：** Windows 與 Linux 都從 Nexus PyPI 安裝 Python 套件

#### 4.1 設定 pip 指向 Nexus

```ini
# pip.ini (Windows: %APPDATA%\pip\pip.ini)
# pip.conf (Linux: ~/.config/pip/pip.conf 或 /etc/pip.conf)
[global]
index-url = http://nexus.internal:8081/repository/pypi-group/simple/
trusted-host = nexus.internal
```

#### 4.2 bootstrap 腳本自動設定 pip.ini

在 `bootstrap.ps1` / `bootstrap.sh` 中加入：

```powershell
# Windows bootstrap.ps1 中加入
$pipIni = "$env:APPDATA\pip\pip.ini"
$content = @"
[global]
index-url = $nexusPyPiUrl
trusted-host = $nexusHost
"@
Set-Content -Path $pipIni -Value $content
```

#### 4.3 Nexus PyPI Proxy 設定

- Proxy URL: `https://pypi.org/`
- 開啟快取，首次下載後不再需要公網

**驗收條件：**
- [ ] `pip install -r requirements.txt` 全部從 Nexus 取得
- [ ] 斷網情況下，已快取套件可正常安裝

---

### Phase 5：開發者環境 Onboarding

**目標：** 新進開發者可以用最少步驟建立完整開發環境

#### 5.1 更新 ssd-testkit README.md

加入「快速開始」段落：

**Windows：**
```powershell
# 1. Clone repository
git clone https://github.com/huangkk10/ssd-testkit.git
cd ssd-testkit

# 2. 設定 Nexus API Key（向管理員取得）
[System.Environment]::SetEnvironmentVariable("NEXUS_API_KEY", "...", "Machine")

# 3. 一鍵環境建置
.\bin\chocolatey\installer\bootstrap.ps1 -Source nexus

# 4. Python 依賴
pip install -r requirements.txt
```

**Linux：**
```bash
# 1. Clone repository
git clone https://github.com/huangkk10/ssd-testkit.git
cd ssd-testkit

# 2. 一鍵環境建置
bash bin/linux/bootstrap.sh --source nexus

# 3. Python 依賴（由 bootstrap.sh 自動完成，或手動）
pip install -r requirements.txt
```

#### 5.2 建立 `ONBOARDING.md`

記錄：
- Nexus 連線資訊（內部網路位置）
- API Key / 帳號申請方式
- 代理設定（如有 proxy）
- 常見問題排除

#### 5.3 CI/CD 整合（選用）

在 GitHub Actions / Jenkins pipeline 中：
```yaml
- name: Bootstrap Windows tools
  run: .\bin\chocolatey\installer\bootstrap.ps1 -Source nexus
  env:
    NEXUS_API_KEY: ${{ secrets.NEXUS_API_KEY }}
```

---

## 四、技術選型說明

### 為何選 Nexus Repository Manager

| 條件 | Nexus OSS（免費版） |
|------|-------------------|
| NuGet (Chocolatey) 支援 | ✅ 原生支援 NuGet hosted/proxy |
| PyPI 支援 | ✅ 原生支援 PyPI proxy/hosted |
| Raw/Binary 支援 | ✅ raw repository |
| apt/yum 支援 | ✅ apt proxy（OSS 版有限制） |
| 自架容易度 | ✅ Docker 單容器即可 |
| 離線 / 斷網友好 | ✅ 快取後不需公網 |

### Linux 套件管理工具選擇

| 工具類型 | 建議方式 | 備註 |
|---------|---------|------|
| 系統套件（python3, git）| `apt` via Nexus apt-proxy | Ubuntu/Debian |
| Python 套件 | `pip` via Nexus pypi-group | 跨平台統一 |
| 大型 binary（playwright browsers）| Nexus raw-hosted + bash 下載 | 避免重複下載 |
| 小型腳本工具 | 直接放入 `bin/linux/tools/` | 版本控制管理 |

---

## 五、工作項目總覽（Task Backlog）

| # | Phase | 工作項目 | 負責 | 狀態 |
|---|-------|---------|------|------|
| 1 | 0 | 決定 Nexus 部署環境與 hostname | Infra | ✅ 完成（IP: 10.252.170.171） |
| 2 | 1 | 安裝 Nexus（Docker Compose） | Infra | ✅ 完成 |
| 3 | 1 | 建立 choco-hosted repository | Infra | ✅ 完成 |
| 4 | 1 | 建立 pypi-group/proxy/hosted repository | Infra | ✅ 完成 |
| 5 | 1 | 建立 raw-linux-tools repository | Infra | ✅ 完成 |
| 6 | 1 | 設定使用者與 API Key | Infra | ✅ 完成 |
| 7 | 2 | 上傳所有 Windows .nupkg 到 Nexus | Dev | 🔄 進行中 |
| 8 | 2 | 更新 sources.config 填入真實 Nexus URL | Dev | 🔄 進行中 |
| 9 | 2 | 測試 bootstrap.ps1 -Source nexus | Dev | 🔄 進行中 |
| 10 | 3 | 盤點 Linux 需要的工具清單 | Dev | 待做 |
| 11 | 3 | 建立 bin/linux/ 目錄結構與腳本 | Dev | 待做 |
| 12 | 3 | 上傳 Linux binary 工具到 Nexus raw | Dev | 待做 |
| 13 | 3 | 測試 bootstrap.sh --source nexus | Dev | 待做 |
| 14 | 4 | 設定 Nexus PyPI proxy | Infra | 待做 |
| 15 | 4 | 更新 bootstrap 腳本自動設定 pip.ini | Dev | 待做 |
| 16 | 5 | 更新 README.md 快速開始章節 | Dev | 待做 |
| 17 | 5 | 建立 ONBOARDING.md | Dev | 待做 |

---

## 六、目錄結構建議（完成後）

```
ssd-testkit/
├── bin/
│   ├── chocolatey/              # 現有 Windows Chocolatey 管理（已建立）
│   │   ├── installer/
│   │   │   └── bootstrap.ps1   # 修改：加入 pip.ini 設定
│   │   ├── scripts/
│   │   │   ├── install_choco.ps1
│   │   │   ├── install_packages.ps1
│   │   │   └── upload_to_nexus.ps1  # 新增：批次上傳腳本
│   │   ├── packages/            # .nupkg 離線備份（也上傳到 Nexus）
│   │   └── config/
│   │       ├── environment.config   # 修改：nexus URL 確認
│   │       ├── sources.config       # 修改：填入真實 Nexus URL
│   │       └── packages.config
│   └── linux/                   # 新增 Linux 套件管理
│       ├── bootstrap.sh
│       ├── config/
│       │   ├── environment.config
│       │   ├── sources.config
│       │   └── packages.config
│       └── scripts/
│           ├── install_pip_packages.sh
│           ├── install_raw_tools.sh
│           └── setup_playwright.sh
├── framework/
├── lib/
├── tests/
├── requirements.txt
├── README.md                    # 修改：加入快速開始
└── ONBOARDING.md                # 新增
```

---

## 七、風險與注意事項

| 風險 | 說明 | 緩解措施 |
|------|------|---------|
| Nexus 儲存空間不足 | Windows ADK、Playwright browsers 體積大 | 預先評估，至少預留 50GB |
| .nupkg 憑證/簽名 | 某些工具（PHM、SmiCli）可能是 NDA 軟體，需確認授權 | 上傳前確認授權允許內部分發 |
| Linux 工具版本差異 | 部分工具可能沒有 Linux 版本 | 先盤點，不強求 100% Linux 覆蓋 |
| Nexus 高可用性 | 單點故障時開發者無法建環境 | 短期：保留 `offline` 模式作為 fallback；長期：Nexus HA |
| API Key 洩漏 | 憑證不能寫死在 config | 使用環境變數，gitignore 確保不進版本控制 |
| Nexus 版本升級 | API 格式可能變更 | 固定 Docker image tag，有計畫升級 |

---

## 八、參考資源

- [Nexus Repository Manager 官方文件](https://help.sonatype.com/en/nexus-repository.html)
- [Nexus NuGet Hosted Repository 設定](https://help.sonatype.com/en/nuget-repositories.html)
- [Nexus PyPI Proxy 設定](https://help.sonatype.com/en/pypi-repositories.html)
- [Chocolatey 官方文件 - 設定私有來源](https://docs.chocolatey.org/en-us/features/private-cdn)
- [ssd-testkit bin/chocolatey/config/sources.config](https://github.com/huangkk10/ssd-testkit/blob/develop/bin/chocolatey/config/sources.config)

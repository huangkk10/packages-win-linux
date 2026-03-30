# Phase 1：Nexus 伺服器建置 — 操作手冊

## 前置條件

- Docker + Docker Compose 已安裝於目標伺服器
- 目標伺服器 port 80 / 443 已開放
- 已決定 hostname（例如 `nexus.internal`）並設定好 DNS 或 hosts 記錄

---

## Step 1：準備 SSL 憑證

將憑證檔案放到 `nexus/nginx/certs/`：

```bash
# 選項 A：使用現有公司 CA 簽發的憑證
cp your-cert.crt nexus/nginx/certs/nexus.crt
cp your-key.key  nexus/nginx/certs/nexus.key

# 選項 B：產生 Self-Signed 憑證（測試用）
openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
  -keyout nexus/nginx/certs/nexus.key \
  -out    nexus/nginx/certs/nexus.crt \
  -subj   "/CN=nexus.internal/O=Internal/C=TW"
```

---

## Step 2：設定環境變數

```bash
cp nexus/docker/.env.example nexus/docker/.env
# 編輯 .env，填入 NEXUS_HOST 等設定
```

---

## Step 3：啟動 Nexus + Nginx

```bash
cd nexus/docker
docker compose up -d

# 確認啟動狀態（Nexus 第一次啟動約需 2-3 分鐘）
docker compose ps
docker compose logs -f nexus
```

Nexus 啟動完成後，從容器內取得初始管理員密碼：

```bash
docker exec nexus cat /nexus-data/admin.password
```

瀏覽器開啟 `https://nexus.internal`，使用 `admin` + 上述密碼登入，並依照引導修改密碼。

---

## Step 4：建立 Repository

```bash
./scripts/setup/01_create_repos.sh \
  -h https://nexus.internal \
  -u admin \
  -p <your_admin_password>
```

建立完成後，Nexus UI → Browse 可看到以下 repository：

| 名稱 | 格式 | 用途 |
|------|------|------|
| `choco-hosted` | NuGet hosted | Windows Chocolatey .nupkg |
| `pypi-proxy` | PyPI proxy | 代理 pypi.org |
| `pypi-hosted` | PyPI hosted | 內部自製 Python 套件 |
| `pypi-group` | PyPI group | pip 唯一入口（proxy + hosted） |
| `raw-linux-tools` | Raw hosted | Linux binary 工具 |

---

## Step 5：建立使用者

```bash
./scripts/setup/02_create_users.sh \
  -h https://nexus.internal \
  -p <your_admin_password> \
  --uploader-pass  <uploader_password> \
  --developer-pass <developer_password>
```

| 使用者 | 角色 | 用途 |
|--------|------|------|
| `uploader` | nx-uploader | CI/CD 上傳套件 |
| `developer` | nx-developer | 開發者下載（唯讀） |

---

## Step 6：驗收確認（Checklist）

- [ ] `https://nexus.internal` Web UI 可正常登入
- [ ] `choco-hosted` repository 存在
- [ ] `pypi-group` repository 可用
- [ ] `raw-linux-tools` repository 存在
- [ ] `developer` 帳號可登入 Web UI
- [ ] `uploader` 帳號 curl 測試上傳回 201

```bash
# 驗證 uploader 可上傳（用 dummy 檔案測試）
echo "test" > /tmp/test.txt
curl -u uploader:<pass> \
  --upload-file /tmp/test.txt \
  https://nexus.internal/repository/raw-linux-tools/test/test.txt
# 預期回傳 201 Created
```

---

## 開發者機器信任 Self-Signed 憑證

**Windows：**
```powershell
certutil -addstore "Root" nexus.crt
```

**Linux：**
```bash
sudo cp nexus.crt /usr/local/share/ca-certificates/nexus-internal.crt
sudo update-ca-certificates
```

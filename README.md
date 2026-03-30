# packages-win-linux

Nexus Repository Manager 部署與套件管理，為 [ssd-testkit](https://github.com/huangkk10/ssd-testkit) 提供離線/內網工具下載服務。

## 目錄結構

```
packages-win-linux/
├── nexus/
│   ├── docker/        # Docker Compose + .env 設定
│   └── nginx/
│       └── certs/     # SSL 憑證（不進版本控制）
├── packages/
│   ├── windows/       # Windows .nupkg 離線備份
│   └── linux/         # Linux binary 工具備份（tar.gz 等）
├── scripts/
│   ├── upload/        # 上傳套件到 Nexus 的腳本（PS1 / bash）
│   ├── backup/        # Nexus 資料備份腳本
│   └── setup/         # 初始化 Nexus（建 repository、建帳號）
├── docs/              # 操作說明文件
└── PLAN.md            # 整體建置計畫
```

## 快速開始

詳見 [docs/PLAN.md](docs/PLAN.md)。

## License

MIT

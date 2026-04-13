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

  工具名稱                版本              安裝指令
  -----------------------------------------------------------------
  Windows ADK           26100.0.0         choco install windows-adk         --version 26100.0.0  -y
  BurnIn Test           10.2.1004         choco install burnin              --version 10.2.1004   -y
  CrystalDiskInfo       8.17.13           choco install cdi                 --version 8.17.13     -y
  Git                   2.44.0            choco install git                 --version 2.44.0      -y
  SmiCli                2026.2.13         choco install smicli              --version 2026.2.13   -y
  SmiWinTools           2026.2.13.1       choco install smiwintools         --version 2026.2.13.1 -y
  PHM                   4.22.0            choco install phm                 --version 4.22.0      -y
  .NET 7 SDK            7.0.410           choco install net-7-sdk           --version 7.0.410     -y
  Playwright Browsers   1.58.0            choco install playwright-browsers --version 1.58.0      -y

  注意：必須加 --version（Nexus 3.77+ 不支援版本自動搜尋）

  一次安裝全部工具：
    choco install windows-adk --version 26100.0.0 burnin --version 10.2.1004 cdi --version 8.17.13 git --version 2.44.0 smicli --version 2026.2.13 smiwintools --version 2026.2.13.1 phm --version 4.22.0 net-7-sdk --version 7.0.410 playwright-browsers --version 1.58.0 -y

----------------------------------------------------------------
【查詢所有可用版本】

  choco search --source "https://nexus.internal/repository/choco-hosted/index.json" --all-versions

----------------------------------------------------------------
【移除 Chocolatey 及 Nexus 設定】

  以系統管理員開啟 PowerShell，依序執行：

  # 1. 移除 Chocolatey
  Remove-Item -Recurse -Force "C:\ProgramData\chocolatey"
  $p = [Environment]::GetEnvironmentVariable('Path','Machine')
  $p = ($p -split ';' | Where-Object { $_ -notlike '*chocolatey*' }) -join ';'
  [Environment]::SetEnvironmentVariable('Path', $p, 'Machine')

  # 2. 移除 hosts 裡的 nexus.internal
  $h = "$env:SystemRoot\System32\drivers\etc\hosts"
  (Get-Content $h) | Where-Object { $_ -notmatch 'nexus\.internal' } | Set-Content $h

  # 3. 移除 Nexus CA 憑證
  Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -match 'nexus' } | Remove-Item

================================================================

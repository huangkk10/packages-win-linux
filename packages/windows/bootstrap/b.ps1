# b.ps1 — Chocolatey 內網 Bootstrap
# 用法（以管理員 PowerShell 執行一行）：
#   Set-ExecutionPolicy Bypass -Scope Process -Force; iwr http://10.252.170.171/b -UseBasicParsing | iex
#
# 說明：此腳本本身經 HTTP 下載（不含機密）
#          內部再用 Add-Type 可靠跟過 SSL 驗證，適用 PS5/PS7

param(
    [string]$NexusIp   = "10.252.170.171",
    [string]$NexusHost = "nexus.internal",
    [string]$Repo      = "raw-windows-bootstrap"
)

$ErrorActionPreference = 'Stop'

# 強制 TLS 1.2（PS5 預設 TLS 1.0，nginx 只接受 TLS 1.2+）
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 略過 self-signed SSL 驗證（使用 Add-Type ，相容 PS5 / PS7）
if ($PSVersionTable.PSVersion.Major -ge 6) {
    $PSDefaultParameterValues['Invoke-WebRequest:SkipCertificateCheck'] = $true
    $PSDefaultParameterValues['Invoke-RestMethod:SkipCertificateCheck']  = $true
} else {
    if (-not ([System.Management.Automation.PSTypeName]'TrustAllCerts').Type) {
        Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCerts : ICertificatePolicy {
    public bool CheckValidationResult(ServicePoint sp, X509Certificate cert,
                                      WebRequest req, int problem) { return true; }
}
"@
    }
    [Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCerts
}

# [0/5] 自動寫入 hosts（若尚未存在）
$hostsFile  = "$env:SystemRoot\System32\drivers\etc\hosts"
$hostsEntry = "$NexusIp`t$NexusHost"
if (-not (Select-String -Path $hostsFile -Pattern ([regex]::Escape($NexusHost)) -Quiet)) {
    Write-Host "[0/5] 寫入 hosts：$hostsEntry"
    Add-Content $hostsFile "`n$hostsEntry"
} else {
    Write-Host "[0/5] hosts 已有 $NexusHost，略過"
}

$NexusUrl   = "https://$NexusIp"
$base       = "$NexusUrl/repository/$Repo"
$tmp        = "$env:TEMP\choco-bootstrap"
$nupkg      = "$tmp\chocolatey.nupkg"
$extractDir = "$tmp\choco-extracted"
$certFile   = "$tmp\nexus.crt"

New-Item -ItemType Directory -Force -Path $tmp | Out-Null

Write-Host "[1/5] 匯入 Nexus CA 憑證..."
# 憑證經 HTTP 下載（bootstrap 階段尚未信任 CA，需先用 HTTP）
Invoke-WebRequest "http://$NexusIp/nexus.crt" -OutFile $certFile -UseBasicParsing
Import-Certificate -FilePath $certFile -CertStoreLocation "Cert:\LocalMachine\Root" | Out-Null
Write-Host "[1/5] 憑證已匯入 Trusted Root CA"

# 注意：Import-Certificate 寫入 Windows 憑證庫，但目前程序的 .NET 不會立即重讀
# TrustAllCerts 維持生效直到此腳本結束；下次啟動的程序（choco）才會使用憑證庫

$chocoExe = "$env:SystemDrive\ProgramData\chocolatey\bin\choco.exe"
if (Test-Path $chocoExe) {
    Write-Host "[2/5] Chocolatey 已安裝，略過"
    Write-Host "[3/5] 略過"
} else {
    Write-Host "[2/5] 下載 chocolatey.nupkg ..."
    Invoke-WebRequest "$base/chocolatey.nupkg" -OutFile $nupkg -UseBasicParsing

    Write-Host "[3/5] 安裝 Chocolatey ..."
    $env:ChocolateyInstall = 'C:\ProgramData\chocolatey'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
    [System.IO.Compression.ZipFile]::ExtractToDirectory($nupkg, $extractDir)
    & "$extractDir\tools\chocolateyInstall.ps1"
}

# 重新載入 PATH
$env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
            [System.Environment]::GetEnvironmentVariable('Path', 'User')

Write-Host "[4/5] 登錄 Nexus 為 choco 來源 ..."
choco source add `
    --name="nexus" `
    --source="https://$NexusHost/repository/choco-hosted/index.json" `
    --priority=1 -y
choco source disable --name="chocolatey" 2>$null

Write-Host "[5/5] 完成！"
Write-Host ""
Write-Host "注意：安裝時必須指定 --version（Nexus 3.77+ 不支援 NuGet v2 OData 自動搜尋）"
Write-Host ""
Write-Host "安裝工具："
Write-Host "  choco install burnin            --version 10.2.1004   -y"
Write-Host "  choco install cdi               --version 8.17.13     -y"
Write-Host "  choco install git               --version 2.44.0      -y"
Write-Host "  choco install net-7-sdk         --version 7.0.410     -y"
Write-Host "  choco install phm               --version 4.22.0      -y"
Write-Host "  choco install playwright-browsers --version 1.58.0    -y"
Write-Host "  choco install smiwintools       --version 2026.2.13   -y"
Write-Host "  choco install smiwintools       --version 2026.2.13.1 -y"
Write-Host "  choco install windows-adk       --version 26100.0.0   -y"

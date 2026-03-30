# upload_nupkg.ps1
# 在 Windows 機器上直接執行，掃描本地 .nupkg 並上傳到 Nexus choco-hosted
#
# 使用方式：
#   .\upload_nupkg.ps1
#   .\upload_nupkg.ps1 -NexusUrl https://10.252.170.171 -PackagesDir "C:\ssd-testkit\bin\chocolatey\packages"

param(
    [string]$NexusUrl    = "https://10.252.170.171",
    [string]$NexusRepo   = "choco-hosted",
    [string]$NexusUser   = "admin",
    [string]$NexusPass   = "1.a",
    [string]$PackagesDir = "C:\ssd-testkit\bin\chocolatey\packages"
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

# 忽略 self-signed 憑證
if (-not ([System.Management.Automation.PSTypeName]"TrustAllCerts").Type) {
    Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCerts : ICertificatePolicy {
    public bool CheckValidationResult(ServicePoint sp, X509Certificate cert, WebRequest req, int problem) { return true; }
}
"@
}
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCerts
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

$UploadUrl = "$NexusUrl/service/rest/v1/components?repository=$NexusRepo"

Write-Host "============================================"
Write-Host " Nexus nupkg Uploader (Windows)"
Write-Host " Source : $PackagesDir"
Write-Host " Nexus  : $NexusUrl/repository/$NexusRepo/"
Write-Host "============================================"

# ── 確認來源目錄存在 ──────────────────────────────────────────────────────────
if (-not (Test-Path $PackagesDir)) {
    Write-Error "Packages directory not found: $PackagesDir"
    exit 1
}

# ── 找出所有 .nupkg ───────────────────────────────────────────────────────────
$nupkgs = Get-ChildItem -Path $PackagesDir -Recurse -Filter "*.nupkg"
if ($nupkgs.Count -eq 0) {
    Write-Host "[WARN] No .nupkg files found."
    exit 0
}

Write-Host "`n[INFO] Found $($nupkgs.Count) file(s):`n"
$nupkgs | ForEach-Object { Write-Host "  $($_.FullName)" }

# ── 批次上傳 ──────────────────────────────────────────────────────────────────
$success = 0
$failed  = 0
$cred    = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${NexusUser}:${NexusPass}"))
$headers = @{ Authorization = "Basic $cred" }

Write-Host "`n[Step] Uploading ...`n"

foreach ($pkg in $nupkgs) {
    Write-Host -NoNewline "  $($pkg.Name) ... "
    try {
        # Nexus REST API: multipart form upload
        $form = @{ "nuget.asset" = Get-Item $pkg.FullName }
        $resp = Invoke-RestMethod -Uri $UploadUrl `
            -Method Post `
            -Headers $headers `
            -Form $form `
            -SkipCertificateCheck
        Write-Host "OK"
        $success++
    } catch {
        $status = $null
        try { $status = $_.Exception.Response.StatusCode.Value__ } catch {}
        # 204 No Content = success
        if ($status -eq 204 -or ($null -eq $status -and $_.Exception.Message -notmatch "(?i)error|fail|denied|unauthorized")) {
            Write-Host "OK"
            $success++
        } else {
            Write-Host "FAILED$(if ($status) { " (HTTP $status)" })"
            Write-Host "    $($_.Exception.Message)"
            $failed++
        }
    }
}

Write-Host "`n============================================"
Write-Host " Upload complete: $success succeeded, $failed failed"
Write-Host "============================================"

if ($failed -gt 0) { exit 1 }

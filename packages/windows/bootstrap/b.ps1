# b.ps1 - Chocolatey Internal Network Bootstrap
# Usage (run as Administrator in PowerShell):
#   Set-ExecutionPolicy Bypass -Scope Process -Force; iwr http://10.252.170.171/b -UseBasicParsing | iex
#
# Note: This script is downloaded via HTTP. SSL bypass is handled internally via Add-Type. Compatible with PS5/PS7.

param(
    [string]$NexusIp   = "10.252.170.171",
    [string]$NexusHost = "nexus.internal",
    [string]$Repo      = "raw-windows-bootstrap"
)

$ErrorActionPreference = 'Stop'

# Force TLS 1.2 (PS5 defaults to TLS 1.0; nginx requires TLS 1.2+)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Skip self-signed SSL verification (Add-Type method, compatible with PS5/PS7)
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

# [0/5] Add hosts entry if not already present
$hostsFile  = "$env:SystemRoot\System32\drivers\etc\hosts"
$hostsEntry = "$NexusIp`t$NexusHost"
if (-not (Select-String -Path $hostsFile -Pattern ([regex]::Escape($NexusHost)) -Quiet)) {
    Write-Host "[0/5] Adding hosts entry: $hostsEntry"
    Add-Content $hostsFile "`n$hostsEntry"
} else {
    Write-Host "[0/5] hosts entry for $NexusHost already exists, skipping"
}

$NexusUrl   = "https://$NexusIp"
$base       = "$NexusUrl/repository/$Repo"
$tmp        = "$($(Get-Item $env:TEMP).FullName)\choco-bootstrap"
$nupkg      = "$tmp\chocolatey.nupkg"
$extractDir = "$tmp\choco-extracted"
$certFile   = "$tmp\nexus.crt"

New-Item -ItemType Directory -Force -Path $tmp | Out-Null

Write-Host "[1/5] Importing Nexus CA certificate..."
# Downloaded via HTTP because CA is not yet trusted at this stage
Invoke-WebRequest "http://$NexusIp/nexus.crt" -OutFile $certFile -UseBasicParsing
Import-Certificate -FilePath $certFile -CertStoreLocation "Cert:\LocalMachine\Root" | Out-Null
Write-Host "[1/5] Certificate imported to Trusted Root CA"

# Note: Import-Certificate writes to the Windows cert store, but the current .NET process
# won't reload it immediately. TrustAllCerts stays active until this script ends.

$chocoExe = "$env:SystemDrive\ProgramData\chocolatey\bin\choco.exe"
if (Test-Path $chocoExe) {
    Write-Host "[2/5] Chocolatey already installed, skipping"
    Write-Host "[3/5] Skipping"
} else {
    Write-Host "[2/5] Downloading chocolatey.nupkg ..."
    Invoke-WebRequest "$base/chocolatey.nupkg" -OutFile $nupkg -UseBasicParsing

    Write-Host "[3/5] Installing Chocolatey ..."
    $env:ChocolateyInstall = 'C:\ProgramData\chocolatey'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
    [System.IO.Compression.ZipFile]::ExtractToDirectory($nupkg, $extractDir)
    & "$extractDir\tools\chocolateyInstall.ps1"
}

# Reload PATH so choco is available in this session
$env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
            [System.Environment]::GetEnvironmentVariable('Path', 'User')

Write-Host "[4/5] Registering Nexus as choco source ..."
choco source add `
    --name="nexus" `
    --source="https://$NexusHost/repository/choco-hosted/index.json" `
    --priority=1 -y
choco source disable --name="chocolatey" 2>$null

Write-Host "[5/5] Done!"
Write-Host ""
Write-Host "NOTE: --version is required for all installs (Nexus 3.77+ dropped NuGet v2 OData auto-search)"
Write-Host ""
Write-Host "Install tools:"
Write-Host "  choco install burnin            --version 10.2.1004   -y"
Write-Host "  choco install cdi               --version 8.17.13     -y"
Write-Host "  choco install git               --version 2.44.0      -y"
Write-Host "  choco install net-7-sdk         --version 7.0.410     -y"
Write-Host "  choco install phm               --version 4.22.0      -y"
Write-Host "  choco install playwright-browsers --version 1.58.0    -y"
Write-Host "  choco install smiwintools       --version 2026.2.13   -y"
Write-Host "  choco install smiwintools       --version 2026.2.13.1 -y"
Write-Host "  choco install windows-adk       --version 26100.0.0   -y"

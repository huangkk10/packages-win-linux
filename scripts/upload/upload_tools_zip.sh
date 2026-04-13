#!/usr/bin/env bash
# =============================================================================
#  upload_tools_zip.sh
#  從 NAS 上傳 binary zip 到 Nexus raw-windows-tools repo
#
#  使用方式：
#    ./upload_tools_zip.sh
#    ./upload_tools_zip.sh --nexus-url https://10.252.170.171
#
#  NAS zip 路徑：
#    /mnt/nas-mdt/Team/PQ1-3/tool/ssd-testkit-source/windows/zip/
#
#  Nexus 路徑格式：
#    raw-windows-tools/<ToolName>/<version>/<file>.zip
# =============================================================================
set -uo pipefail

NEXUS_URL="${NEXUS_URL:-https://10.252.170.171}"
NEXUS_REPO="${NEXUS_REPO:-raw-windows-tools}"
NEXUS_USER="${NEXUS_USER:-admin}"
NEXUS_PASS="${NEXUS_PASS:-1.a}"
NAS_ZIP_DIR="${NAS_ZIP_DIR:-/mnt/nas-mdt/Team/PQ1-3/tool/ssd-testkit-source/windows/zip}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --nexus-url)  NEXUS_URL="$2";  shift 2 ;;
        --nexus-user) NEXUS_USER="$2"; shift 2 ;;
        --nexus-pass) NEXUS_PASS="$2"; shift 2 ;;
        --nas-dir)    NAS_ZIP_DIR="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# 對應表：NAS 檔名 → Nexus 路徑
# 格式：<nas_filename>:<nexus_path>
declare -a MAPPINGS=(
    "BurnIn-10.2.1004.zip:BurnIn/10.2.1004/BurnIn-10.2.1004.zip"
    "CrystalDiskInfo-8.17.13.zip:CrystalDiskInfo/8.17.13/CrystalDiskInfo-8.17.13.zip"
    "git-2.44.0.zip:git/2.44.0/git-2.44.0.zip"
    "net-7-sdk-7.0.410.zip:net_7_sdk/7.0.410/net-7-sdk-7.0.410.zip"
    "PHM-V4.22.0.zip:PHM/4.22.0/PHM-V4.22.0.zip"
    "playwright-browsers-1.58.0.zip:PlaywrightBrowsers/1.58.0/playwright-browsers-1.58.0.zip"
    "SmiWinTools-v20260213B.zip:SmiWinTools/v20260213B/SmiWinTools-v20260213B.zip"
    "SmiWinTools-v20260213C.zip:SmiWinTools/v20260213C/SmiWinTools-v20260213C.zip"
    "WindowsADK-26100.0.0.zip:WindowsADK/26100/WindowsADK-26100.0.0.zip"
)

echo "============================================"
echo " Nexus tools zip uploader"
echo " NAS dir : $NAS_ZIP_DIR"
echo " Nexus   : $NEXUS_URL/repository/$NEXUS_REPO/"
echo "============================================"

success=0
skipped=0
failed=0

for mapping in "${MAPPINGS[@]}"; do
    nas_file="${mapping%%:*}"
    nexus_path="${mapping##*:}"
    local_file="$NAS_ZIP_DIR/$nas_file"

    if [[ ! -f "$local_file" ]]; then
        echo "[SKIP] $nas_file — not found on NAS (需從 Windows 備份)"
        ((skipped++))
        continue
    fi

    size=$(du -sh "$local_file" | cut -f1)
    echo ""
    echo "[UPLOAD] $nas_file ($size) → $NEXUS_REPO/$nexus_path"

    http_code=$(curl -sk -u "${NEXUS_USER}:${NEXUS_PASS}" \
        -X PUT \
        "${NEXUS_URL}/repository/${NEXUS_REPO}/${nexus_path}" \
        --upload-file "$local_file" \
        -w "%{http_code}" -o /dev/null)

    if [[ "$http_code" == "201" || "$http_code" == "200" ]]; then
        echo "  HTTP:$http_code ✓"
        success=$((success + 1))
    else
        echo "  HTTP:$http_code ✗ FAILED"
        failed=$((failed + 1))
    fi
done

echo ""
echo "============================================"
echo " Done"
echo " Success : $success"
echo " Skipped : $skipped (zip 不在 NAS，需從 Windows 備份)"
echo " Failed  : $failed"
echo "============================================"

if [[ $failed -gt 0 ]]; then
    exit 1
fi

#!/usr/bin/env bash
# =============================================================================
#  upload_nupkg.sh
#  從遠端 Windows 專案目錄撈出所有 .nupkg，上傳到 Nexus choco-hosted
#
#  使用方式：
#    # 從遠端 Windows 機器上傳（預設）
#    ./upload_nupkg.sh
#
#    # 指定自訂參數
#    ./upload_nupkg.sh \
#      --nexus-url https://10.252.170.171 \
#      --nexus-user uploader \
#      --nexus-pass Uploader@2026 \
#      --win-host 10.8.113.3 \
#      --win-user administrator \
#      --win-pass 1.a \
#      --win-path "C:/ssd-testkit/bin/chocolatey/packages"
# =============================================================================
set -euo pipefail

# ── 預設值（與環境一致）──────────────────────────────────────────────────────
NEXUS_URL="${NEXUS_URL:-https://10.252.170.171}"
NEXUS_REPO="${NEXUS_REPO:-choco-hosted}"
NEXUS_USER="${NEXUS_USER:-admin}"
NEXUS_PASS="${NEXUS_PASS:-1.a}"

WIN_HOST="${WIN_HOST:-10.8.113.3}"
WIN_USER="${WIN_USER:-administrator}"
WIN_PASS="${WIN_PASS:-1.a}"
WIN_PATH="${WIN_PATH:-C:/ssd-testkit/bin/chocolatey/packages}"

WORK_DIR="/tmp/nupkg_upload_$$"

# ── 解析參數 ──────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --nexus-url)   NEXUS_URL="$2";   shift 2 ;;
        --nexus-user)  NEXUS_USER="$2";  shift 2 ;;
        --nexus-pass)  NEXUS_PASS="$2";  shift 2 ;;
        --nexus-repo)  NEXUS_REPO="$2";  shift 2 ;;
        --win-host)    WIN_HOST="$2";    shift 2 ;;
        --win-user)    WIN_USER="$2";    shift 2 ;;
        --win-pass)    WIN_PASS="$2";    shift 2 ;;
        --win-path)    WIN_PATH="$2";    shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ── 確認 sshpass 存在 ─────────────────────────────────────────────────────────
if ! command -v sshpass &>/dev/null; then
    echo "[INFO] Installing sshpass ..."
    sudo apt-get install -y sshpass
fi

SSH_CMD="sshpass -p ${WIN_PASS} ssh -o StrictHostKeyChecking=no ${WIN_USER}@${WIN_HOST}"
SCP_CMD="sshpass -p ${WIN_PASS} scp -o StrictHostKeyChecking=no"

echo "============================================"
echo " Nexus nupkg Uploader"
echo " Windows : ${WIN_USER}@${WIN_HOST}:${WIN_PATH}"
echo " Nexus   : ${NEXUS_URL}/repository/${NEXUS_REPO}/"
echo "============================================"

# ── Step 1: 列出遠端 .nupkg 清單 ─────────────────────────────────────────────
echo ""
echo "[Step 1] Listing .nupkg files on Windows ..."
NUPKG_LIST=$($SSH_CMD "cmd /c dir /s /b \"${WIN_PATH}\\*.nupkg\" 2>nul" 2>/dev/null || true)

if [[ -z "$NUPKG_LIST" ]]; then
    echo "[WARN]   No .nupkg files found in ${WIN_PATH}"
    exit 0
fi

echo "$NUPKG_LIST"
TOTAL=$(echo "$NUPKG_LIST" | wc -l)
echo "[INFO]   Found ${TOTAL} file(s)."

# ── Step 2: 建立暫存目錄，複製 .nupkg ────────────────────────────────────────
echo ""
echo "[Step 2] Copying .nupkg files to local temp dir ..."
mkdir -p "$WORK_DIR"

while IFS= read -r win_file; do
    [[ -z "$win_file" ]] && continue
    # 轉換 Windows 路徑格式 → scp 格式
    scp_path=$(echo "$win_file" | sed 's|\\|/|g' | sed 's|C:|/C|')
    filename=$(basename "$win_file")
    echo "  Copying ${filename} ..."
    $SCP_CMD "${WIN_USER}@${WIN_HOST}:${scp_path}" "${WORK_DIR}/${filename}" 2>/dev/null || \
        echo "  [WARN] Failed to copy ${filename}, skipping."
done <<< "$NUPKG_LIST"

# ── Step 3: 上傳所有 .nupkg 到 Nexus ─────────────────────────────────────────
echo ""
echo "[Step 3] Uploading to Nexus ${NEXUS_REPO} ..."
SUCCESS=0
FAILED=0

for nupkg in "$WORK_DIR"/*.nupkg; do
    [[ -f "$nupkg" ]] || continue
    filename=$(basename "$nupkg")
    echo -n "  Uploading ${filename} ... "
    status=$(curl -sk --max-time 60 \
        -u "${NEXUS_USER}:${NEXUS_PASS}" \
        -X POST "${NEXUS_URL}/service/rest/v1/components?repository=${NEXUS_REPO}" \
        -F "nuget.asset=@${nupkg};type=application/octet-stream" \
        -o /tmp/nexus_upload.json \
        -w "%{http_code}")

    if [[ "$status" == "204" ]]; then
        echo "OK"
        ((SUCCESS++))
    else
        echo "FAILED (HTTP ${status})"
        cat /tmp/nexus_upload.json 2>/dev/null
        ((FAILED++))
    fi
done

# ── Step 4: 清理暫存 ──────────────────────────────────────────────────────────
rm -rf "$WORK_DIR"

echo ""
echo "============================================"
echo " Upload complete: ${SUCCESS} succeeded, ${FAILED} failed"
echo "============================================"

[[ $FAILED -eq 0 ]]

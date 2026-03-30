#!/usr/bin/env bash
# =============================================================================
#  01_create_repos.sh
#  透過 Nexus REST API 建立所有必要的 repository
#
#  使用方式：
#    ./01_create_repos.sh -h https://nexus.internal -u admin -p <password>
#
#  建立項目：
#    - choco-hosted       NuGet hosted    (Chocolatey .nupkg)
#    - pypi-proxy         PyPI proxy      (代理 pypi.org)
#    - pypi-hosted        PyPI hosted     (內部自製套件，選用)
#    - pypi-group         PyPI group      (整合 proxy + hosted)
#    - raw-linux-tools    Raw hosted      (Linux binary 工具)
# =============================================================================
set -euo pipefail

# ── 預設值 ────────────────────────────────────────────────────────────────────
NEXUS_URL=""
ADMIN_USER="admin"
ADMIN_PASS=""

usage() {
    echo "Usage: $0 -h <nexus_url> -u <admin_user> -p <admin_password>"
    echo "  -h  Nexus base URL, e.g. https://nexus.internal"
    echo "  -u  Admin username (default: admin)"
    echo "  -p  Admin password"
    exit 1
}

while getopts "h:u:p:" opt; do
    case $opt in
        h) NEXUS_URL="$OPTARG" ;;
        u) ADMIN_USER="$OPTARG" ;;
        p) ADMIN_PASS="$OPTARG" ;;
        *) usage ;;
    esac
done

[[ -z "$NEXUS_URL" || -z "$ADMIN_PASS" ]] && usage

API="${NEXUS_URL}/service/rest/v1/repositories"
AUTH="${ADMIN_USER}:${ADMIN_PASS}"

# ── Helper ────────────────────────────────────────────────────────────────────
repo_exists() {
    local name="$1"
    local status
    status=$(curl -sk --connect-timeout 10 --max-time 15 \
        -o /dev/null -w "%{http_code}" \
        -u "$AUTH" "${NEXUS_URL}/service/rest/v1/repositories/${name}")
    [[ "$status" == "200" ]]
}

create_repo() {
    local name="$1"
    local endpoint="$2"
    local body="$3"

    if repo_exists "$name"; then
        echo "[SKIP] Repository '$name' already exists."
        return 0
    fi

    echo "[CREATE] Creating repository '$name' ..."
    local status
    status=$(curl -sk --connect-timeout 10 --max-time 30 \
        -o /tmp/nexus_response.json -w "%{http_code}" \
        -u "$AUTH" \
        -X POST "${API}/${endpoint}" \
        -H "Content-Type: application/json" \
        -d "$body")

    if [[ "$status" == "201" ]]; then
        echo "[OK]     '$name' created."
    else
        echo "[ERROR]  '$name' failed (HTTP $status):"
        cat /tmp/nexus_response.json
        exit 1
    fi
}

# ── 1. choco-hosted（NuGet hosted）────────────────────────────────────────────
create_repo "choco-hosted" "nuget/hosted" '{
  "name": "choco-hosted",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true,
    "writePolicy": "allow"
  }
}'

# ── 2. pypi-proxy（代理 pypi.org）─────────────────────────────────────────────
create_repo "pypi-proxy" "pypi/proxy" '{
  "name": "pypi-proxy",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true
  },
  "proxy": {
    "remoteUrl": "https://pypi.org",
    "contentMaxAge": 1440,
    "metadataMaxAge": 1440
  },
  "negativeCache": {
    "enabled": true,
    "timeToLive": 1440
  },
  "httpClient": {
    "blocked": false,
    "autoBlock": true
  }
}'

# ── 3. pypi-hosted（內部自製 Python 套件，選用）────────────────────────────────
create_repo "pypi-hosted" "pypi/hosted" '{
  "name": "pypi-hosted",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true,
    "writePolicy": "allow"
  }
}'

# ── 4. pypi-group（整合 proxy + hosted）───────────────────────────────────────
create_repo "pypi-group" "pypi/group" '{
  "name": "pypi-group",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true
  },
  "group": {
    "memberNames": ["pypi-hosted", "pypi-proxy"]
  }
}'

# ── 5. raw-linux-tools（Linux binary 工具）────────────────────────────────────
create_repo "raw-linux-tools" "raw/hosted" '{
  "name": "raw-linux-tools",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": false,
    "writePolicy": "allow"
  }
}'

echo ""
echo "============================================"
echo " All repositories created successfully."
echo "============================================"

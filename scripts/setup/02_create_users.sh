#!/usr/bin/env bash
# =============================================================================
#  02_create_users.sh
#  透過 Nexus REST API 建立 role 與 user
#
#  使用方式：
#    ./02_create_users.sh -h https://nexus.internal -p <admin_password> \
#                         --uploader-pass <pass> --developer-pass <pass>
#
#  建立項目：
#    Role  : nx-uploader   (可上傳套件)
#    Role  : nx-developer  (唯讀下載)
#    User  : uploader      (CI/CD 上傳用)
#    User  : developer     (開發者下載用，可共用或個人申請)
# =============================================================================
set -euo pipefail

# ── 預設值 ────────────────────────────────────────────────────────────────────
NEXUS_URL=""
ADMIN_USER="admin"
ADMIN_PASS=""
UPLOADER_PASS=""
DEVELOPER_PASS=""

usage() {
    echo "Usage: $0 -h <nexus_url> -p <admin_password>"
    echo "          --uploader-pass <pass> --developer-pass <pass>"
    echo "  -h  Nexus base URL, e.g. https://nexus.internal"
    echo "  -u  Admin username (default: admin)"
    echo "  -p  Admin password"
    echo "  --uploader-pass   Password for 'uploader' user"
    echo "  --developer-pass  Password for 'developer' user"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h) NEXUS_URL="$2"; shift 2 ;;
        -u) ADMIN_USER="$2"; shift 2 ;;
        -p) ADMIN_PASS="$2"; shift 2 ;;
        --uploader-pass)  UPLOADER_PASS="$2";  shift 2 ;;
        --developer-pass) DEVELOPER_PASS="$2"; shift 2 ;;
        *) usage ;;
    esac
done

[[ -z "$NEXUS_URL" || -z "$ADMIN_PASS" || -z "$UPLOADER_PASS" || -z "$DEVELOPER_PASS" ]] && usage

AUTH="${ADMIN_USER}:${ADMIN_PASS}"
ROLES_API="${NEXUS_URL}/service/rest/v1/security/roles"
USERS_API="${NEXUS_URL}/service/rest/v1/security/users"

# ── Helper ────────────────────────────────────────────────────────────────────
role_exists() {
    local id="$1"
    local status
    status=$(curl -sk -o /dev/null -w "%{http_code}" \
        -u "$AUTH" "${ROLES_API}/${id}")
    [[ "$status" == "200" ]]
}

user_exists() {
    local id="$1"
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" \
        -u "$AUTH" "${USERS_API}?userId=${id}")
    # Returns 200 with empty array if not found; check via response body
    local body
    body=$(curl -sk -u "$AUTH" "${USERS_API}?userId=${id}")
    [[ "$body" != "[]" ]]
}

create_role() {
    local id="$1"
    local body="$2"

    if role_exists "$id"; then
        echo "[SKIP] Role '$id' already exists."
        return 0
    fi

    echo "[CREATE] Creating role '$id' ..."
    local status
    status=$(curl -sk -o /tmp/nexus_response.json -w "%{http_code}" \
        -u "$AUTH" \
        -X POST "$ROLES_API" \
        -H "Content-Type: application/json" \
        -d "$body")

    if [[ "$status" == "200" ]]; then
        echo "[OK]     Role '$id' created."
    else
        echo "[ERROR]  Role '$id' failed (HTTP $status):"
        cat /tmp/nexus_response.json
        exit 1
    fi
}

create_user() {
    local id="$1"
    local body="$2"

    if user_exists "$id"; then
        echo "[SKIP] User '$id' already exists."
        return 0
    fi

    echo "[CREATE] Creating user '$id' ..."
    local status
    status=$(curl -sk -o /tmp/nexus_response.json -w "%{http_code}" \
        -u "$AUTH" \
        -X POST "$USERS_API" \
        -H "Content-Type: application/json" \
        -d "$body")

    if [[ "$status" == "200" ]]; then
        echo "[OK]     User '$id' created."
    else
        echo "[ERROR]  User '$id' failed (HTTP $status):"
        cat /tmp/nexus_response.json
        exit 1
    fi
}

# ── 1. Role: nx-developer（唯讀下載）─────────────────────────────────────────
create_role "nx-developer" '{
  "id": "nx-developer",
  "name": "nx-developer",
  "description": "Read-only access to all repositories",
  "privileges": [
    "nx-repository-view-nuget-choco-hosted-read",
    "nx-repository-view-nuget-choco-hosted-browse",
    "nx-repository-view-pypi-pypi-group-read",
    "nx-repository-view-pypi-pypi-group-browse",
    "nx-repository-view-raw-raw-linux-tools-read",
    "nx-repository-view-raw-raw-linux-tools-browse"
  ],
  "roles": []
}'

# ── 2. Role: nx-uploader（可上傳，CI/CD 用）──────────────────────────────────
create_role "nx-uploader" '{
  "id": "nx-uploader",
  "name": "nx-uploader",
  "description": "Upload access to all hosted repositories",
  "privileges": [
    "nx-repository-view-nuget-choco-hosted-*",
    "nx-repository-view-pypi-pypi-hosted-*",
    "nx-repository-view-raw-raw-linux-tools-*"
  ],
  "roles": ["nx-developer"]
}'

# ── 3. User: uploader（CI/CD 上傳用）─────────────────────────────────────────
create_user "uploader" "$(cat <<JSON
{
  "userId": "uploader",
  "firstName": "Uploader",
  "lastName": "Bot",
  "emailAddress": "uploader@nexus.internal",
  "password": "${UPLOADER_PASS}",
  "status": "active",
  "roles": ["nx-uploader"]
}
JSON
)"

# ── 4. User: developer（開發者共用帳號，也可改為個人帳號）──────────────────────
create_user "developer" "$(cat <<JSON
{
  "userId": "developer",
  "firstName": "Developer",
  "lastName": "User",
  "emailAddress": "developer@nexus.internal",
  "password": "${DEVELOPER_PASS}",
  "status": "active",
  "roles": ["nx-developer"]
}
JSON
)"

echo ""
echo "============================================"
echo " All roles and users created successfully."
echo "============================================"
echo ""
echo "Next steps:"
echo "  1. developer  → share credentials with all dev machines"
echo "  2. uploader   → store as CI/CD secret (NEXUS_API_KEY)"

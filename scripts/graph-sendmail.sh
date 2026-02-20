#!/bin/bash
# graph-sendmail.sh — Asterisk mailcmd replacement using Microsoft Graph API
#
# Reads a complete MIME email from STDIN (as Asterisk voicemail provides)
# and sends it via Microsoft Graph API using OAuth2 client credentials.
#
# Install:
#   1. Copy to /usr/local/bin/graph-sendmail.sh
#   2. chmod +x /usr/local/bin/graph-sendmail.sh
#   3. Create /etc/asterisk/graph-mail.conf with your Azure credentials
#   4. Set mailcmd in FreePBX: Settings > Voicemail Admin > Settings >
#      Email Config > Mail Command = /usr/local/bin/graph-sendmail.sh
#   5. Apply Config
#
# Azure AD setup:
#   - Register an app in Microsoft Entra (Azure AD)
#   - Add application permission: Microsoft Graph > Mail.Send
#   - Grant admin consent
#   - Create a client secret
#
# Config file: /etc/asterisk/graph-mail.conf
#   TENANT_ID="your-tenant-id"
#   CLIENT_ID="your-client-id"
#   CLIENT_SECRET="your-client-secret"
#   SENDER_EMAIL="pbx@yourcompany.com"
#
# Dependencies: curl, base64, python3 (for JSON parsing)

set -euo pipefail

CONFIG_FILE="/etc/asterisk/graph-mail.conf"
TOKEN_CACHE_DIR="/var/spool/asterisk/graph-mail"
TOKEN_FILE="${TOKEN_CACHE_DIR}/token"
TOKEN_EXPIRY_FILE="${TOKEN_CACHE_DIR}/token-expiry"
LOG_TAG="graph-sendmail"

log_info()  { logger -t "$LOG_TAG" "$1"; }
log_error() { logger -t "$LOG_TAG" -p mail.err "ERROR: $1"; }

# --- Load config ---
if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Config file not found: $CONFIG_FILE"
    exit 1
fi

source "$CONFIG_FILE"

for var in TENANT_ID CLIENT_ID CLIENT_SECRET SENDER_EMAIL; do
    if [ -z "${!var:-}" ]; then
        log_error "Missing required config variable: $var"
        exit 1
    fi
done

# --- Ensure cache directory exists ---
mkdir -p "$TOKEN_CACHE_DIR"
chown asterisk:asterisk "$TOKEN_CACHE_DIR" 2>/dev/null || true

# --- Read MIME email from STDIN ---
MIME_MESSAGE=$(cat)

if [ -z "$MIME_MESSAGE" ]; then
    log_error "No input received on STDIN"
    exit 1
fi

# --- Get OAuth2 access token (cached) ---
get_token() {
    local NOW
    NOW=$(date +%s)

    # Check cached token
    if [ -f "$TOKEN_FILE" ] && [ -f "$TOKEN_EXPIRY_FILE" ]; then
        local EXPIRY
        EXPIRY=$(cat "$TOKEN_EXPIRY_FILE" 2>/dev/null || echo 0)
        if [ "$NOW" -lt "$EXPIRY" ]; then
            cat "$TOKEN_FILE"
            return 0
        fi
    fi

    # Request new token
    local RESPONSE
    RESPONSE=$(curl -s --max-time 30 -X POST \
        "https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token" \
        -d "client_id=${CLIENT_ID}" \
        -d "scope=https%3A%2F%2Fgraph.microsoft.com%2F.default" \
        -d "client_secret=${CLIENT_SECRET}" \
        -d "grant_type=client_credentials" 2>&1)

    local ACCESS_TOKEN EXPIRES_IN
    ACCESS_TOKEN=$(echo "$RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if 'access_token' in data:
        print(data['access_token'])
    else:
        print('ERROR:' + data.get('error_description', data.get('error', 'unknown')), file=sys.stderr)
        sys.exit(1)
except Exception as e:
    print('ERROR:' + str(e), file=sys.stderr)
    sys.exit(1)
" 2>&1)

    if [[ "$ACCESS_TOKEN" == ERROR:* ]]; then
        log_error "OAuth2 token request failed: ${ACCESS_TOKEN#ERROR:}"
        return 1
    fi

    EXPIRES_IN=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('expires_in', 3599))")

    # Cache token (expire 60s early for safety)
    echo "$ACCESS_TOKEN" > "$TOKEN_FILE"
    echo $((NOW + EXPIRES_IN - 60)) > "$TOKEN_EXPIRY_FILE"
    chmod 600 "$TOKEN_FILE" "$TOKEN_EXPIRY_FILE"
    chown asterisk:asterisk "$TOKEN_FILE" "$TOKEN_EXPIRY_FILE" 2>/dev/null || true

    echo "$ACCESS_TOKEN"
}

ACCESS_TOKEN=$(get_token) || exit 1

# --- Base64-encode the MIME message and send via Graph API ---
MIME_B64=$(echo "$MIME_MESSAGE" | base64 -w 0)

HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" --max-time 30 -X POST \
    "https://graph.microsoft.com/v1.0/users/${SENDER_EMAIL}/sendMail" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: text/plain" \
    -d "$MIME_B64" 2>&1)

HTTP_BODY=$(echo "$HTTP_RESPONSE" | head -n -1)
HTTP_CODE=$(echo "$HTTP_RESPONSE" | tail -n 1)

if [ "$HTTP_CODE" = "202" ]; then
    log_info "Email sent successfully via Graph API (sender: $SENDER_EMAIL)"
    exit 0
fi

# --- Handle errors ---

# If 401, token may be stale — clear cache and retry once
if [ "$HTTP_CODE" = "401" ]; then
    log_info "Got 401, clearing token cache and retrying..."
    rm -f "$TOKEN_FILE" "$TOKEN_EXPIRY_FILE"
    ACCESS_TOKEN=$(get_token) || exit 1

    HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" --max-time 30 -X POST \
        "https://graph.microsoft.com/v1.0/users/${SENDER_EMAIL}/sendMail" \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: text/plain" \
        -d "$MIME_B64" 2>&1)

    HTTP_BODY=$(echo "$HTTP_RESPONSE" | head -n -1)
    HTTP_CODE=$(echo "$HTTP_RESPONSE" | tail -n 1)

    if [ "$HTTP_CODE" = "202" ]; then
        log_info "Email sent successfully on retry (sender: $SENDER_EMAIL)"
        exit 0
    fi
fi

# Extract error message from JSON response
ERROR_MSG=$(echo "$HTTP_BODY" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    err = data.get('error', {})
    print(f\"{err.get('code', 'unknown')}: {err.get('message', 'no details')}\")
except:
    print(sys.stdin.read() if hasattr(sys.stdin, 'read') else 'unparseable response')
" 2>/dev/null || echo "$HTTP_BODY")

log_error "Graph API returned HTTP $HTTP_CODE: $ERROR_MSG"
exit 1

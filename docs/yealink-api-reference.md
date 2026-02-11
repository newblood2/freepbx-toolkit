# Yealink T54W API Reference (Firmware v86+)

## Authentication

The newer Yealink firmware (v86+) uses a Vue.js web UI with a JSON REST API. The old `/servlet` path redirects to `/api`.

### Login

**Endpoint:** `POST /api/auth/login`
**Content-Type:** `application/x-www-form-urlencoded`
**Default credentials:** `admin` / `admin`

```bash
# Step 1: Load page to get session cookie
curl -sk -c /tmp/yealink_cookies.txt "https://$PHONE_IP/api" -o /dev/null

# Step 2: Login — IMPORTANT: password field is "pwd", NOT "password"
curl -sk -b /tmp/yealink_cookies.txt -c /tmp/yealink_cookies.txt \
  "https://$PHONE_IP/api/auth/login" -X POST \
  -d "username=admin&pwd=admin"
```

**Success:** `{"ret":"ok","data":true}`
**Wrong creds:** `{"ret":"failed","data":false,"error":{"msg":"error_username_or_password_is_wrong"}}`
**Locked out:** `{"ret":"failed","data":false,"error":{"webStatus":"lock","lockTime":"3"}}`

> **Lockout warning:** ~5 failed attempts triggers a 3-minute lockout. Each failed attempt during lockout resets the timer. Wait it out.

### Logout

```bash
curl -sk -b /tmp/yealink_cookies.txt "https://$PHONE_IP/api/auth/logout" -X POST
```

## Configuration

### Write Config

```bash
curl -sk -b /tmp/yealink_cookies.txt \
  "https://$PHONE_IP/api/inner/writeconfig" -X POST \
  -H "Content-Type: application/json" \
  -d '{"setConfig":{"key.name":"value","another.key":"value"}}'
```

Response: `{"ret":"ok","data":"change"}` or `{"ret":"ok","data":"nochange"}`

### Read Config

```bash
curl -sk -b /tmp/yealink_cookies.txt \
  "https://$PHONE_IP/api/inner/readconfig" -X POST \
  -H "Content-Type: application/json" \
  -d '{"keys":["key.name","another.key"]}'
```

> Note: `readconfig` returns `"error_invalid_cfg_info"` for keys it doesn't recognize. Use `readconfigalllevel` for provisioning-related keys (only works when autoprovision is enabled).

## Provisioning

### Set Provisioning URL

```bash
curl -sk -b /tmp/yealink_cookies.txt \
  "https://$PHONE_IP/api/inner/writeconfig" -X POST \
  -H "Content-Type: application/json" \
  -d '{"setConfig":{"auto_provision.mode":"6","auto_provision.server_url":"http://SERVER_IP/prov","auto_provision.pnp_enable":"0","security.trust_certificates":"0"}}'
```

- `auto_provision.mode=6` — HTTP provisioning
- `auto_provision.mode=0` — Disabled
- `security.trust_certificates=0` — Required for HTTP/self-signed

### Trigger Provisioning Now

```bash
curl -sk -b /tmp/yealink_cookies.txt \
  "https://$PHONE_IP/api/autop/now" -X POST \
  -H "Content-Type: application/json" -d '{}'
```

### Check Provisioning Status

```bash
curl -sk -b /tmp/yealink_cookies.txt "https://$PHONE_IP/api/autop/status"
```

Response: `{"ret":"ok","data":"idle"}` or `{"ret":"ok","data":"provisioning"}`

## System

### Reboot

```bash
curl -sk -b /tmp/yealink_cookies.txt \
  "https://$PHONE_IP/api/system/reboot" -X POST \
  -H "Content-Type: application/json" -d '{}'
```

### Factory Reset

```bash
curl -sk -b /tmp/yealink_cookies.txt \
  "https://$PHONE_IP/api/system/resetsettings" -X POST \
  -H "Content-Type: application/json" -d '{}'
```

### Phone Info

```bash
curl -sk -b /tmp/yealink_cookies.txt "https://$PHONE_IP/api/common/info"
```

### Account Info

```bash
curl -sk -b /tmp/yealink_cookies.txt "https://$PHONE_IP/api/account/info"
```

## All Known Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/auth/login` | POST | Login (form: `username` + `pwd`) |
| `/api/auth/logout` | POST | Logout |
| `/api/auth/user` | GET | Current user info |
| `/api/inner/writeconfig` | POST | Write config (JSON `setConfig`) |
| `/api/inner/readconfig` | POST | Read config (JSON `keys` array) |
| `/api/inner/readconfigalllevel` | POST | Read config with all levels |
| `/api/inner/resetconfig` | POST | Reset config keys |
| `/api/autop/now` | POST | Trigger provisioning |
| `/api/autop/status` | GET | Provisioning status |
| `/api/system/reboot` | POST | Reboot phone |
| `/api/system/resetsettings` | POST | Factory reset |
| `/api/common/info` | GET | Phone model/firmware/status |
| `/api/account/info` | GET | SIP account configuration |
| `/api/account/list` | GET | List all accounts |
| `/api/account/status` | GET | Account registration status |
| `/api/dsskey/info` | GET | Line key configuration |
| `/api/contacts/localcontacts` | GET | Local phonebook |
| `/api/contacts/calllog` | GET | Call history |
| `/api/diagnosis/start` | POST | Start packet capture |
| `/api/diagnosis/stop` | POST | Stop packet capture |
| `/api/diagnosis/log` | GET | System log |
| `/api/time/localtime` | GET | Time settings |
| `/api/network/wifi` | GET | WiFi settings |
| `/api/upgrade/upgrade` | POST | Firmware upgrade |

## Legacy API (pre-v86 firmware)

Older firmware uses `/servlet` endpoints with Basic Auth or form login:

```bash
# Login
curl -sk -c cookies.txt "$PROTO://$PHONE_IP/servlet?m=mod_data&p=login" \
  -d "username=admin&pwd=admin"

# Set provisioning
curl -sk -b cookies.txt "$PROTO://$PHONE_IP/servlet?m=mod_data&p=config-autop" \
  -d "autop_mode=6&autop_url=http://SERVER_IP/prov"

# Reboot
curl -sk -b cookies.txt "$PROTO://$PHONE_IP/servlet?m=mod_data&p=reboot" \
  -d "reboot=1"
```

Some models also support Basic Auth via `/cgi-bin/ConfigManApp.com`:
```bash
curl -sk --user admin:admin "https://$PHONE_IP/cgi-bin/ConfigManApp.com?key=DNDOn" -X POST -d ""
```

## Detecting Firmware Version

Any failed login attempt returns the firmware version in the error response:
```json
{
  "error": {
    "phoneName": "T54W",
    "firmware": "96.86.0.75"
  }
}
```

If firmware version starts with `96.86` or higher → use the new `/api/` endpoints.

## Finding Phone Local IPs from FreePBX

If you know the extension but not the phone's LAN IP:
```bash
ssh root@SERVER_IP "asterisk -rx 'pjsip show aor EXTENSION'"
```

Look for `x-ast-orig-host=192.168.x.x` in the contact field.

---
name: provision-phone
description: Provision a Yealink phone to register with a FreePBX server
disable-model-invocation: true
allowed-tools: Bash, Read, Grep
argument-hint: [server-ip] [phone-ip]
---

# Provision Phone - Configure Yealink for FreePBX

**Required arguments from `$ARGUMENTS`:**
- First word = FreePBX server IP/hostname
- Second word = Phone's local IP address

Parse both from `$ARGUMENTS`.

If the phone's local IP is not provided, try to find it from the server by checking PJSIP AOR details:
```bash
ssh root@$SERVER_IP "asterisk -rx 'pjsip show aors'" 2>/dev/null
```
Look for `x-ast-orig-host=<local-ip>` in the contact URIs.

## Steps

### 1. Test connectivity to phone
Try HTTPS first (most Yealink T5x phones use HTTPS):
```bash
curl -sk --max-time 5 -o /dev/null -w "%{http_code}" "https://$PHONE_IP/api"
```

If that fails, try HTTP:
```bash
curl -sk --max-time 5 -o /dev/null -w "%{http_code}" "http://$PHONE_IP/api"
```

Use whichever protocol responds (200 or 302).

### 2. Login to phone web API

**New firmware (v86+, Vue.js UI)** — uses `/api/auth/login` with form-encoded data.
IMPORTANT: The password field name is `pwd`, NOT `password`.

```bash
rm -f /tmp/yealink_cookies.txt
# First load the page to get a session cookie
curl -sk --max-time 5 -c /tmp/yealink_cookies.txt "$PROTO://$PHONE_IP/api" -o /dev/null
# Then login — field names are username and pwd
curl -sk --max-time 5 -b /tmp/yealink_cookies.txt -c /tmp/yealink_cookies.txt \
  "$PROTO://$PHONE_IP/api/auth/login" -X POST \
  -d "username=admin&pwd=admin"
```

Expected success response: `{"ret":"ok","data":true}`
Expected failure: `{"ret":"failed","data":false,"error":{"msg":"error_username_or_password_is_wrong"}}`
Lockout response: `{"ret":"failed","data":false,"error":{"webStatus":"lock","lockTime":"3"}}`

If locked out, wait the specified lockTime (minutes) before retrying. DO NOT retry — each failed attempt resets the timer.

**Old firmware (pre-v86, servlet UI)** — if `/api` returns 404, try the legacy servlet:
```bash
curl -sk --max-time 10 -c /tmp/yealink_cookies.txt \
  "$PROTO://$PHONE_IP/servlet?m=mod_data&p=login" \
  -d "username=admin&pwd=admin"
```

### 3. Set provisioning server URL

**New firmware (v86+)** — use the writeconfig API:
```bash
curl -sk --max-time 5 -b /tmp/yealink_cookies.txt \
  "$PROTO://$PHONE_IP/api/inner/writeconfig" -X POST \
  -H "Content-Type: application/json" \
  -d '{"setConfig":{"auto_provision.mode":"6","auto_provision.server_url":"http://'$SERVER_IP'/prov","auto_provision.pnp_enable":"0","security.trust_certificates":"0"}}'
```

Expected response: `{"ret":"ok","data":"change"}`

Parameters explained:
- `auto_provision.mode=6` = HTTP provisioning
- `auto_provision.server_url` = provisioning URL pointing to FreePBX server
- `auto_provision.pnp_enable=0` = disable PnP (not needed with explicit URL)
- `security.trust_certificates=0` = disable cert checking (needed for HTTP provisioning)

**Old firmware** — use the servlet:
```bash
curl -sk --max-time 10 -b /tmp/yealink_cookies.txt \
  "$PROTO://$PHONE_IP/servlet?m=mod_data&p=config-autop" \
  -d "autop_mode=6&autop_url=http://$SERVER_IP/prov"
```

### 4. Reboot the phone

**New firmware (v86+):**
```bash
curl -sk --max-time 5 -b /tmp/yealink_cookies.txt \
  "$PROTO://$PHONE_IP/api/system/reboot" -X POST \
  -H "Content-Type: application/json" -d '{}'
```

**Old firmware:**
```bash
curl -sk --max-time 10 -b /tmp/yealink_cookies.txt \
  "$PROTO://$PHONE_IP/servlet?m=mod_data&p=reboot" -d "reboot=1"
```

### 5. Wait for phone to reboot and re-register
Wait 75 seconds for the phone to reboot, download its provisioning config, and register:
```bash
sleep 75
```

### 6. Verify registration on server
```bash
ssh root@$SERVER_IP "asterisk -rx 'pjsip show contacts'" 2>/dev/null
```

Look for the phone's extension showing `Avail`. If it shows `Unavail`, wait another 15 seconds and check again — the qualify cycle may not have completed.

### 7. Cleanup
```bash
rm -f /tmp/yealink_cookies.txt
```

## Yealink API Reference (v86+ firmware)

### Key Endpoints
| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/auth/login` | POST | Login (fields: `username`, `pwd`) |
| `/api/auth/logout` | POST | Logout |
| `/api/inner/writeconfig` | POST | Write config params (JSON body with `setConfig`) |
| `/api/inner/readconfig` | POST | Read config params (JSON body with `keys` array) |
| `/api/autop/now` | POST | Trigger provisioning now |
| `/api/autop/status` | GET | Check provisioning status |
| `/api/system/reboot` | POST | Reboot phone |
| `/api/system/resetsettings` | POST | Factory reset |
| `/api/account/info` | GET | SIP account info |
| `/api/common/info` | GET | Phone model/firmware info |

### Detecting Firmware Version
The login failure response includes firmware version:
```json
{"error":{"phoneName":"T54W","firmware":"96.86.0.75"}}
```

## Output
- Report each step's success/failure
- After reboot, show if the phone registered successfully
- If registration not seen, suggest:
  - Check that a provisioning config exists for this phone's MAC at `http://<server>/prov/<mac>.cfg`
  - Verify the MAC-to-extension mapping in the config file
  - Check server-side: `ls /var/www/html/prov/` for the phone's MAC

## Common Issues
- **Phone unreachable**: Ensure you're on the same network/VLAN as the phone
- **Login fails**: Phone may have non-default credentials; check with user
- **Login lockout**: Wait the lockTime (usually 3 min). Do NOT retry during lockout — it resets the timer
- **Provisioning works but no registration**: Check MAC config exists in `/var/www/html/prov/`
- **Phone loops rebooting**: Provisioning template may have errors; check `/var/log/asterisk/full`
- **Factory reset needed**: Long-press OK button for 10 seconds during boot

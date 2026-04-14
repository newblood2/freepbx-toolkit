# Yealink Phone Reference

Comprehensive reference for provisioning, configuring, and managing Yealink T-series phones (tested extensively on T54W firmware v86+). Covers the REST API, provisioning flow, config file format, line keys, BLF, parking, NAT settings, and firmware-version gotchas.

---

## Table of Contents

1. [Overview](#overview)
2. [REST API (Firmware v86+)](#rest-api-firmware-v86)
3. [Legacy API (pre-v86)](#legacy-api-pre-v86)
4. [Provisioning Flow](#provisioning-flow)
5. [Config File Format](#config-file-format)
6. [Line Keys & BLF](#line-keys--blf)
7. [Parking Lot Keys](#parking-lot-keys)
8. [Firewall Requirements](#firewall-requirements)
9. [NAT Configuration](#nat-configuration)
10. [Finding Phone IPs from the Server](#finding-phone-ips-from-the-server)
11. [Firmware Detection](#firmware-detection)
12. [Troubleshooting](#troubleshooting)

---

## Overview

### Tested Models

- **T54W** — primary test target, verified v86+ firmware
- **T53, T53W** — same API, tested working
- **T46, T46U, T42, T48S** — assumed same API based on Yealink docs (not personally verified)

### Architecture

Yealink phones auto-provision from an HTTP(S) server hosting `.cfg` files named by MAC address. The phone pulls its config on boot or when manually triggered. Changes to the web UI, line keys, accounts, and most settings can be pushed via:

1. **Config file** (persistent, reapplied on reboot) — place at `/var/www/html/prov/<MAC>.cfg`
2. **REST API** (immediate, may not persist through reprovision) — POST to `/api/inner/writeconfig`

---

## REST API (Firmware v86+)

Newer firmware uses a Vue.js web UI with a JSON REST API. The old `/servlet` path redirects to `/api`.

### Authentication

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

> **Lockout warning:** ~5 failed attempts triggers a 3-minute lockout. Each additional failed attempt **resets the timer**. Wait it out.

### Logout

```bash
curl -sk -b /tmp/yealink_cookies.txt "https://$PHONE_IP/api/auth/logout" -X POST
```

### Change Web Admin Password

**Endpoint:** `POST /api/auth/user`
**Content-Type:** `application/json`

```bash
curl -sk -b /tmp/yealink_cookies.txt \
  "https://$PHONE_IP/api/auth/user" -X POST \
  -H "Content-Type: application/json" \
  -d '{"id":"admin","oldPwd":"admin","newPwd":"NEW_PASSWORD","confirmPwd":"NEW_PASSWORD"}'
```

**Success:** `{"ret":"ok","data":true}`
**Wrong old password:** `{"ret":"failed","data":false,"error":{"msg":"error_incorrect_old_password"}}`

> **Important:** `writeconfig` with `security.user_password.admin` does NOT change the password. Provisioning config files with `security.user_password.admin` also do NOT apply the password change. The dedicated `/api/auth/user` endpoint is the only method that works.

### Write Config

```bash
curl -sk -b /tmp/yealink_cookies.txt \
  "https://$PHONE_IP/api/inner/writeconfig" -X POST \
  -H "Content-Type: application/json" \
  -d '{"setConfig":{"key.name":"value","another.key":"value"}}'
```

**Response:** `{"ret":"ok","data":"change"}` or `{"ret":"ok","data":"nochange"}`

### Read Config

```bash
curl -sk -b /tmp/yealink_cookies.txt \
  "https://$PHONE_IP/api/inner/readconfig" -X POST \
  -H "Content-Type: application/json" \
  -d '{"keys":["key.name","another.key"]}'
```

> `readconfig` returns `"error_invalid_cfg_info"` for keys it doesn't recognize. Use `readconfigalllevel` for provisioning-related keys (only works when autoprovision is enabled).

### Set Provisioning URL

```bash
curl -sk -b /tmp/yealink_cookies.txt \
  "https://$PHONE_IP/api/inner/writeconfig" -X POST \
  -H "Content-Type: application/json" \
  -d '{"setConfig":{
    "auto_provision.mode":"6",
    "auto_provision.server_url":"http://<PBX_IP>/prov",
    "auto_provision.pnp_enable":"0",
    "security.trust_certificates":"0"
  }}'
```

| Key | Value | Meaning |
|-----|-------|---------|
| `auto_provision.mode` | `6` | HTTP provisioning |
| `auto_provision.mode` | `0` | Disabled |
| `security.trust_certificates` | `0` | Required for HTTP / self-signed |

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

### System Commands

```bash
# Reboot
curl -sk -b /tmp/yealink_cookies.txt \
  "https://$PHONE_IP/api/system/reboot" -X POST \
  -H "Content-Type: application/json" -d '{}'

# Factory reset
curl -sk -b /tmp/yealink_cookies.txt \
  "https://$PHONE_IP/api/system/resetsettings" -X POST \
  -H "Content-Type: application/json" -d '{}'

# Phone info (model, firmware, status)
curl -sk -b /tmp/yealink_cookies.txt "https://$PHONE_IP/api/common/info"

# Account info (SIP registration)
curl -sk -b /tmp/yealink_cookies.txt "https://$PHONE_IP/api/account/info"
```

### All Known Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/auth/login` | POST | Login (form: `username` + `pwd`) |
| `/api/auth/logout` | POST | Logout |
| `/api/auth/user` | GET | List users (admin, user) |
| `/api/auth/user` | POST | Change password |
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

---

## Legacy API (pre-v86)

Older firmware uses `/servlet` endpoints with Basic Auth or form login:

```bash
# Login
curl -sk -c cookies.txt "$PROTO://$PHONE_IP/servlet?m=mod_data&p=login" \
  -d "username=admin&pwd=admin"

# Set provisioning
curl -sk -b cookies.txt "$PROTO://$PHONE_IP/servlet?m=mod_data&p=config-autop" \
  -d "autop_mode=6&autop_url=http://<PBX_IP>/prov"

# Reboot
curl -sk -b cookies.txt "$PROTO://$PHONE_IP/servlet?m=mod_data&p=reboot" \
  -d "reboot=1"
```

Some models also support Basic Auth via `/cgi-bin/ConfigManApp.com`:

```bash
curl -sk --user admin:admin "https://$PHONE_IP/cgi-bin/ConfigManApp.com?key=DNDOn" -X POST -d ""
```

---

## Provisioning Flow

```
1. New phone connected to network
         ↓
2. Phone API: set provisioning URL + reboot
   (or factory reset; phones ship with default admin/admin)
         ↓
3. Phone boots, requests config:
   GET http://<PBX>/prov/<MAC>.cfg
         ↓
4. PBX returns phone-specific config:
   - SIP account credentials
   - Line keys (own line, BLFs, parking, speed dials)
   - Network/NAT settings
         ↓
5. Phone registers with FreePBX
   Asterisk: "pjsip show contacts" now shows this extension
```

### Provisioning Server Setup on FreePBX

```bash
mkdir -p /var/www/html/prov
chown asterisk:asterisk /var/www/html/prov
chmod 755 /var/www/html/prov
```

Config files use lowercase MAC with no separators:

- Phone MAC: `80:5E:0C:AA:BB:CC`
- Config filename: `805e0caabbcc.cfg`

### Auto-Provisioning URL

```
http://<PBX_IP>/prov/
```

For HTTP (not HTTPS) auto-provision, the phone must have `security.trust_certificates=0`.

---

## Config File Format

Yealink uses `.cfg` text files with INI-style `key = value` syntax.

### Filename Convention

- `{MAC}.cfg` — per-phone config (e.g., `001565abcdef.cfg`)
- `y000000000096.cfg` — model-specific defaults (T54W)
- `common.cfg` — global settings for all phones

### Basic T54W Config Template

```ini
#!version:1.0.0.1

## Account 1 (Primary Line)
account.1.enable = 1
account.1.label = {DISPLAY_NAME}
account.1.display_name = {DISPLAY_NAME}
account.1.user_name = {EXTENSION}
account.1.auth_name = {EXTENSION}
account.1.password = {SIP_SECRET}
account.1.sip_server.1.address = {PBX_HOST}
account.1.sip_server.1.port = 5060
account.1.sip_server.1.transport_type = 0
account.1.outbound_proxy_enable = 0

## Codecs
account.1.codec.1.enable = 1
account.1.codec.1.payload_type = PCMU
account.1.codec.2.enable = 1
account.1.codec.2.payload_type = PCMA
account.1.codec.3.enable = 1
account.1.codec.3.payload_type = G722

## DTMF
account.1.dtmf.type = 1
account.1.dtmf.dtmf_payload = 101

## NAT
account.1.nat.nat_traversal = 0
account.1.nat.rport = 1

## Voicemail
voice_mail.number.1 = *97

## Display
lcd.contrast = 6
lcd.backlight_level.active = 7
lcd.backlight_time = 60

## Time
local_time.ntp_server1 = pool.ntp.org
local_time.time_zone = -5
local_time.time_zone_name = Eastern
local_time.summer_time = 2

## Language
lang.gui = English

## Audio
voice.ring_type.headset = 1
voice.ring_type.ring1 = Ring1.wav
```

### `static.` Prefix

Config keys prefixed with `static.` are applied **only on factory reset or initial provisioning**. For keys that should update every time the phone provisions, omit `static.`.

Example:

- `static.network.wifi.ip_address_mode = 0` — persists through factory reset, applied once
- `auto_provision.mode = 6` — applied every provisioning cycle

---

## Line Keys & BLF

### Line Key Types

| Type | Function |
|------|----------|
| 0 | N/A (disabled) |
| 13 | Speed Dial |
| 15 | Line |
| 16 | BLF (Busy Lamp Field) |
| 17 | Call Park |
| 22 | Intercom |
| 23 | DTMF |

### Examples

```ini
## Line Key 1 - Own Line
linekey.1.type = 15
linekey.1.line = 1
linekey.1.value = 201
linekey.1.label = Main Line

## Line Key 2 - BLF for Extension 202
linekey.2.type = 16
linekey.2.line = 1
linekey.2.value = 202
linekey.2.label = Reception
linekey.2.extension = 202

## Line Key 3 - Speed Dial
linekey.3.type = 13
linekey.3.line = 1
linekey.3.value = 911
linekey.3.label = Emergency

## Line Key 4 - Intercom
linekey.4.type = 22
linekey.4.line = 1
linekey.4.value = 203
linekey.4.label = Intercom 203
```

---

## Parking Lot Keys

Requires Parking module configured on FreePBX (see [freepbx-reference.md](freepbx-reference.md#parking-lots)).

```ini
## Park (transfer call to lot)
linekey.11.type = 17
linekey.11.value = 700
linekey.11.label = Park

## Park Orbit BLF (monitor slot 701)
linekey.12.type = 16
linekey.12.line = 1
linekey.12.value = 701
linekey.12.label = Slot 1

## Park Orbit BLF (monitor slot 702)
linekey.13.type = 16
linekey.13.line = 1
linekey.13.value = 702
linekey.13.label = Slot 2
```

---

## Firewall Requirements

For phones to provision and register, the following must be allowed:

### Cloud Firewall (Linode, AWS, etc.)

Open these ports from the phone network's WAN IP:

- **Port 80 TCP** — config file downloads (HTTP)
- **Port 5060 UDP** — SIP registration
- **Port 10000-20000 UDP** — RTP media

### FreePBX Responsive Firewall

Add the phone network WAN IP to the trusted zone:

```bash
fwconsole firewall trust <WAN_IP>
fwconsole firewall restart
fwconsole firewall list trusted
```

### Troubleshooting Firewall Issues

- If phones **fetch configs but don't register** → port 5060 UDP not open
- If phones **don't fetch configs at all** → port 80 not open OR WAN IP not trusted
- Check Apache logs: `tail -f /var/log/apache2/access.log`

---

## NAT Configuration

If phones are behind NAT (remote office, home users), you MUST disable `direct_media` on their extensions on the FreePBX side. See [freepbx-reference.md](freepbx-reference.md#firewall--nat) for details.

### Phone-Side NAT Settings

```ini
## NAT settings in the phone config
account.1.nat.nat_traversal = 0
account.1.nat.rport = 1
static.sip.rport = 1
```

Generally the PBX-side NAT fixes (direct_media=no, rewrite_contact=yes, rtp_symmetric=yes, force_rport=yes) are more important than phone-side settings.

---

## Finding Phone IPs from the Server

If you know the extension but not the phone's LAN IP:

```bash
ssh root@<PBX_IP> "asterisk -rx 'pjsip show aor <EXT>'"
```

Look for `x-ast-orig-host=192.168.x.x` in the contact field.

Example output:

```
Contact:  204/sip:204@50.144.174.18:1922;x-ast-orig-host=192.168.1.79:5060 4e657c7c5c Avail
```

The phone's local IP is `192.168.1.79`.

---

## Firmware Detection

Any failed login attempt returns the firmware version in the error response:

```json
{
  "error": {
    "phoneName": "T54W",
    "firmware": "96.86.0.75"
  }
}
```

**Rule of thumb:**

- Firmware starting with `96.86` or higher → new `/api/` endpoints
- Firmware before `v86` → legacy `/servlet` endpoints

Or use the `/api/common/info` endpoint if you're already authenticated:

```bash
curl -sk -b cookies "https://$PHONE_IP/api/common/info"
```

---

## Troubleshooting

### Phone Shows Warning Triangle

Usually means **admin password is still default** (`admin/admin`). Change it via the `/api/auth/user` POST endpoint. See [Change Web Admin Password](#change-web-admin-password).

Other causes:

- Account unregistered (check SIP credentials, server reachability)
- Anonymous Call feature enabled (disable in phone menu)
- Network/Ethernet issue

### Phone Logs Out Instantly

The phone's session cookies tie to the specific IP. If you switch between HTTP/HTTPS or change source IPs during a session, expect to re-login.

### Wrong Old Password Error on Password Change

The phone tracks the **current** password, not the one you think it is. If you've changed it via the UI since the last API change, use the current password as `oldPwd`.

### Phone Doesn't Pull Config on Reboot

- Check `auto_provision.mode` is `6` (HTTP) — not `0`
- Check `auto_provision.server_url` is correct
- Verify the config file exists at `/var/www/html/prov/<mac>.cfg`
- Verify firewall allows port 80 from phone's WAN IP
- Check Apache access log for GET request from phone
- Try triggering manually: `POST /api/autop/now`

### `static.` Prefix Confusion

Config keys with `static.` prefix only apply on factory reset / first provisioning. If you change a `static.` key in an already-provisioned phone's config, nothing will happen. Either:

1. Use the non-`static.` version of the key (if it exists)
2. Factory reset the phone
3. Push the change directly via `/api/inner/writeconfig`

### `writeconfig` Returns "change" But Nothing Actually Changed

The API accepts and acknowledges config keys that it doesn't actually apply. Notable cases:

- `security.user_password.admin` — use `/api/auth/user` instead
- Some `static.` keys when autoprovision is disabled

Test with `/api/inner/readconfig` or by observing actual phone behavior.

### Large JSON Payload Fails on `writeconfig`

Phones can reject very large single calls. Break into multiple `writeconfig` calls.

---

## Related Documentation

- [freepbx-reference.md](freepbx-reference.md) — FreePBX side (server config, NAT, firewall trust)
- [../scripts/graph-sendmail.sh](../scripts/graph-sendmail.sh) — Voicemail-to-email via Microsoft Graph API
- [../skills/provision-phone/SKILL.md](../skills/provision-phone/SKILL.md) — Claude Code skill for provisioning a phone

## External References

- [Yealink Support](https://support.yealink.com/) — admin guides and firmware downloads
- Search "Yealink T54W admin guide PDF" for the full config key reference

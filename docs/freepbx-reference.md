# FreePBX 17 Reference

Comprehensive reference for administering and automating FreePBX 17 (Asterisk 17+) systems. Combines GraphQL API knowledge, direct SQL operations, `fwconsole` CLI usage, and production troubleshooting notes.

---

## Table of Contents

1. [System Overview](#system-overview)
2. [GraphQL API](#graphql-api)
3. [Database Schema & Direct SQL](#database-schema--direct-sql)
4. [Extensions](#extensions)
5. [SIP Trunks](#sip-trunks)
6. [Outbound Routes](#outbound-routes)
7. [Inbound Routes](#inbound-routes)
8. [Ring Groups](#ring-groups)
9. [Time Conditions](#time-conditions)
10. [IVR & System Recordings](#ivr--system-recordings)
11. [Voicemail & Email-to-Voicemail](#voicemail--email-to-voicemail)
12. [Parking Lots](#parking-lots)
13. [Firewall & NAT](#firewall--nat)
14. [fwconsole Reference](#fwconsole-reference)
15. [Troubleshooting](#troubleshooting)
16. [Gotchas & Lessons Learned](#gotchas--lessons-learned)

---

## System Overview

### Default Ports

| Port | Purpose |
|------|---------|
| 80 | HTTP web UI |
| 83 | Admin/GraphQL API port (may be HTTP only from localhost) |
| 443 | HTTPS web UI |
| 5060 UDP | SIP signaling |
| 5061 TCP/TLS | SIP over TLS |
| 10000-20000 UDP | RTP media |
| 8089 WSS | WebRTC |

### Checking System Status

```bash
# Asterisk uptime / version
asterisk -rx "core show version"
asterisk -rx "core show uptime"

# Reload needed check (FreePBX 17 has no --check flag)
mysql asterisk -N -e "SELECT data FROM admin WHERE variable='need_reload';"
# Result: 1 = reload needed, 0 = up to date

# List installed modules
fwconsole ma list

# Reload config after changes
fwconsole reload
```

### Enabling the GraphQL API

```bash
fwconsole ma install api
fwconsole reload
```

Then create a **Machine-to-Machine** application in:
**Admin → Connectivity → API → Add Application**

---

## GraphQL API

### Authentication (OAuth2 Client Credentials)

```bash
curl -X POST "http://<PBX_IP>:83/admin/api/api/token" \
  -d "grant_type=client_credentials" \
  -d "client_id=<CLIENT_ID>" \
  -d "client_secret=<CLIENT_SECRET>"
```

Response:

```json
{
  "access_token": "eyJ...",
  "token_type": "Bearer",
  "expires_in": 3600
}
```

### Making a Request

```bash
curl -X POST "http://<PBX_IP>:83/admin/api/api/gql" \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"query": "..."}'
```

### Schema Introspection (ALWAYS do this first for your version)

```graphql
# All queries
{ __schema { queryType { fields { name description } } } }

# All mutations
{ __schema { mutationType { fields { name } } } }

# Type fields
{ __type(name: "extension") { fields { name type { name kind } } } }

# Input type fields
{ __type(name: "addExtensionInput") { inputFields { name type { name kind } } } }
```

> **IMPORTANT**: Field names are case-sensitive and may differ between versions. Always introspect before writing queries.

### Available Mutations (v17.0.24)

```
addExtension, updateExtension, deleteExtension, createRangeofExtension
addInboundRoute, updateInboundRoute, removeInboundRoute
addRingGroup, updateRingGroup, deleteRingGroup
addCoreUser, updateCoreUser, removeCoreUser
addCoreDevice, updateCoreDevice, deleteCoreDevice
enableVoiceMail, disableVoiceMail
enableFollowMe, disableFollowMe
doreload
addBlacklist, removeBlacklist
addAllowlist, removeAllowlist
enableFirewall, disableFirewall
addWhiteListIP, addBlackListIP
installModule, uninstallModule, enableModule, disableModule
```

### What Is NOT Available via GraphQL

- SIP Trunks (must use GUI or direct SQL)
- Time Conditions (limited)
- Time Groups
- IVR creation
- TTS generation (GUI only)
- Queue deep configuration

---

## Database Schema & Direct SQL

### Connection

```bash
# On FreePBX server
mysql asterisk

# Or without confirmation
mysql asterisk -e "SELECT ..."
```

### Key Tables

| Table | Purpose |
|-------|---------|
| `users` | Core user/extension data |
| `devices` | SIP device configuration |
| `sip` | Legacy chan_sip settings (still used for many extension settings in v17) |
| `pjsip` | PJSIP-specific settings (trunks, flags=2) |
| `trunks` | Main trunk definitions |
| `incoming` | Inbound routes |
| `outbound_routes` | Outbound route definitions |
| `outbound_route_patterns` | Dial patterns |
| `outbound_route_trunks` | Route-to-trunk linking (has `seq`) |
| `ringgroups` | Ring group config |
| `queues_config` | Call queues |
| `ivr_details` | IVR config |
| `ivr_entries` | IVR menu options |
| `timeconditions` | Time condition routing |
| `timegroups_groups` | Time group definitions |
| `timegroups_details` | Time ranges |
| `admin` | FreePBX system variables (incl. `need_reload`) |
| `kvstore_FreePBX_modules_Voicemail` | Voicemail module settings |
| `recordings` | System Recordings metadata |
| `cdr` | Call Detail Records (in `asteriskcdrdb`) |

### Critical Schema Notes (FreePBX 17)

- **`sip` table** columns: `id`, `keyword`, `data`, `flags` — the value column is **`data`**, NOT `val`
- **`cdr` table** (in `asteriskcdrdb` database): context column is **`dcontext`**, NOT `context`
- **`outbound_routes`** does NOT have a `seq` column in FreePBX 17
- **`outbound_route_trunks`** DOES have a `seq` column (for trunk priority order)
- **`incoming.extension`** may be empty for catch-all routes (normal)
- **`admin` table reload check**: `SELECT data FROM admin WHERE variable='need_reload';`
- Note: `fwconsole reload --check` does NOT exist
- Note: `fwconsole firewall status` is NOT a valid subcommand — use `fwconsole ma list | grep firewall`

### After Any Direct SQL Change

```bash
fwconsole reload
```

---

## Extensions

### GraphQL Schema: `extension`

```
id              - ID (NON_NULL)
extensionId     - ID
tech            - String (pjsip, sip, iax2)
user            - coreuser (nested: name, outboundCid, voicemail, ringtimer, ...)
coreDevice      - coredevice
status          - Boolean
message         - String
```

### GraphQL Schema: `addExtensionInput`

```
extensionId     - Int (NON_NULL, REQUIRED)
name            - String (NON_NULL, REQUIRED)
email           - String (NON_NULL, REQUIRED)
tech            - String (default: pjsip)
outboundCid     - String
emergencyCid    - String
vmEnable        - Boolean
vmPassword      - String
callerID        - String
maxContacts     - String
ringtimer       - String
```

### List Extensions

```graphql
query {
  fetchAllExtensions {
    status
    message
    extension {
      extensionId
      tech
      user { name outboundCid }
    }
  }
}
```

### Create Extension

```graphql
mutation {
  addExtension(input: {
    extensionId: 201
    name: "John Doe"
    email: "john@example.com"
    tech: "pjsip"
    vmEnable: true
    vmPassword: "1234"
  }) {
    status
    message
  }
}
```

> Extension name is in `extension.user.name`, NOT `extension.name`.

### Delete Extension

```graphql
mutation {
  deleteExtension(input: { extensionId: 201 }) { status message }
}
```

### Bulk Create via CSV

```bash
# Preferred method for mass creation
fwconsole bulkimport --type=extensions --replace file.csv
```

CSV headers: `extension,name,tech,secret,voicemail,voicemail_enable`

> **Avoid `!` and special characters in SIP passwords** — some phones can't handle them.

> **Do NOT put extension data in the `pjsip` table** — that table is for trunks only (flags=2). Extensions are stored across `users`, `devices`, and `sip` tables.

### Get SIP Secret for a Specific Extension

```bash
# Note: use the 'sip' table, NOT 'pjsip'
mysql asterisk -N -e "SELECT data FROM sip WHERE id='201' AND keyword='secret';"

# Or via Asterisk CLI
asterisk -rx "pjsip show endpoint 201"
```

### Checking Registration

```bash
asterisk -rx "pjsip show contacts"
asterisk -rx "pjsip show aor 201"
```

Look for `x-ast-orig-host=<ip>` in the contact field to find the phone's local IP.

---

## SIP Trunks

> **GraphQL does NOT support trunk management.** Use direct SQL or GUI.

### Required Tables

1. `trunks` — main trunk definition
2. `pjsip` — PJSIP settings (all keyed to the same `id` matching `trunkid`)

### `trunks` Table Schema

| Column | Type | Notes |
|--------|------|-------|
| `trunkid` | int PK auto | |
| `name` | varchar(50) | Display name (often called "trunk_name" in GUI but column is `name`) |
| `tech` | varchar(20) | pjsip, sip, iax2, dahdi, custom |
| `channelid` | varchar(190) | |
| `outcid` | varchar(255) | Outbound Caller ID |
| `keepcid` | varchar(4) | Preserve inbound CID (off/on) |
| `maxchans` | varchar(6) | Max concurrent channels |
| `dialoutprefix` | varchar(255) | |
| `usercontext` | varchar(255) | |
| `provider` | varchar(40) | |
| `disabled` | varchar(4) | |
| `continue` | varchar(4) | Continue on failure |

### Required PJSIP Keywords for a Working Trunk

All entries share one `id` matching `trunkid` from the `trunks` table:

| Keyword | Example Value | Critical Notes |
|---------|---------------|----------------|
| `trunk_name` | `myprovider` | **Required** — FreePBX code accesses `$trunk['trunk_name']` |
| `secret` | `YOUR_SIP_PASSWORD` | NOT `password` — FreePBX uses `$trunk['secret']` |
| `authentication` | `outbound` | NOT `auth_type` — values: `outbound`/`inbound`/`both`/`none` |
| `sip_server` | `sip.provider.com` | Used for URI construction |
| `registration` | `send` | `send` for credential auth, `none` for IP auth |
| `aors` | `myprovider` | **MUST match AOR section name (trunk name), NOT the trunkid** |
| `retry_interval` | `60` | Required when registration=send |
| `expiration` | `3600` | Required when registration=send |
| `qualify_frequency` | `0` | Set to 0 if provider doesn't respond to OPTIONS |

### The `aors` Mismatch Bug (causes "All Circuits Busy")

When creating PJSIP trunks via direct SQL, the endpoint's `aors` keyword commonly ends up set to the **trunk ID number** (e.g., `1`) instead of the **trunk name**. The generated config then shows:

```ini
[myprovider]
type=endpoint
aors=1          ; WRONG — AOR section named '1' doesn't exist
```

It should be:

```ini
[myprovider]
type=endpoint
aors=myprovider ; CORRECT — matches the [myprovider] AOR section
```

**Symptom**: Outbound calls fail instantly with "all circuits are busy", CDR shows `DIALSTATUS=CHANUNAVAIL`, `HANGUPCAUSE=3`, endpoint shows `Unavailable` or error `Could not create dialog to invalid URI '1'`.

**Fix**:

```sql
UPDATE pjsip SET data='myprovider' WHERE id='1' AND keyword='aors';
-- Then: fwconsole reload
```

**Verification**:

```bash
grep 'aors=' /etc/asterisk/pjsip.endpoint.conf
asterisk -rx 'pjsip show endpoint myprovider'   # Should be "Not in use"
asterisk -rx 'pjsip show aor myprovider'         # Should have contact
```

### Checking Trunk Status

```bash
asterisk -rx "pjsip show endpoints"
asterisk -rx "pjsip show endpoint TRUNKNAME"
asterisk -rx "pjsip show registrations"
```

---

## Outbound Routes

### Standard US/Canada Dial Patterns

| Prefix | Pattern | Description |
|--------|---------|-------------|
| | `NXXXXXX` | 7-digit local (area-code-optional) |
| | `NXXNXXXXXX` | 10-digit |
| | `1NXXNXXXXXX` | 11-digit (1 + area code) |
| | `011.` | International |

### Emergency Route (Mark as Emergency)

| Prefix | Pattern | Description |
|--------|---------|-------------|
| | `911` | Direct emergency |
| | `933` | Emergency test line |
| | `988` | Crisis hotline |
| `1` | `911` | 1+911 |
| `9` | `911` | Outside-line+911 |

> **E911 Warning**: Creating a 911 dial pattern is only one part of a functional emergency system. You MUST separately configure E911 with your VoIP provider, register your physical address, and test from every extension. VoIP-based 911 fails when your internet or trunk is down. Always test after setup.

### Schema: `outbound_routes` Table

```
route_id, name, outcid, outcid_mode, password,
emergency_route (YES/empty), intracompany_route, mohclass,
time_group_id, dest, time_mode, calendar_id, timezone
```

> **No `seq` column in `outbound_routes`** — priority is set via `outbound_route_trunks.seq`.

### Schema: `outbound_route_patterns`

```
route_id, match_pattern_prefix, match_pattern_pass, match_cid, prepend_digits
```

### Schema: `outbound_route_trunks`

```
route_id, trunk_id, seq   -- seq = priority order
```

---

## Inbound Routes

### GraphQL: List Inbound Routes

```graphql
query {
  allInboundRoutes {
    inboundRoutes { extension description cidnum }
  }
}
```

### GraphQL: Create Inbound Route

```graphql
mutation {
  addInboundRoute(input: {
    description: "Main Line"
    destination: "from-did-direct,201,1"
  }) { status message }
}
```

### Destination String Format

| Destination Type | Format | Example |
|------------------|--------|---------|
| Extension | `from-did-direct,EXT,1` | `from-did-direct,201,1` |
| Ring Group | `ext-group,GRPNUM,1` | `ext-group,600,1` |
| Time Condition | `timeconditions,ID,1` | `timeconditions,2,1` |
| IVR | `ivr-ID,s,1` | `ivr-1,s,1` |
| Voicemail (unavail) | `ext-local,vmuEXT,1` | `ext-local,vmu299,1` |
| Voicemail (busy) | `ext-local,vmbEXT,1` | `ext-local,vmb299,1` |
| Voicemail (no-msg) | `ext-local,vmsEXT,1` | `ext-local,vms299,1` |
| Parking Lot | `park-dial,SLOT,1` | `park-dial,701,1` |
| Recording | `recordings,ID,1` | `recordings,1,1` |
| Hangup | `app-blackhole,hangup,1` | |

> Use `vmu` (unavailable), `vmb` (busy), or `vms` (no message — straight to beep) — NOT just `vm`.

> The GraphQL API validates destinations exist before accepting them. Invalid destinations cause mutation failure.

---

## Ring Groups

### GraphQL: Create Ring Group

```graphql
mutation {
  addRingGroup(input: {
    groupNumber: 600
    strategy: "ringall"
    extensionList: "201-202-203"
    description: "Sales Team"
    ringTime: "20"
  }) { status message }
}
```

### Ring Strategies

- `ringall` — Ring all simultaneously
- `hunt` — Ring in order
- `memoryhunt` — Ring first, then first+second, etc.
- `firstavailable` — Ring first available
- `firstnotonphone` — Ring first not on phone

### Gotchas

- Input field is `groupNumber` (camelCase)
- Input uses `extensionList` as a string: `"201-202-203"`
- Response field is `ringgroups` (all lowercase), NOT `ringGroups`
- Schema field is `groupList` internally, NOT `extensionList`

---

## Time Conditions

### Flow

```
Inbound Route → Time Condition → checks Time Group
                    ├── Match (true):    Destination A
                    └── No Match (false): Destination B
```

### Schema: `timeconditions`

```sql
timeconditions_id   - INT (auto, PK)
displayname         - VARCHAR(50)
time                - INT (references timegroups_groups.id)
truegoto            - VARCHAR(50)    -- destination if time matches
falsegoto           - VARCHAR(50)    -- destination if time doesn't match
mode                - VARCHAR(20)    -- default: "time-group"
timezone            - VARCHAR(255)
```

### Database Operations (no GraphQL support)

```sql
-- List time groups
SELECT * FROM timegroups_groups;

-- Create time condition
INSERT INTO timeconditions (displayname, time, truegoto, falsegoto, mode)
VALUES ('Business Hours', 1, 'ext-group,600,1', 'ext-local,vm201,1', 'time-group');
```

---

## IVR & System Recordings

### IVR Storage

- `ivr_details` — IVR config
- `ivr_entries` — menu options (key → destination mapping)
- `ivr_details.announcement` — recording ID for greeting

### System Recordings

Recordings metadata is stored in the `recordings` table. Files live at:

```
/var/lib/asterisk/sounds/en/custom/
```

| Operation | GraphQL Support |
|-----------|-----------------|
| List recordings | `fetchAllRecordings` |
| Upload new recording | Partial (file upload only) |
| Update metadata | Yes (`deleteRecording` etc.) |
| **TTS generation** | **No — GUI only** |

### Linking Recording to IVR

```sql
UPDATE ivr_details SET announcement=1 WHERE id=1;
```

### TTS Engines (GUI only)

Admin → System Recordings → TTS — OpenAI, Google, Amazon Polly, etc.

> For provisioning tools: TTS must be generated manually before automated setup references a recording.

---

## Voicemail & Email-to-Voicemail

### Voicemail Config Location

`/etc/asterisk/voicemail.conf` is regenerated by FreePBX. Do not edit directly unless you know the voicemail module will preserve your change (it does preserve existing `[general]` keys like `mailcmd`).

### FreePBX Voicemail Module Storage

Module settings live in table `kvstore_FreePBX_modules_Voicemail`.

### Setting `mailcmd` (for custom mail delivery like Graph API)

The voicemail module reads existing `[general]` keys from `voicemail.conf` and preserves them on regeneration. You can inject `mailcmd` directly:

```bash
# Add after [general]
sed -i '/^\[general\]/a mailcmd=/usr/local/bin/graph-sendmail.sh' /etc/asterisk/voicemail.conf
asterisk -rx "module reload app_voicemail.so"
```

Also set `serveremail` to match your sender so email From: matches the Graph API sender:

```bash
sed -i '/^\[general\]/a serveremail=voicemail@yourcompany.com' /etc/asterisk/voicemail.conf
```

### Setting Voicemail Email Address

Format in `voicemail.conf`:

```
201=,John Doe,john@example.com,,attach=yes|saycid=no|envelope=no|delete=no
```

Fields (comma-separated): `password,name,email,pager,options`.

### Microsoft Graph API Voicemail-to-Email

For tenants where basic SMTP is disabled (M365), use the included `graph-sendmail.sh` script as a drop-in `mailcmd` replacement. See [../README.md](../README.md) and [scripts/graph-sendmail.sh](../scripts/graph-sendmail.sh).

Setup summary:

1. Register an app in Microsoft Entra with `Mail.Send` application permission
2. Create a client secret
3. (Recommended) Create an Application Access Policy to restrict app to one mailbox:
   - Create a mail-enabled security group (shared mailboxes aren't security principals themselves)
   - Add the sender mailbox to the group
   - Run `New-ApplicationAccessPolicy -AppId <ID> -PolicyScopeGroupId "<group>" -AccessRight RestrictAccess`
4. Deploy `graph-sendmail.sh` to `/usr/local/bin/`, `chmod 755`
5. Create `/etc/asterisk/graph-mail.conf` with credentials (mode 600, asterisk-owned)
6. Set `mailcmd=/usr/local/bin/graph-sendmail.sh` in `voicemail.conf [general]`
7. Set `serveremail=<sender@yourdomain.com>` to match Graph sender
8. Reload voicemail

### Key Graph API Gotcha

`curl -d` mangles large base64 payloads (voicemail WAV attachments). Must use `curl --data-binary @file`. The included `graph-sendmail.sh` handles this correctly.

---

## Parking Lots

### Table: `parkplus`

| Field | Description | Typical Value |
|-------|-------------|---------------|
| `name` | Lot name | Default Lot |
| `parkext` | Extension to dial to park | 700 |
| `parkpos` | Starting slot number | 701 |
| `numslots` | Number of parking slots | 8 (gives 701-708) |
| `parkingtime` | Seconds before timeout | 300 |
| `parkedmusicclass` | MoH class | default |
| `findslot` | Slot assignment | first |
| `comebacktoorigin` | Return to parker on timeout | yes |
| `dest` | Timeout destination | `app-blackhole,hangup,1` |

### Usage

- Transfer to `700` → announces slot number
- Retrieve: dial slot number (`701`-`708`)
- BLF keys can monitor slots

### Destination Format

`park-dial,<slot>,1` e.g., `park-dial,701,1`

---

## Firewall & NAT

### Responsive Firewall — Trust an IP

```bash
# Add remote site WAN IP to trusted zone
fwconsole firewall trust <WAN_IP>

# List trusted IPs
fwconsole firewall list trusted

# Restart firewall after major changes
fwconsole firewall restart
```

### Cloud Provider Firewall (Linode, etc.)

Open for phone networks:

- Port 80 (TCP) — config downloads
- Port 5060 (UDP) — SIP registration
- Port 10000-20000 (UDP) — RTP
- (Optional) Port 83 (TCP) — API, localhost-only is safer

### NAT: Direct Media Issue

If phones are behind NAT (remote office, home users), you MUST disable `direct_media` on their extensions. Otherwise inbound calls drop immediately (CDR `lastapp=Congestion`) while outbound works fine.

```bash
# Check current settings
mysql asterisk -e "SELECT id, data FROM sip WHERE keyword='direct_media' AND id LIKE '20%';"

# Disable for extensions 201-210
mysql asterisk -e "UPDATE sip SET data='no' WHERE keyword='direct_media' AND id IN ('201','202','203','204','205','206','207','208','209','210');"

fwconsole reload

# Verify
grep 'direct_media' /etc/asterisk/pjsip.endpoint.conf | head -5
```

### Required NAT Settings (per-extension)

| Setting | Value | Purpose |
|---------|-------|---------|
| `direct_media` | `no` | Route audio through PBX |
| `rewrite_contact` | `yes` | Use phone's public IP from registration |
| `rtp_symmetric` | `yes` | Send RTP to same port we receive from |
| `force_rport` | `yes` | Force response to source port |

---

## fwconsole Reference

### Commonly Used

```bash
# Apply configuration changes
fwconsole reload

# List installed modules and status
fwconsole ma list

# Install/enable a module
fwconsole ma install <module>
fwconsole ma enable <module>

# Bulk import via CSV
fwconsole bulkimport --type=extensions --replace file.csv

# Fix permissions after file changes
fwconsole chown

# Firewall management
fwconsole firewall trust <IP>
fwconsole firewall list trusted
fwconsole firewall restart

# Restart services
fwconsole restart
fwconsole stop
fwconsole start

# Trunk list/toggle (NO creation)
fwconsole trunk --list
fwconsole trunk --enable <ID>
fwconsole trunk --disable <ID>

# Convert chan_sip trunks to PJSIP (FreePBX 17)
fwconsole trunks --convert2pjsip all
```

### What DOESN'T Work

- `fwconsole firewall status` — not a valid subcommand (use `fwconsole ma list | grep firewall`)
- `fwconsole reload --check` — flag doesn't exist (use SQL: `SELECT data FROM admin WHERE variable='need_reload';`)

---

## Troubleshooting

### "All Circuits Are Busy"

Most common causes in order:

1. **PJSIP `aors` mismatch** (see [SIP Trunks](#sip-trunks)) — most common when creating trunks via SQL
2. **Invalid outbound CID** — many providers reject calls with extension-number CIDs. Set a valid DID:
   ```sql
   UPDATE trunks SET outcid='"Outbound" <YOUR_DID>' WHERE trunkid=1;
   ```
3. **Provider IP blacklist** — too many failed registrations can get your PBX IP firewalled. Diagnose with `sipsak -vv -s sip:user@server.provider.com` (timeout = blocked). Fix: switch to a different provider server.
4. **`qualify_frequency > 0` marking endpoint unavailable** — if provider doesn't respond to OPTIONS:
   ```sql
   UPDATE pjsip SET data='0' WHERE id='1' AND keyword='qualify_frequency';
   ```
5. **No sub-account** — some providers (like VoIP.ms) don't let main accounts register. Create a sub-account.

### Inbound Calls Drop Instantly

Usually NAT-related. Check `direct_media` is disabled on extensions (see [NAT](#firewall--nat)).

### Phones Register But Can't Fetch Configs

- Port 80 not open on cloud firewall
- Phone WAN IP not in FreePBX trusted zone
- Check Apache logs: `tail -f /var/log/apache2/access.log`

### Phones Fetch Configs But Don't Register

- Port 5060 UDP not open on cloud firewall
- SIP credentials mismatch

### Windows-Uploaded Shell Scripts Fail

CRLF line endings break them. Fix:

```bash
sed -i 's/\r//' script.sh
```

---

## Gotchas & Lessons Learned

### GraphQL API

1. **Always introspect the schema first** — field names vary between versions
2. **Case sensitivity** — response field is `ringgroups` (lowercase), input is `groupNumber` (camelCase)
3. **Nested objects** — extension name is in `extension.user.name`, not `extension.name`
4. **Destination validation** — mutations validate destinations exist before accepting
5. **Connection types** — some queries use pagination wrappers (`allInboundRoutes.inboundRoutes`)
6. **No trunk management via GraphQL** — use SQL or GUI
7. **Reload required** — call `doreload` mutation after changes
8. **Port 83 API** — blocked externally by default; either open it or run scripts from localhost
9. **HTTP vs HTTPS on port 83** — from localhost, port 83 may only respond on HTTP. Try HTTP first.

### SQL

1. **`sip` table uses `data` column, not `val`**
2. **`cdr` table uses `dcontext`, not `context`**
3. **Do NOT put extension data in `pjsip` table** — that's for trunks (flags=2)
4. **`outbound_routes` has no `seq` column** — priority is in `outbound_route_trunks.seq`
5. **Use `secret` not `password`** for PJSIP trunk auth
6. **Use `authentication` not `auth_type`** — values: `outbound`/`inbound`/`both`/`none`

### `fwconsole`

1. `fwconsole firewall status` is NOT valid — use `fwconsole ma list | grep firewall`
2. `fwconsole reload --check` does NOT exist — check `admin` table `need_reload` instead

### Operational

1. **Avoid `!` and special chars in SIP passwords** — phones may not handle them
2. **SIP passwords from providers** often have odd characters — wrap SQL values in quotes carefully
3. **Always test from a real workstation** after any change — GraphQL success ≠ actual functionality
4. **Keep old backups renamed as `.OLD` for a week** after any database or config file migration

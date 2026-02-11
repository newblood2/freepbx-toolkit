---
name: fix-nat
description: Fix direct_media NAT issues on any FreePBX server
disable-model-invocation: true
allowed-tools: Bash, Read, Grep
argument-hint: [server-ip]
---

# Fix NAT - Correct direct_media and NAT Settings

**Required argument:** `$ARGUMENTS` = FreePBX server IP/hostname

Parse the server IP from `$ARGUMENTS` (first word).

## Background
When phones are behind NAT (which is almost always the case), `direct_media=yes` causes one-way audio because Asterisk tries to send RTP directly between endpoints instead of proxying it. This skill fixes that and related NAT settings.

## Steps

### 1. Check current direct_media settings
```bash
ssh root@$1 "mysql -N -B asterisk -e \"SELECT s.id, d.description, s.data FROM sip s LEFT JOIN devices d ON s.id = d.id WHERE s.keyword='direct_media' AND s.data='yes';\"" 2>/dev/null
```

Report which extensions currently have `direct_media=yes`.

### 2. Fix direct_media - set to 'no' for all extensions
```bash
ssh root@$1 "mysql asterisk -e \"UPDATE sip SET data='no' WHERE keyword='direct_media' AND data='yes';\"" 2>/dev/null
```

### 3. Ensure rewrite_contact is set to 'yes'
```bash
ssh root@$1 "mysql asterisk -e \"UPDATE sip SET data='yes' WHERE keyword='rewrite_contact' AND data='no';\"" 2>/dev/null
```

### 4. Ensure rtp_symmetric is set to 'yes'
```bash
ssh root@$1 "mysql asterisk -e \"UPDATE sip SET data='yes' WHERE keyword='rtp_symmetric' AND data='no';\"" 2>/dev/null
```

### 5. Ensure force_rport is set to 'yes'
```bash
ssh root@$1 "mysql asterisk -e \"UPDATE sip SET data='yes' WHERE keyword='force_rport' AND data='no';\"" 2>/dev/null
```

### 6. Apply changes with fwconsole reload
```bash
ssh root@$1 "fwconsole reload" 2>/dev/null
```

### 7. Verify changes in live config
```bash
ssh root@$1 "grep -A2 'direct_media' /etc/asterisk/pjsip.endpoint.conf | head -30" 2>/dev/null
```

### 8. Verify all settings are correct now
```bash
ssh root@$1 "mysql -N -B asterisk -e \"SELECT s.id, s.keyword, s.data FROM sip s WHERE s.keyword IN ('direct_media','rewrite_contact','rtp_symmetric','force_rport') AND ((s.keyword='direct_media' AND s.data='yes') OR (s.keyword IN ('rewrite_contact','rtp_symmetric','force_rport') AND s.data='no'));\"" 2>/dev/null
```

If this returns no rows, all settings are correct.

## Output Format

```
=== NAT Fix Report: $SERVER_IP ===

Before:
- Extensions with direct_media=yes: 204, 207, 210 (3 total)

Changes Applied:
- direct_media: yes → no (3 extensions updated)
- rewrite_contact: verified yes for all
- rtp_symmetric: verified yes for all
- force_rport: verified yes for all

Reload: Applied successfully

Verification:
- All extensions now have correct NAT settings ✓
```

## What These Settings Do
- **direct_media=no**: Forces RTP through Asterisk (prevents one-way audio behind NAT)
- **rewrite_contact=yes**: Rewrites SIP Contact header with actual IP (NAT traversal)
- **rtp_symmetric=yes**: Sends RTP back to the same IP:port it came from
- **force_rport=yes**: Forces rport even if the phone doesn't request it

## Common Issues
- If `fwconsole reload` hangs: try `ssh root@$1 "fwconsole reload --verbose"` to see what's stuck
- If changes don't appear in pjsip.endpoint.conf: the FreePBX dialplan generator may be cached, try `asterisk -rx 'dialplan reload'`

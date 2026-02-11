---
name: phone-status
description: Check phone registrations on any FreePBX server
disable-model-invocation: false
allowed-tools: Bash, Read, Grep
argument-hint: [server-ip]
---

# Phone Status - Check SIP Registrations

**Required argument:** `$ARGUMENTS` = FreePBX server IP/hostname

Parse the server IP from `$ARGUMENTS` (first word).

## Steps

### 1. Get PJSIP contacts (registered phones)
```bash
ssh root@$1 "asterisk -rx 'pjsip show contacts'" 2>/dev/null
```

### 2. Get extension names from the database
```bash
ssh root@$1 "mysql -N -B asterisk -e \"SELECT id, description FROM devices;\"" 2>/dev/null
```

### 3. Get PJSIP endpoint details for additional context
```bash
ssh root@$1 "asterisk -rx 'pjsip show endpoints'" 2>/dev/null
```

## Output Format

Display a clean formatted table with these columns:
| Extension | Name | Status | IP Address | RTT |
|-----------|------|--------|------------|-----|

- **Extension**: The endpoint/extension number
- **Name**: Human-readable name from `devices` table
- **Status**: Avail / NonQual / Unavail
- **IP Address**: The contact URI (IP:port)
- **RTT**: Round-trip time if available

## Summary Line
After the table, show:
- Total registered / total configured
- Any extensions that are configured but NOT registered (potential issues)

## Common Issues
- If SSH fails: suggest checking SSH key auth (`ssh-copy-id root@<server>`)
- If no contacts shown: check if PJSIP is running (`asterisk -rx 'core show channels'`)
- `NonQual` status usually means qualify is disabled, not necessarily a problem

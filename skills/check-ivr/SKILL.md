---
name: check-ivr
description: View IVR configuration on any FreePBX server
disable-model-invocation: false
allowed-tools: Bash, Read, Grep
argument-hint: [server-ip]
---

# Check IVR - View IVR Configuration

**Required argument:** `$ARGUMENTS` = FreePBX server IP/hostname

Parse the server IP from `$ARGUMENTS` (first word).

## Steps

### 1. Get IVR details (main IVR settings)
```bash
ssh root@$1 "mysql -N -B asterisk -e \"SELECT id, name, description FROM ivr_details;\""
```

### 2. Get IVR entries (key press destinations)
```bash
ssh root@$1 "mysql -N -B asterisk -e \"SELECT ivr_id, selection, dest, ivr_ret FROM ivr_entries ORDER BY ivr_id, selection;\""
```

### 3. Get extension names for resolving destinations
```bash
ssh root@$1 "mysql -N -B asterisk -e \"SELECT id, description FROM devices;\""
```

### 4. Get queue names for resolving destinations
```bash
ssh root@$1 "mysql -N -B asterisk -e \"SELECT extension, descr FROM queues_details WHERE keyword='descr';\"" 2>/dev/null
ssh root@$1 "mysql -N -B asterisk -e \"SELECT extension, descr FROM queues_config;\"" 2>/dev/null
```

### 5. Get ring group names
```bash
ssh root@$1 "mysql -N -B asterisk -e \"SELECT grpnum, description FROM ringgroups;\""
```

### 6. Get time conditions
```bash
ssh root@$1 "mysql -N -B asterisk -e \"SELECT timeconditions_id, displayname FROM timeconditions;\""
```

### 7. Get announcements
```bash
ssh root@$1 "mysql -N -B asterisk -e \"SELECT announcement_id, description FROM announcement;\""
```

## Destination Resolution

FreePBX destinations are formatted as `module,id,priority`. Common patterns:
- `ext-local,204,1` → Extension 204
- `ext-queues,400,1` → Queue 400
- `ivr-10,s,1` → IVR ID 10
- `timeconditions,1,0` → Time Condition ID 1
- `app-announcement-1,s,1` → Announcement ID 1
- `ext-group,600,1` → Ring Group 600
- `app-blackhole,hangup,1` → Hangup
- `app-blackhole,zapateller,1` → Play SIT tones then hangup

Resolve each destination to a human-readable format using the data gathered above.

## Output Format

For each IVR, display:

```
=== IVR: [Name] (ID: X) ===
Description: ...

| Key | Destination | Details |
|-----|-------------|---------|
| 1   | Extension 204 | John Smith |
| 2   | Queue 400   | Sales Queue |
| 3   | Ring Group 600 | Support Team |
| t   | IVR: Main Menu | (timeout) |
| i   | Hangup | (invalid) |
```

- `t` = timeout destination
- `i` = invalid input destination

## Notes
- If no IVRs exist, report that clearly
- Show the timeout and invalid destinations from `ivr_details` table as well

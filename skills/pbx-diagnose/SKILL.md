---
name: pbx-diagnose
description: Run full diagnostic check on any FreePBX server
disable-model-invocation: false
allowed-tools: Bash, Read, Grep
argument-hint: [server-ip]
---

# PBX Diagnose - Full System Diagnostic

**Required argument:** `$ARGUMENTS` = FreePBX server IP/hostname

Parse the server IP from `$ARGUMENTS` (first word).

Run ALL the following checks via SSH and present a summary report.

## Diagnostic Checks

### 1. Trunk Registration
```bash
ssh root@$1 "asterisk -rx 'pjsip show registrations'" 2>/dev/null
```
- **PASS**: All trunks show `Registered`
- **FAIL**: Any trunk shows `Unregistered` or `Rejected`

### 2. Extension Registrations
```bash
ssh root@$1 "asterisk -rx 'pjsip show contacts'" 2>/dev/null
```
Also get total configured extensions:
```bash
ssh root@$1 "mysql -N -B asterisk -e \"SELECT COUNT(*) FROM devices;\"" 2>/dev/null
```
- **PASS**: All or most extensions registered
- **WARN**: Some extensions not registered (list them)
- **FAIL**: No extensions registered

### 3. Direct Media / NAT Settings
```bash
ssh root@$1 "mysql -N -B asterisk -e \"SELECT d.id, d.description, s.data FROM devices d JOIN sip s ON d.id = s.id WHERE s.keyword='direct_media' AND s.data='yes';\"" 2>/dev/null
```
- **PASS**: No extensions have `direct_media=yes`
- **FAIL**: Extensions found with `direct_media=yes` (causes one-way audio behind NAT)

### 4. Firewall Status
Check if firewall module is installed and enabled:
```bash
ssh root@$1 "fwconsole ma list 2>/dev/null | grep -i firewall"
```
List trusted IPs:
```bash
ssh root@$1 "fwconsole firewall list trusted 2>/dev/null || echo 'Firewall module not active'"
```
- **PASS**: Firewall module enabled with trusted IPs
- **WARN**: Firewall not installed/active
- **INFO**: List trusted IPs

### 5. Recent Asterisk Errors
```bash
ssh root@$1 "tail -200 /var/log/asterisk/full | grep -i 'error\|warning\|fatal' | tail -20" 2>/dev/null
```
- **PASS**: No recent errors
- **WARN**: Warnings found (show them)
- **FAIL**: Errors or fatal messages found

### 6. Reload Pending
```bash
ssh root@$1 "mysql -N -B asterisk -e \"SELECT data FROM admin WHERE variable='need_reload';\"" 2>/dev/null
```
- **PASS**: Returns `false` or empty (no reload needed)
- **WARN**: Returns `true` (reload needed - run `fwconsole reload`)

### 7. Asterisk Service Status
```bash
ssh root@$1 "systemctl status asterisk --no-pager -l 2>/dev/null | head -5"
```
- **PASS**: Active (running)
- **FAIL**: Not running

### 8. Disk Space
```bash
ssh root@$1 "df -h / /var 2>/dev/null | tail -n+2"
```
- **PASS**: Less than 80% used
- **WARN**: 80-90% used
- **FAIL**: Over 90% used

### 9. FreePBX Version
```bash
ssh root@$1 "fwconsole --version 2>/dev/null"
```

### 10. Uptime and Load
```bash
ssh root@$1 "uptime" 2>/dev/null
```
- **PASS**: Load average reasonable (< number of CPUs)
- **WARN**: High load

## Output Format

Present as a diagnostic report:

```
=== FreePBX Diagnostic Report: $SERVER_IP ===
FreePBX Version: X.X.X
Uptime: X days, load average: X.XX

Check                    | Status | Details
-------------------------|--------|--------
Trunk Registration       | PASS   | 2/2 registered
Extension Registration   | WARN   | 8/12 registered (201,205,210,215 missing)
Direct Media (NAT)       | FAIL   | 3 extensions have direct_media=yes
Firewall                 | PASS   | Active, 5 trusted IPs
Recent Errors            | WARN   | 3 warnings found
Reload Pending           | PASS   | No reload needed
Asterisk Service         | PASS   | Running
Disk Space               | PASS   | 45% used

=== Action Items ===
1. [FAIL] Fix direct_media for extensions: 204, 207, 210 (run /fix-nat $SERVER_IP)
2. [WARN] Check unregistered extensions: 201, 205, 210, 215
3. [WARN] Review recent warnings in /var/log/asterisk/full
```

## Notes
- Run all checks even if some fail - give the complete picture
- Suggest specific remediation commands or other skills (like `/fix-nat`) where applicable
- If SSH connection fails entirely, report that first and stop

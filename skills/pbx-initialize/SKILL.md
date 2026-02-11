---
name: pbx-initialize
description: Initialize and configure a new or existing FreePBX server
disable-model-invocation: true
allowed-tools: Bash, Read, Grep
argument-hint: [server-ip]
---

# PBX Initialize - Set Up FreePBX Server

**Required argument:** `$ARGUMENTS` = FreePBX server IP/hostname

Parse the server IP from `$ARGUMENTS` (first word).

This skill runs through a full initialization/verification of a FreePBX server, whether it's a new deployment or an existing system we're onboarding.

## Steps

### 1. Set Up SSH Key Auth
First test if SSH key auth already works:
```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 root@$1 "echo ok" 2>/dev/null
```

If that fails, set up SSH key auth:
```bash
ssh-copy-id root@$1
```
This will prompt for the root password interactively.

### 2. Test SSH Connectivity
```bash
ssh root@$1 "hostname && uname -a" 2>/dev/null
```

### 3. Check FreePBX Version and Modules
```bash
ssh root@$1 "fwconsole --version" 2>/dev/null
ssh root@$1 "fwconsole ma list | grep -E 'Enabled|Status'" 2>/dev/null
```

Get key module status:
```bash
ssh root@$1 "fwconsole ma list | grep -E 'endpointman|firewall|sipsettings|ivr|queues|ringgroups|timeconditions'" 2>/dev/null
```

### 4. Verify API Credentials (GraphQL on port 83)
Check if API port is listening:
```bash
ssh root@$1 "ss -tlnp | grep ':83 '" 2>/dev/null
```

Test API accessibility (try HTTP first since port 83 often uses HTTP):
```bash
ssh root@$1 "curl -sk --max-time 5 -o /dev/null -w '%{http_code}' http://localhost:83/admin/api/api/gql" 2>/dev/null
```

If that fails, try HTTPS:
```bash
ssh root@$1 "curl -sk --max-time 5 -o /dev/null -w '%{http_code}' https://localhost:83/admin/api/api/gql" 2>/dev/null
```

### 5. Fix Direct Media / NAT Settings
Check for bad NAT settings:
```bash
ssh root@$1 "mysql -N -B asterisk -e \"SELECT s.id, d.description FROM sip s LEFT JOIN devices d ON s.id = d.id WHERE s.keyword='direct_media' AND s.data='yes';\"" 2>/dev/null
```

If any found, fix them:
```bash
ssh root@$1 "mysql asterisk -e \"UPDATE sip SET data='no' WHERE keyword='direct_media' AND data='yes';\""
ssh root@$1 "mysql asterisk -e \"UPDATE sip SET data='yes' WHERE keyword='rewrite_contact' AND data='no';\""
ssh root@$1 "mysql asterisk -e \"UPDATE sip SET data='yes' WHERE keyword='rtp_symmetric' AND data='no';\""
ssh root@$1 "mysql asterisk -e \"UPDATE sip SET data='yes' WHERE keyword='force_rport' AND data='no';\""
```

### 6. Trust Current WAN IP in Firewall
Get our current WAN IP:
```bash
curl -s ifconfig.me
```

Check if already trusted:
```bash
ssh root@$1 "fwconsole firewall list trusted 2>/dev/null"
```

If not already trusted:
```bash
ssh root@$1 "fwconsole firewall trust $WAN_IP && fwconsole firewall restart" 2>/dev/null
```

### 7. Check Trunk Registration
```bash
ssh root@$1 "asterisk -rx 'pjsip show registrations'" 2>/dev/null
```

### 8. Set Up Provisioning Directory
```bash
ssh root@$1 "mkdir -p /var/www/html/prov && chown asterisk:asterisk /var/www/html/prov && chmod 755 /var/www/html/prov" 2>/dev/null
```

Verify it's accessible (403 is OK — means directory exists but listing is disabled; 404 means it's missing):
```bash
curl -sk --max-time 5 -o /dev/null -w "%{http_code}" http://$1/prov/
```

### 9. System Summary
Gather all summary info:

```bash
# Extensions
ssh root@$1 "mysql -N -B asterisk -e \"SELECT COUNT(*) FROM devices;\"" 2>/dev/null

# Extension list with names
ssh root@$1 "mysql -N -B asterisk -e \"SELECT id, description FROM devices ORDER BY CAST(id AS UNSIGNED);\"" 2>/dev/null

# Trunks
ssh root@$1 "mysql -N -B asterisk -e \"SELECT trunkid, name, channelid FROM trunks;\"" 2>/dev/null

# Outbound Routes
ssh root@$1 "mysql -N -B asterisk -e \"SELECT route_id, name FROM outbound_routes;\"" 2>/dev/null

# Inbound Routes
ssh root@$1 "mysql -N -B asterisk -e \"SELECT extension, description, destination FROM incoming;\"" 2>/dev/null

# IVRs
ssh root@$1 "mysql -N -B asterisk -e \"SELECT id, name FROM ivr_details;\"" 2>/dev/null

# Ring Groups
ssh root@$1 "mysql -N -B asterisk -e \"SELECT grpnum, description FROM ringgroups;\"" 2>/dev/null

# Queues
ssh root@$1 "mysql -N -B asterisk -e \"SELECT extension, descr FROM queues_config;\"" 2>/dev/null

# Registered phones
ssh root@$1 "asterisk -rx 'pjsip show contacts'" 2>/dev/null
```

### 10. Apply reload if any changes were made
```bash
ssh root@$1 "fwconsole reload" 2>/dev/null
```

## Output Format

```
=== FreePBX Server Initialization: $SERVER_IP ===

Connection:     SSH key auth working ✓
FreePBX:        v16.0.40.1
Asterisk:       v20.5.0

NAT Settings:   Fixed 5 extensions (direct_media → no)
Firewall:       WAN IP 1.2.3.4 trusted ✓
Provisioning:   /var/www/html/prov/ ready ✓

=== System Summary ===
Extensions:     12 configured, 8 registered
Trunks:         2 (all registered)
Outbound Routes: 3
Inbound Routes:  4
IVRs:           2
Ring Groups:    3
Queues:         1

=== Extensions ===
| Ext | Name          | Registered |
|-----|---------------|------------|
| 200 | Front Desk    | Yes        |
| 201 | John Smith    | Yes        |
| 202 | Jane Doe      | No         |
...

=== Trunks ===
| Trunk           | Status     |
|-----------------|------------|
| VoIP.ms-Main    | Registered |
| VoIP.ms-Backup  | Registered |
```

## Common Issues
- SSH key auth fails: ensure `PermitRootLogin yes` in `/etc/ssh/sshd_config`
- FreePBX not found: check if it's installed at `/var/www/html/admin/`
- MySQL access denied: FreePBX uses `/etc/freepbx.conf` for DB credentials
- Port 83 not listening: API module may not be installed (`fwconsole ma install api`)

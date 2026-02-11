---
name: firewall-trust
description: Trust an IP address in FreePBX firewall
disable-model-invocation: true
allowed-tools: Bash, Read, Grep
argument-hint: [server-ip] [wan-ip-to-trust]
---

# Firewall Trust - Add Trusted IP to FreePBX Firewall

**Required arguments from `$ARGUMENTS`:**
- First word = FreePBX server IP/hostname
- Second word = WAN IP to trust in the firewall

Parse both from `$ARGUMENTS`. If the WAN IP is not provided, determine the user's current WAN IP:
```bash
curl -s ifconfig.me
```

## Steps

### 1. Trust the IP in FreePBX firewall
```bash
ssh root@$1 "fwconsole firewall trust $WAN_IP"
```

### 2. Restart the firewall to apply
```bash
ssh root@$1 "fwconsole firewall restart"
```

### 3. Verify - list current trusted IPs
```bash
ssh root@$1 "fwconsole firewall list trusted"
```

If the above command doesn't work, try:
```bash
ssh root@$1 "cat /etc/firewall-*.json 2>/dev/null | grep -A5 trusted"
```

Or check iptables directly:
```bash
ssh root@$1 "iptables -L fpbxtrusted -n 2>/dev/null"
```

## Output
- Confirm the IP was trusted
- Show the current list of trusted IPs
- Show a reminder about cloud firewalls

## Cloud Firewall Reminder
After trusting the IP in FreePBX, remind the user:

> **Note:** If this server is behind a cloud firewall (Linode, Vultr, AWS, etc.), you may also need to allow this IP in the cloud provider's firewall/security group. FreePBX firewall only controls the OS-level firewall (iptables).

## Common Issues
- `fwconsole: command not found` → FreePBX not installed or not in PATH. Try `/var/lib/asterisk/bin/fwconsole`
- Firewall module not enabled → `fwconsole ma install firewall && fwconsole ma enable firewall`
- If trust fails, check if the firewall module is installed: `fwconsole ma list | grep firewall`

---
name: setup-graph-mail
description: Set up Microsoft Graph API voicemail-to-email on a FreePBX server
argument: <server-ip> <tenant-id> <client-id> <client-secret> <sender-email>
disable-model-invocation: true
---

# Setup Microsoft Graph API Voicemail-to-Email

Deploy `graph-sendmail.sh` to a FreePBX server so voicemail notifications are sent
via Microsoft Graph API instead of SMTP. This replaces the default `sendmail` mail
command with a script that authenticates via OAuth2 client credentials.

## Prerequisites

The user must have already:
1. Registered an app in Microsoft Entra (Azure AD)
2. Added **Mail.Send** application permission and granted admin consent
3. Created a client secret
4. Have a real mailbox in their M365 tenant to use as the sender

## Arguments

- `$1` — FreePBX server IP (SSH as root)
- `$2` — Azure Tenant ID
- `$3` — Azure Application (Client) ID
- `$4` — Client Secret value
- `$5` — Sender email address (must be a real M365 mailbox)

## Deployment Steps

All commands run via `ssh root@$1`.

### Step 1: Deploy the script

Copy the `graph-sendmail.sh` script to the server:

```bash
ssh root@$1 "cat > /usr/local/bin/graph-sendmail.sh && chmod +x /usr/local/bin/graph-sendmail.sh" < /path/to/graph-sendmail.sh
```

Or create it inline via SSH. The script should be owned by root with mode 755.

### Step 2: Create the config file

```bash
ssh root@$1 'cat > /etc/asterisk/graph-mail.conf << EOF
TENANT_ID="$2"
CLIENT_ID="$3"
CLIENT_SECRET="$4"
SENDER_EMAIL="$5"
EOF
chmod 600 /etc/asterisk/graph-mail.conf
chown asterisk:asterisk /etc/asterisk/graph-mail.conf'
```

### Step 3: Create the token cache directory

```bash
ssh root@$1 "mkdir -p /var/spool/asterisk/graph-mail && chown asterisk:asterisk /var/spool/asterisk/graph-mail"
```

### Step 4: Set mailcmd in FreePBX

Set the mail command via the FreePBX database so it survives updates:

```bash
ssh root@$1 "mysql -u root asterisk -e \"UPDATE kvstore SET val='/usr/local/bin/graph-sendmail.sh' WHERE \\\`key\\\`='mailcmd';\""
```

If that doesn't work (the kvstore schema varies), check the current mailcmd:

```bash
ssh root@$1 "mysql -u root asterisk -e \"SELECT * FROM kvstore WHERE \\\`key\\\` LIKE '%mailcmd%';\""
```

Alternative: Set it through `voicemail.conf` custom override:

```bash
ssh root@$1 "grep -q 'mailcmd' /etc/asterisk/voicemail_custom.conf 2>/dev/null && sed -i 's|^mailcmd=.*|mailcmd=/usr/local/bin/graph-sendmail.sh|' /etc/asterisk/voicemail_custom.conf || echo 'mailcmd=/usr/local/bin/graph-sendmail.sh' >> /etc/asterisk/voicemail_custom.conf"
```

Then reload:

```bash
ssh root@$1 "fwconsole reload"
```

### Step 5: Verify mailcmd is active

```bash
ssh root@$1 "grep 'mailcmd' /etc/asterisk/voicemail.conf"
```

Expected output:
```
mailcmd=/usr/local/bin/graph-sendmail.sh
```

### Step 6: Test the setup

Test OAuth2 token acquisition:

```bash
ssh root@$1 'source /etc/asterisk/graph-mail.conf && curl -s -X POST "https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token" -d "client_id=${CLIENT_ID}" -d "scope=https%3A%2F%2Fgraph.microsoft.com%2F.default" -d "client_secret=${CLIENT_SECRET}" -d "grant_type=client_credentials" | python3 -c "import sys,json; d=json.load(sys.stdin); print(\"Token OK, expires in\", d.get(\"expires_in\",\"?\"), \"seconds\") if \"access_token\" in d else print(\"FAILED:\", d.get(\"error_description\", d))"'
```

Test sending a real email by piping a minimal MIME message:

```bash
ssh root@$1 'echo -e "From: <SENDER_EMAIL>\nTo: <TEST_RECIPIENT>\nSubject: FreePBX Graph Mail Test\nMIME-Version: 1.0\nContent-Type: text/plain\n\nThis is a test from FreePBX graph-sendmail." | /usr/local/bin/graph-sendmail.sh'
```

Replace `<TEST_RECIPIENT>` with the user's email address.

Check syslog for results:

```bash
ssh root@$1 "grep graph-sendmail /var/log/syslog | tail -5"
```

### Step 7: Test with an actual voicemail

Have someone call an extension and leave a voicemail (or call from the CLI):

```bash
ssh root@$1 "asterisk -rx 'channel originate Local/EXTENSION@from-internal application VoiceMail EXTENSION@default'"
```

Then verify the email arrived and check logs:

```bash
ssh root@$1 "grep graph-sendmail /var/log/syslog | tail -10"
```

## Troubleshooting

### "Config file not found" in syslog
The config file must be at `/etc/asterisk/graph-mail.conf` and readable by the asterisk user.

### OAuth2 token failure
- Verify tenant ID, client ID, and secret are correct
- Ensure the app has **Mail.Send** application permission with admin consent
- Client secrets expire — check the expiry date in Azure

### HTTP 403 from Graph API
- The sender email must be a real mailbox in the M365 tenant
- If using an Application Access Policy, ensure the sender mailbox is allowed

### HTTP 413 or large voicemail failures
- Graph API MIME limit is 4MB. If voicemails exceed this, switch the voicemail
  format from WAV to MP3 in FreePBX Voicemail Admin settings.

### mailcmd not being used
- Verify with: `grep mailcmd /etc/asterisk/voicemail.conf`
- Ensure the voicemail box has an email address configured
- Check: `asterisk -rx "voicemail show users" | grep EXTENSION`
- Debug: `asterisk -rx "core set verbose 5"` then leave a voicemail and watch the CLI

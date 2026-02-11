# FreePBX Toolkit

Claude Code skills and shell scripts for managing FreePBX 17 systems with VoIP.ms trunks and Yealink phones.

## Claude Code Skills

Drop the `skills/` directories into `~/.claude/skills/` to get slash commands in Claude Code.

| Skill | Command | Description |
|-------|---------|-------------|
| [phone-status](skills/phone-status/) | `/phone-status <server-ip>` | Check SIP phone registrations |
| [check-cdr](skills/check-cdr/) | `/check-cdr <server-ip> [filters]` | View recent call detail records |
| [check-ivr](skills/check-ivr/) | `/check-ivr <server-ip>` | View IVR configuration and key mappings |
| [pbx-diagnose](skills/pbx-diagnose/) | `/pbx-diagnose <server-ip>` | Full diagnostic (trunks, NAT, firewall, disk, errors) |
| [firewall-trust](skills/firewall-trust/) | `/firewall-trust <server-ip> [wan-ip]` | Trust an IP in FreePBX firewall |
| [fix-nat](skills/fix-nat/) | `/fix-nat <server-ip>` | Fix direct_media and NAT settings |
| [provision-phone](skills/provision-phone/) | `/provision-phone <server-ip> <phone-ip>` | Provision a Yealink phone |
| [pbx-initialize](skills/pbx-initialize/) | `/pbx-initialize <server-ip>` | Full server initialization/onboarding |

### Installing Skills

```bash
cp -r skills/* ~/.claude/skills/
```

Skills will appear in Claude Code's `/` autocomplete. All skills accept a server IP as the first argument and connect via `ssh root@<server>`.

### Prerequisites

- SSH key auth to your FreePBX server (`ssh-copy-id root@<server-ip>`)
- Claude Code CLI installed

## Shell Scripts

Standalone bash scripts for FreePBX server setup. Run these directly on the server or via SSH.

| Script | Description |
|--------|-------------|
| [stackscript.sh](scripts/stackscript.sh) | Full Linode StackScript: installs FreePBX 17, configures VoIP.ms trunk, creates extensions, sets up 911 |
| [setup-voipms-trunk.sh](scripts/setup-voipms-trunk.sh) | Configure a VoIP.ms PJSIP trunk via direct SQL |
| [create-extensions.sh](scripts/create-extensions.sh) | Bulk-create PJSIP extensions with random passwords |
| [setup-911.sh](scripts/setup-911.sh) | Configure 911 emergency routing with a callback DID |
| [install-all.sh](scripts/install-all.sh) | Quick wrapper to run all setup scripts in order |

### Usage

```bash
# Copy scripts to server
scp scripts/*.sh root@<server-ip>:/root/

# SSH in and run
ssh root@<server-ip>
chmod +x *.sh

# Set up VoIP.ms trunk
./setup-voipms-trunk.sh "subaccount_user" "password" "server.voip.ms"

# Create 10 extensions starting at 200
./create-extensions.sh 200 10 "Company Name"

# Set up 911 routing
./setup-911.sh "5551234567"
```

## Documentation

| Document | Description |
|----------|-------------|
| [Yealink API Reference](docs/yealink-api-reference.md) | REST API for Yealink T54W phones (v86+ firmware) — login, provisioning, config, reboot |

## FreePBX Database Notes

Key schema details for FreePBX 17 (learned the hard way):

- **`sip` table**: Columns are `id`, `keyword`, `data`, `flags` — the value column is `data`, NOT `val`
- **`cdr` table** (in `asteriskcdrdb`): Context column is `dcontext`, NOT `context`
- **Reload check**: `SELECT data FROM admin WHERE variable='need_reload'` — `fwconsole reload --check` doesn't exist
- **Firewall status**: `fwconsole firewall status` is not a valid subcommand — use `fwconsole ma list | grep firewall`
- **API port 83**: May use HTTP, not HTTPS — try HTTP first from localhost

## Architecture

All skills are:
- **Generic** — no hardcoded server IPs; accept target via arguments
- **SSH-based** — all commands run via `ssh root@<server>`
- **Self-documenting** — include exact SQL queries, CLI commands, expected outputs, and troubleshooting

Skills that make changes have `disable-model-invocation: true` (Claude won't run them automatically).

## License

MIT

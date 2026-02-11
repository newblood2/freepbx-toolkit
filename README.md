# FreePBX Toolkit

Claude Code skills and shell scripts for managing FreePBX 17 systems. Works with any SIP trunk provider and Yealink phones.

## Safety

These tools manage **production phone systems** — they modify firewall rules, SIP trunks, phone configs, database records, and 911 routing. A bad command can knock phones offline, lock you out of a server, or break emergency calling.

**Do not run unattended.** Specifically:
- **Do not** use `claude --dangerously-skip-permissions` or Claude Code's auto-accept mode with these skills. Always review each SSH command and SQL query before it executes.
- **Do not** use OpenAI Codex's `--full-auto` / `--yolo` mode or any equivalent that bypasses command approval.
- **Read every command** before approving it. These skills run commands as `root` over SSH — there is no undo for a dropped firewall rule or a bad database UPDATE.
- **Test on a non-production system first** if possible. If not, have a console/out-of-band access method ready in case SSH access is lost.

Skills that make changes (`firewall-trust`, `fix-nat`, `provision-phone`, `pbx-initialize`) have `disable-model-invocation: true` set, which prevents Claude from running them automatically. Do not override this.

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

> **E911 Warning:** The `setup-911.sh` script and `stackscript.sh` create Asterisk dialplan routing for 911 calls, but this alone is **not sufficient** for emergency calling. You **must** separately configure E911 with your VoIP provider and register your physical address. VoIP-based 911 will fail if your internet or trunk is down. Always test after setup and understand the limitations before relying on VoIP for emergency services.

Standalone bash scripts for FreePBX server setup. Run these directly on the server or via SSH.

| Script | Description |
|--------|-------------|
| [stackscript.sh](scripts/stackscript.sh) | Full Linode StackScript: installs FreePBX 17, configures SIP trunk, creates extensions, sets up 911 |
| [setup-sip-trunk.sh](scripts/setup-sip-trunk.sh) | Configure a PJSIP trunk for any SIP provider via direct SQL |
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

# Set up a SIP trunk (works with any provider)
./setup-sip-trunk.sh mytrunk "sip_user" "sip_pass" "sip.provider.com" "My Provider"

# Create 10 extensions starting at 200
./create-extensions.sh 200 10 "Company Name"

# Set up 911 routing (configure E911 with your provider first!)
./setup-911.sh "5551234567" mytrunk
```

### Tested Providers

The trunk scripts use standard PJSIP registration and should work with any SIP trunk provider, including:
- VoIP.ms
- Telnyx
- Flowroute
- Twilio Elastic SIP
- Bandwidth
- Any provider offering standard SIP trunk credentials

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

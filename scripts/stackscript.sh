#!/bin/bash
# FreePBX 17 Complete Production Deployment for Linode
# Version 5.0 - Provider-agnostic SIP trunk support
#
# Works with any SIP trunk provider (VoIP.ms, Telnyx, Flowroute, Twilio, etc.)
#
# Linode StackScript UDF Variables
# <UDF name="client_name" label="Client Company Name" example="Acme Corp" />
# <UDF name="admin_email" label="Admin Email Address" example="admin@example.com" />
# <UDF name="trunk_name" label="Trunk short name (no spaces)" default="trunk1" example="voipms" />
# <UDF name="trunk_display" label="Trunk display name" default="SIP Trunk" example="VoIP.ms" />
# <UDF name="sip_username" label="SIP Auth Username" example="123456_freepbx" />
# <UDF name="sip_password" label="SIP Auth Password" />
# <UDF name="sip_server" label="SIP Server Hostname" example="sip.provider.com" />
# <UDF name="emergency_did" label="Emergency 911 Callback DID (10 digits)" example="5551234567" />
# <UDF name="outbound_cid" label="Outbound Caller ID (10 digits)" example="5551234567" />
# <UDF name="extension_start" label="First Extension Number" default="100" />
# <UDF name="extension_count" label="Number of Extensions to Create" default="10" />
export CLIENT_NAME="${CLIENT_NAME:-Example Corp}"
export TRUNK_NAME="${TRUNK_NAME:-trunk1}"
export TRUNK_DISPLAY="${TRUNK_DISPLAY:-SIP Trunk}"
export SIP_USERNAME="${SIP_USERNAME:-changeme}"
export SIP_PASSWORD="${SIP_PASSWORD:-changeme}"
export SIP_SERVER="${SIP_SERVER:-sip.provider.com}"
export EMERGENCY_DID="${EMERGENCY_DID:-5551234567}"
export OUTBOUND_CID="${OUTBOUND_CID:-5551234567}"
export EXTENSION_START="${EXTENSION_START:-200}"
export EXTENSION_COUNT="${EXTENSION_COUNT:-10}"

# Error handling - only exit on critical errors
set -o pipefail

# Setup logging
exec > >(tee -a /var/log/freepbx-stackscript.log)
exec 2>&1

echo "=========================================="
echo "FreePBX 17 Deployment: ${CLIENT_NAME}"
echo "Started: $(date)"
echo "=========================================="

#############################################
# PHASE 1: System Preparation
#############################################
echo ""
echo "==> PHASE 1: System Preparation"

export DEBIAN_FRONTEND=noninteractive

# Update system
echo "Updating system packages..."
apt-get update || { echo "WARNING: apt-get update had issues"; }
apt-get upgrade -y || { echo "WARNING: apt-get upgrade had issues"; }

# Install prerequisites
echo "Installing prerequisites..."
apt-get install -y wget curl git net-tools python3

# Set hostname with proper error handling
echo "Setting hostname..."
SANITIZED_HOSTNAME=$(echo "${CLIENT_NAME}" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g')
NEW_HOSTNAME="${SANITIZED_HOSTNAME}-pbx"

echo "Sanitized hostname will be: ${NEW_HOSTNAME}"

# Use hostnamectl with explicit set-hostname subcommand
if hostnamectl set-hostname "${NEW_HOSTNAME}" 2>/dev/null; then
    echo "Hostname set successfully to: $(hostname)"
else
    echo "WARNING: hostnamectl failed, trying alternative method..."
    # Fallback to traditional method
    echo "${NEW_HOSTNAME}" > /etc/hostname
    hostname "${NEW_HOSTNAME}"
    echo "Hostname set via /etc/hostname: $(hostname)"
fi

echo "Phase 1 complete"

#############################################
# PHASE 2: FreePBX 17 Installation
#############################################
echo ""
echo "==> PHASE 2: FreePBX 17 Installation"
echo "This will take 30-60 minutes..."

cd /tmp

# Download official FreePBX 17 installation script
echo "Downloading FreePBX 17 installation script..."
rm -f sng_freepbx_debian_install.sh
wget https://github.com/FreePBX/sng_freepbx_debian_install/raw/master/sng_freepbx_debian_install.sh

if [ ! -f sng_freepbx_debian_install.sh ]; then
    echo "ERROR: Failed to download FreePBX installation script!"
    exit 1
fi

# Execute installation
echo ""
echo "========================================================"
echo "STARTING FREEPBX INSTALLATION"
echo "This will take 30-60 minutes - BE PATIENT"
echo "========================================================"
echo ""

bash sng_freepbx_debian_install.sh --opensourceonly 2>&1 | tee /var/log/freepbx-install.log

INSTALL_EXIT_CODE=${PIPESTATUS[0]}

if [ $INSTALL_EXIT_CODE -ne 0 ]; then
    echo "WARNING: FreePBX installation script exited with code $INSTALL_EXIT_CODE"
    echo "This is sometimes normal - checking if FreePBX was actually installed..."
fi

# Wait for services to stabilize
echo "Waiting for services to stabilize..."
sleep 30

# Verify installation
if ! command -v fwconsole &> /dev/null; then
    echo "ERROR: FreePBX installation failed - fwconsole not found"
    echo ""
    echo "Last 100 lines of installation log:"
    tail -100 /var/log/freepbx-install.log
    exit 1
fi

echo "FreePBX installation verified successfully"

# Ensure services are running
echo "Starting/verifying services..."
systemctl start asterisk 2>/dev/null || true
systemctl enable asterisk 2>/dev/null || true
systemctl start freepbx 2>/dev/null || true
sleep 15

if systemctl is-active --quiet asterisk; then
    echo "Asterisk is running"
else
    echo "WARNING: Asterisk may not be running yet, continuing..."
fi

echo "Phase 2 complete"

#############################################
# PHASE 3: Install ionCube Loader
#############################################
echo ""
echo "==> PHASE 3: Installing ionCube Loader"

PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null || echo "8.2")
PHP_EXT_DIR=$(php -i 2>/dev/null | grep "^extension_dir" | awk '{print $3}' | tr -d "'" || echo "/usr/lib/php/20220829")

echo "PHP Version: $PHP_VERSION"
echo "PHP Extension Directory: $PHP_EXT_DIR"

cd /tmp
rm -rf ioncube*
wget -q https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz || {
    echo "WARNING: Failed to download ionCube loader, skipping..."
}

if [ -f ioncube_loaders_lin_x86-64.tar.gz ]; then
    tar xzf ioncube_loaders_lin_x86-64.tar.gz

    if [ -f "ioncube/ioncube_loader_lin_${PHP_VERSION}.so" ]; then
        cp "ioncube/ioncube_loader_lin_${PHP_VERSION}.so" "$PHP_EXT_DIR/" 2>/dev/null || true
        echo "zend_extension = ${PHP_EXT_DIR}/ioncube_loader_lin_${PHP_VERSION}.so" > "/etc/php/${PHP_VERSION}/apache2/conf.d/00-ioncube.ini" 2>/dev/null || true
        echo "zend_extension = ${PHP_EXT_DIR}/ioncube_loader_lin_${PHP_VERSION}.so" > "/etc/php/${PHP_VERSION}/cli/conf.d/00-ioncube.ini" 2>/dev/null || true
        echo "ionCube Loader installed successfully"
    else
        echo "WARNING: ionCube loader for PHP ${PHP_VERSION} not found"
    fi
fi

echo "Phase 3 complete"

#############################################
# PHASE 4: Apache/PHP Configuration
#############################################
echo ""
echo "==> PHASE 4: Configuring Apache and PHP"

# Configure PHP sessions
mkdir -p /var/lib/php/sessions
chown -R www-data:www-data /var/lib/php/sessions 2>/dev/null || true
chmod 1733 /var/lib/php/sessions 2>/dev/null || true

# Add www-data to asterisk group
usermod -a -G asterisk www-data 2>/dev/null || true

# Enable .htaccess support for FreePBX
cat > /etc/apache2/conf-available/freepbx-htaccess.conf << 'HTCONF'
<Directory /var/www/html/admin>
    AllowOverride All
    Require all granted
</Directory>
HTCONF

a2enconf freepbx-htaccess 2>/dev/null || true
a2enmod rewrite 2>/dev/null || true
systemctl restart apache2

echo "Apache and PHP configured"
echo "Phase 4 complete"

#############################################
# PHASE 5: Install Essential FreePBX Modules
#############################################
echo ""
echo "==> PHASE 5: Installing FreePBX Modules"

fwconsole ma downloadinstall framework core 2>&1 | grep -v "Undefined" || true
sleep 5

echo "Phase 5 complete"

#############################################
# PHASE 6: VoIP.ms Trunk Configuration
#############################################
echo ""
echo "==> PHASE 6: Configuring PJSIP Trunk (${TRUNK_DISPLAY})"

# Create SIP trunk via PJSIP custom configuration
cat > /etc/asterisk/pjsip_custom.conf << EOF
; ========================================
; PJSIP Trunk Configuration: ${TRUNK_DISPLAY}
; Client: ${CLIENT_NAME}
; Created: $(date)
; ========================================

[transport-udp]
type = transport
protocol = udp
bind = 0.0.0.0

; Registration
[${TRUNK_NAME}-reg]
type = registration
transport = transport-udp
outbound_auth = ${TRUNK_NAME}-auth
client_uri = sip:${SIP_USERNAME}@${SIP_SERVER}:5060
server_uri = sip:${SIP_SERVER}:5060
expiration = 180
retry_interval = 60
contact_user = ${SIP_USERNAME}

; Authentication
[${TRUNK_NAME}-auth]
type = auth
auth_type = userpass
username = ${SIP_USERNAME}
password = ${SIP_PASSWORD}

; Address of Record
[${TRUNK_NAME}-aor]
type = aor
contact = sip:${SIP_SERVER}:5060
qualify_frequency = 0

; Endpoint
[${TRUNK_NAME}]
type = endpoint
transport = transport-udp
context = from-trunk
disallow = all
allow = ulaw
allow = alaw
allow = g729
from_user = ${SIP_USERNAME}
auth = ${TRUNK_NAME}-auth
outbound_auth = ${TRUNK_NAME}-auth
aors = ${TRUNK_NAME}-aor
rtp_symmetric = yes
rewrite_contact = yes
send_rpid = yes
trust_id_inbound = yes
direct_media = no

; Identify incoming calls
[${TRUNK_NAME}-identify]
type = identify
endpoint = ${TRUNK_NAME}
match = ${SIP_SERVER}
EOF

# Set proper permissions
chown asterisk:asterisk /etc/asterisk/pjsip_custom.conf 2>/dev/null || true
chmod 640 /etc/asterisk/pjsip_custom.conf

echo "SIP trunk configuration created (${TRUNK_DISPLAY})"
echo "Phase 6 complete"

#############################################
# PHASE 7: Extension Creation
#############################################
echo ""
echo "==> PHASE 7: Creating Extensions"
echo "Creating ${EXTENSION_COUNT} extensions starting at ${EXTENSION_START}"

# Create PHP script for extension creation
cat > /tmp/create_extensions.php << 'PHPEOF'
#!/usr/bin/env php
<?php
// Disable authentication for CLI execution
$bootstrap_settings = array();
$bootstrap_settings['freepbx_auth'] = false;

// Load FreePBX framework
if (!@include_once(getenv('FREEPBX_CONF') ? getenv('FREEPBX_CONF') : '/etc/freepbx.conf')) {
    include_once('/etc/asterisk/freepbx.conf');
}

// Get parameters from command line
$start = intval($argv[1]);
$count = intval($argv[2]);
$emergency_did = $argv[3];
$client_name = $argv[4];

$created_extensions = array();

for ($i = 0; $i < $count; $i++) {
    $extension = $start + $i;
    $name = "Extension $extension";
    $secret = bin2hex(random_bytes(12));

    $vars = array(
        "extension" => $extension,
        "name" => $name,
        "cidnum" => $extension,
        "devinfo_secret" => $secret,
        "devinfo_dtmfmode" => "rfc2833",
        "devinfo_context" => "from-internal",
        "devinfo_emergency_cid" => $emergency_did,
    );

    core_users_add($vars);
    core_devices_add($extension, 'pjsip', "PJSIP/$extension", 'fixed', $extension, "$name - $client_name", $emergency_did);

    $created_extensions[] = array(
        'extension' => $extension,
        'secret' => $secret
    );

    echo "Created extension $extension\n";
}

needreload();

echo "\n### CREDENTIALS_JSON ###\n";
echo json_encode($created_extensions);
echo "\n### END_CREDENTIALS ###\n";
?>
PHPEOF

chmod +x /tmp/create_extensions.php

# Execute extension creation script
echo "Creating extensions using FreePBX PHP Bootstrap..."
EXTENSION_OUTPUT=$(/tmp/create_extensions.php "$EXTENSION_START" "$EXTENSION_COUNT" "$EMERGENCY_DID" "$CLIENT_NAME" 2>&1) || {
    echo "WARNING: Extension creation had some errors, but may have succeeded"
}
echo "$EXTENSION_OUTPUT"

# Extract and store credentials
CREDENTIALS=$(echo "$EXTENSION_OUTPUT" | sed -n '/### CREDENTIALS_JSON ###/,/### END_CREDENTIALS ###/p' | grep -v '###')
echo "$CREDENTIALS" > /root/extension_credentials.json

echo "Phase 7 complete"

#############################################
# PHASE 8: Outbound Route & Dialplan Configuration
#############################################
echo ""
echo "==> PHASE 8: Configuring Outbound Routes and Dialplan"

# Create custom dialplan
cat > /etc/asterisk/extensions_custom.conf << EOF
; ========================================
; Custom Dialplan Configuration
; Client: ${CLIENT_NAME}
; Created: $(date)
; ========================================

[from-internal-custom]
; Emergency 911 routing
exten => 911,1,NoOp(Emergency 911 Call)
 same => n,Set(CALLERID(num)=${EMERGENCY_DID})
 same => n,Set(CALLERID(name)=Emergency)
 same => n,Dial(PJSIP/911@${TRUNK_NAME},300)
 same => n,Hangup()

exten => 9911,1,Goto(911,1)

; North American long distance (1+10 digits)
exten => _1NXXNXXXXXX,1,NoOp(Outbound: \${EXTEN})
 same => n,Set(CALLERID(num)=${OUTBOUND_CID})
 same => n,Dial(PJSIP/\${EXTEN}@${TRUNK_NAME})
 same => n,Hangup()

; North American local (10 digits)
exten => _NXXNXXXXXX,1,NoOp(Local: \${EXTEN})
 same => n,Set(CALLERID(num)=${OUTBOUND_CID})
 same => n,Dial(PJSIP/1\${EXTEN}@${TRUNK_NAME})
 same => n,Hangup()

; 7-digit local
exten => _NXXXXXX,1,NoOp(7-digit: \${EXTEN})
 same => n,Set(CALLERID(num)=${OUTBOUND_CID})
 same => n,Dial(PJSIP/\${EXTEN}@${TRUNK_NAME})
 same => n,Hangup()

; International (011+)
exten => _011.,1,NoOp(International: \${EXTEN})
 same => n,Set(CALLERID(num)=${OUTBOUND_CID})
 same => n,Dial(PJSIP/\${EXTEN}@${TRUNK_NAME})
 same => n,Hangup()

; Test numbers (VoIP.ms: 4747=DTMF, 4443=echo; adjust for your provider)
exten => 4747,1,Dial(PJSIP/4747@${TRUNK_NAME})
exten => 4443,1,Dial(PJSIP/4443@${TRUNK_NAME})
EOF

chown asterisk:asterisk /etc/asterisk/extensions_custom.conf 2>/dev/null || true
chmod 640 /etc/asterisk/extensions_custom.conf

echo "Dialplan configured"
echo "Phase 8 complete"

#############################################
# PHASE 9: Apply Configuration
#############################################
echo ""
echo "==> PHASE 9: Applying Configuration"

echo "Fixing file permissions..."
fwconsole chown 2>&1 | grep -v "Undefined" || true

echo "Reloading FreePBX configuration..."
fwconsole reload 2>&1 | grep -v "Undefined" || true

sleep 10

echo "Reloading Asterisk modules..."
asterisk -rx "module reload res_pjsip.so" 2>&1 || true
asterisk -rx "module reload res_pjsip_outbound_registration.so" 2>&1 || true
asterisk -rx "dialplan reload" 2>&1 || true

echo "Waiting for trunk registration..."
sleep 15

echo "Phase 9 complete"

#############################################
# PHASE 10: Final Output
#############################################
echo ""
echo "==> PHASE 10: Verification and Final Output"

PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || echo "Unable to determine")

echo ""
echo "=========================================="
echo "DEPLOYMENT COMPLETE!"
echo "=========================================="
echo ""
echo "CLIENT: ${CLIENT_NAME}"
echo "PUBLIC IP: $PUBLIC_IP"
echo "FREEPBX URL: http://${PUBLIC_IP}/admin"
echo ""
echo "TRUNK REGISTRATION STATUS:"
asterisk -rx "pjsip show registrations" 2>&1 || echo "Check manually after startup"
echo ""
echo "PJSIP ENDPOINTS (first 20):"
asterisk -rx "pjsip show endpoints" 2>&1 | head -20 || echo "Check manually"
echo ""
echo "=========================================="
echo "EXTENSION CREDENTIALS:"
echo "=========================================="

# Display credentials
if [ -f /root/extension_credentials.json ]; then
    python3 << 'PYEOF'
import json
try:
    with open('/root/extension_credentials.json', 'r') as f:
        creds = json.load(f)
    print("\nExtension | Password")
    print("----------|" + "-" * 24)
    for ext in creds:
        print(f"{ext['extension']:>9} | {ext['secret']}")
    print("\n** Credentials saved to: /root/extension_credentials.json **")
except:
    print("Error reading credentials file")
PYEOF
else
    echo "ERROR: Credentials file not found!"
fi

echo ""
echo "=========================================="
echo "NEXT STEPS:"
echo "1. Access: http://${PUBLIC_IP}/admin"
echo "2. Create admin account"
echo "3. Configure phones with extension credentials above"
echo "4. Test: Dial 4443 (echo test) or 4747 (DTMF test)"
echo "=========================================="
echo ""
echo "Completed: $(date)"
echo "Installation log: /var/log/freepbx-stackscript.log"
echo ""

exit 0

#!/bin/bash
# setup-sip-trunk.sh - Configure a PJSIP trunk for any SIP provider
# Usage: ./setup-sip-trunk.sh <trunk-name> <username> <password> <server> [display-name]
#
# Examples:
#   ./setup-sip-trunk.sh voipms 123456_main secretpass atlanta.voip.ms "VoIP.ms"
#   ./setup-sip-trunk.sh telnyx user123 secretpass sip.telnyx.com "Telnyx"
#   ./setup-sip-trunk.sh flowroute tech123 secretpass us-west-or.sip.flowroute.com "Flowroute"
#   ./setup-sip-trunk.sh twilio user123 secretpass pstn.twilio.com "Twilio"

TRUNK_NAME="$1"
SIP_USER="$2"
SIP_PASS="$3"
SIP_SERVER="$4"
DISPLAY_NAME="${5:-$TRUNK_NAME}"

if [ -z "$TRUNK_NAME" ] || [ -z "$SIP_USER" ] || [ -z "$SIP_PASS" ] || [ -z "$SIP_SERVER" ]; then
    echo "Usage: $0 <trunk-name> <username> <password> <server> [display-name]"
    echo ""
    echo "  trunk-name    Short name for the trunk (e.g., voipms, telnyx, flowroute)"
    echo "  username      SIP authentication username"
    echo "  password      SIP authentication password"
    echo "  server        SIP server hostname (e.g., atlanta.voip.ms)"
    echo "  display-name  Optional friendly name (defaults to trunk-name)"
    exit 1
fi

echo "=== Configuring SIP Trunk: $DISPLAY_NAME ==="
echo "Trunk ID: $TRUNK_NAME"
echo "Username: $SIP_USER"
echo "Server: $SIP_SERVER"
echo ""

# Remove existing configuration for this trunk
echo "Cleaning up any existing configuration..."
mysql -u root asterisk << EOF
DELETE FROM pjsip WHERE id LIKE '${TRUNK_NAME}%';
DELETE FROM trunks WHERE name='${DISPLAY_NAME}';
EOF

echo "Creating trunk configuration..."
mysql -u root asterisk << EOF
-- Create trunk
INSERT INTO trunks (name, tech, channelid, outcid, usercontext, provider, \`continue\`, disabled)
VALUES ('${DISPLAY_NAME}', 'pjsip', 'PJSIP/${TRUNK_NAME}', '', 'from-pstn', '${DISPLAY_NAME}', 'off', 'off');

SET @trunkid = LAST_INSERT_ID();

-- PJSIP Endpoint
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('${TRUNK_NAME}', 'type', 'endpoint', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('${TRUNK_NAME}', 'context', 'from-pstn', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('${TRUNK_NAME}', 'disallow', 'all', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('${TRUNK_NAME}', 'allow', 'ulaw,alaw,g729', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('${TRUNK_NAME}', 'dtmf_mode', 'rfc4733', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('${TRUNK_NAME}', 'rtp_symmetric', 'yes', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('${TRUNK_NAME}', 'force_rport', 'yes', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('${TRUNK_NAME}', 'rewrite_contact', 'yes', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('${TRUNK_NAME}', 'ice_support', 'no', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('${TRUNK_NAME}', 'direct_media', 'no', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('${TRUNK_NAME}', 'send_rpid', 'yes', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('${TRUNK_NAME}', 'outbound_auth', '${TRUNK_NAME}-auth', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('${TRUNK_NAME}', 'aors', '${TRUNK_NAME}-aor', 2);

-- PJSIP Auth
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('${TRUNK_NAME}-auth', 'type', 'auth', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('${TRUNK_NAME}-auth', 'auth_type', 'userpass', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('${TRUNK_NAME}-auth', 'username', '${SIP_USER}', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('${TRUNK_NAME}-auth', 'password', '${SIP_PASS}', 2);

-- PJSIP Registration
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('${TRUNK_NAME}-reg', 'type', 'registration', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('${TRUNK_NAME}-reg', 'transport', 'transport-udp', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('${TRUNK_NAME}-reg', 'outbound_auth', '${TRUNK_NAME}-auth', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('${TRUNK_NAME}-reg', 'server_uri', 'sip:${SIP_SERVER}', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('${TRUNK_NAME}-reg', 'client_uri', 'sip:${SIP_USER}@${SIP_SERVER}', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('${TRUNK_NAME}-reg', 'contact_user', '${SIP_USER}', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('${TRUNK_NAME}-reg', 'retry_interval', '60', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('${TRUNK_NAME}-reg', 'expiration', '3600', 2);

-- PJSIP AOR
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('${TRUNK_NAME}-aor', 'type', 'aor', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('${TRUNK_NAME}-aor', 'contact', 'sip:${SIP_USER}@${SIP_SERVER}', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('${TRUNK_NAME}-aor', 'qualify_frequency', '60', 2);

-- PJSIP Identify
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('${TRUNK_NAME}-identify', 'type', 'identify', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('${TRUNK_NAME}-identify', 'endpoint', '${TRUNK_NAME}', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('${TRUNK_NAME}-identify', 'match', '${SIP_SERVER}', 2);

-- Create outbound route
INSERT INTO outbound_routes (name, outcid, outcid_mode, password, seq)
VALUES ('${DISPLAY_NAME}-Route', '', 'inband', '', 0);

SET @route_id = LAST_INSERT_ID();

-- Add North American dial patterns
INSERT INTO outbound_route_patterns (route_id, match_pattern_prefix, match_pattern_pass, prepend_digits) VALUES
(@route_id, '', 'NXXNXXXXXX', '1'),
(@route_id, '', '1NXXNXXXXXX', ''),
(@route_id, '', 'NXXXXXX', ''),
(@route_id, '', '011.', '');

-- Link trunk to route
INSERT INTO outbound_route_trunks (route_id, trunk_id, seq)
VALUES (@route_id, @trunkid, 0);
EOF

echo ""
echo "Reloading FreePBX..."
fwconsole reload

sleep 5

echo ""
echo "=== Registration Status ==="
asterisk -rx "pjsip show registrations"

echo ""
echo "=== Endpoint Check ==="
asterisk -rx "pjsip show endpoints" | grep -A2 "${TRUNK_NAME}"

echo ""
echo "Done! Trunk '${DISPLAY_NAME}' configured."
echo "Check GUI: Connectivity > Trunks > ${DISPLAY_NAME}"

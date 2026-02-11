#!/bin/bash
# setup-voipms-trunk-final.sh

VOIPMS_USER="$1"
VOIPMS_PASS="$2"
VOIPMS_SERVER="${3:-atlanta.voip.ms}"

if [ -z "$VOIPMS_USER" ] || [ -z "$VOIPMS_PASS" ]; then
    echo "Usage: $0 <username> <password> [server]"
    exit 1
fi

echo "=== Configuring VoIP.ms Trunk ==="
echo "Username: $VOIPMS_USER"
echo "Server: $VOIPMS_SERVER"
echo ""

# Completely remove existing configuration
echo "Cleaning up any existing configuration..."
mysql -u root asterisk << EOF
DELETE FROM pjsip WHERE id LIKE 'voipms%';
DELETE FROM trunks WHERE name='VoIPms';
DELETE FROM outbound_routes WHERE name='VoIPms-Main';
DELETE FROM outbound_route_patterns WHERE route_id IN (SELECT route_id FROM outbound_routes WHERE name='VoIPms-Main');
DELETE FROM outbound_route_trunks WHERE route_id IN (SELECT route_id FROM outbound_routes WHERE name='VoIPms-Main');
EOF

echo "Creating trunk configuration..."
mysql -u root asterisk << EOF
-- Create trunk
INSERT INTO trunks (name, tech, channelid, outcid, usercontext, provider, \`continue\`, disabled) 
VALUES ('VoIPms', 'pjsip', 'PJSIP/voipms', '', 'from-pstn', 'VoIP.ms', 'off', 'off');

SET @trunkid = LAST_INSERT_ID();

-- PJSIP Endpoint (comma-separated codecs in single allow entry)
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('voipms', 'type', 'endpoint', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('voipms', 'context', 'from-pstn', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('voipms', 'disallow', 'all', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('voipms', 'allow', 'ulaw,alaw,g729', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('voipms', 'dtmf_mode', 'rfc4733', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('voipms', 'rtp_symmetric', 'yes', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('voipms', 'force_rport', 'yes', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('voipms', 'rewrite_contact', 'yes', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('voipms', 'ice_support', 'no', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('voipms', 'direct_media', 'no', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('voipms', 'send_rpid', 'yes', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('voipms', 'outbound_auth', 'voipms-auth', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('voipms', 'aors', 'voipms-aor', 2);

-- PJSIP Auth
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('voipms-auth', 'type', 'auth', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('voipms-auth', 'auth_type', 'userpass', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('voipms-auth', 'username', '$VOIPMS_USER', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('voipms-auth', 'password', '$VOIPMS_PASS', 2);

-- PJSIP Registration
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('voipms-reg', 'type', 'registration', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('voipms-reg', 'transport', 'transport-udp', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('voipms-reg', 'outbound_auth', 'voipms-auth', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('voipms-reg', 'server_uri', 'sip:$VOIPMS_SERVER', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('voipms-reg', 'client_uri', 'sip:$VOIPMS_USER@$VOIPMS_SERVER', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('voipms-reg', 'contact_user', '$VOIPMS_USER', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('voipms-reg', 'retry_interval', '60', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('voipms-reg', 'expiration', '3600', 2);

-- PJSIP AOR
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('voipms-aor', 'type', 'aor', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('voipms-aor', 'contact', 'sip:$VOIPMS_USER@$VOIPMS_SERVER', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('voipms-aor', 'qualify_frequency', '60', 2);

-- PJSIP Identify
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('voipms-identify', 'type', 'identify', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('voipms-identify', 'endpoint', 'voipms', 2);
INSERT INTO pjsip (id, keyword, data, flags) VALUES ('voipms-identify', 'match', '$VOIPMS_SERVER', 2);

-- Create outbound route
INSERT INTO outbound_routes (name, outcid, outcid_mode, password, seq) 
VALUES ('VoIPms-Main', '', 'inband', '', 0);

SET @route_id = LAST_INSERT_ID();

-- Add dial patterns
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
echo "=== Auth Check ==="
asterisk -rx "pjsip show auths"

echo ""
echo "=== Endpoint Check ==="
asterisk -rx "pjsip show endpoints"

echo ""
echo "✓ Configuration complete!"
echo "Check GUI: Connectivity → Trunks → VoIPms"
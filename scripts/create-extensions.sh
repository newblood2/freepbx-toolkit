#!/bin/bash
# create-extensions.sh
# Usage: ./create-extensions.sh START_NUM COUNT [CLIENT_NAME]

START="${1:-100}"
COUNT="${2:-10}"
CLIENT_NAME="${3:-Client}"

echo "Creating $COUNT extensions starting at $START for $CLIENT_NAME..."

for i in $(seq 0 $((COUNT - 1))); do
    EXT=$((START + i))
    echo "Creating extension $EXT..."
    
    mysql -u root asterisk << EOF
-- Create extension device
INSERT INTO devices (id, tech, dial, devicetype, user, description, emergency_cid) 
VALUES ('$EXT', 'pjsip', '$EXT', 'fixed', '$EXT', 'Extension $EXT - $CLIENT_NAME', '')
ON DUPLICATE KEY UPDATE description='Extension $EXT - $CLIENT_NAME';

-- Create user
INSERT INTO users (extension, name, voicemail, ringtimer, noanswer, recording, outboundcid, sipname) 
VALUES ('$EXT', 'User $EXT', 'default', '0', '', '', '', '$EXT')
ON DUPLICATE KEY UPDATE name='User $EXT';

-- PJSIP settings for extension
DELETE FROM pjsip WHERE id='$EXT';
INSERT INTO pjsip (id, keyword, data, flags) VALUES
('$EXT', 'type', 'endpoint', 0),
('$EXT', 'context', 'from-internal', 0),
('$EXT', 'disallow', 'all', 0),
('$EXT', 'allow', 'ulaw', 0),
('$EXT', 'allow', 'alaw', 0),
('$EXT', 'auth', '$EXT', 0),
('$EXT', 'aors', '$EXT', 0),
('$EXT', 'direct_media', 'no', 0),
('$EXT', 'mailboxes', '$EXT@device', 0),
('$EXT', 'callerid', 'Extension $EXT <$EXT>', 0);

-- PJSIP Auth
INSERT INTO pjsip (id, keyword, data, flags) VALUES
('${EXT}-auth', 'type', 'auth', 0),
('${EXT}-auth', 'auth_type', 'userpass', 0),
('${EXT}-auth', 'username', '$EXT', 0),
('${EXT}-auth', 'password', '$(openssl rand -base64 12)', 0);

-- PJSIP AOR
INSERT INTO pjsip (id, keyword, data, flags) VALUES
('${EXT}-aor', 'type', 'aor', 0),
('${EXT}-aor', 'max_contacts', '1', 0),
('${EXT}-aor', 'qualify_frequency', '60', 0);
EOF
done

fwconsole reload

echo ""
echo "✓ Created extensions $START through $((START + COUNT - 1))"
echo "Default passwords are random - retrieve them from GUI"
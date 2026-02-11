#!/bin/bash
# setup-911.sh
# Usage: ./setup-911.sh EMERGENCY_DID

EMERGENCY_DID="$1"

if [ -z "$EMERGENCY_DID" ]; then
    echo "Usage: $0 <emergency_did>"
    echo "Example: $0 5551234567"
    exit 1
fi

echo "Configuring 911 emergency routing with DID: $EMERGENCY_DID"

# Create custom dialplan for 911
cat > /etc/asterisk/extensions_override_freepbx.conf << EOF
[from-internal-custom]
; Emergency 911 routing
exten => 911,1,NoOp(Emergency 911 Call)
 same => n,Set(CALLERID(num)=$EMERGENCY_DID)
 same => n,Set(CALLERID(name)=Emergency)
 same => n,Dial(PJSIP/911@voipms,300)
 same => n,Hangup()

; Also catch 9-911 (in case users dial 9 for outside line)
exten => 9911,1,Goto(911,1)
EOF

# Reload dialplan
asterisk -rx "dialplan reload"

echo ""
echo "✓ 911 routing configured!"
echo "Calls to 911 will show caller ID: $EMERGENCY_DID"
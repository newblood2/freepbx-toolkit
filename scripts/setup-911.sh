#!/bin/bash
# setup-911.sh - Configure emergency 911 routing
# Usage: ./setup-911.sh <emergency-did> [trunk-name]
#
# WARNING: This script ONLY creates Asterisk dialplan routing for 911.
# It does NOT configure E911 with your VoIP provider.
#
# BEFORE using this script, you MUST:
#   1. Configure E911 service with your VoIP provider's portal
#   2. Register the physical address of your PBX location with the provider
#   3. Verify your provider supports 911 calling on your trunk
#   4. TEST emergency routing after setup (use provider's test numbers first)
#
# VoIP-based 911 has limitations:
#   - If your internet or trunk is down, 911 calls will FAIL
#   - If E911 is not configured, dispatchers won't know your location
#   - This is NOT a substitute for proper E911 compliance
#
# NOTE: This script OVERWRITES extensions_override_freepbx.conf.
# If you have existing custom dialplan in that file, merge manually instead.

EMERGENCY_DID="$1"
TRUNK_NAME="${2:-trunk1}"

if [ -z "$EMERGENCY_DID" ]; then
    echo "Usage: $0 <emergency-did> [trunk-name]"
    echo ""
    echo "  emergency-did  Your E911 callback DID (10 digits)"
    echo "  trunk-name     PJSIP trunk name to route 911 through (default: trunk1)"
    echo ""
    echo "Example: $0 5551234567 voipms"
    echo ""
    echo "WARNING: You must also configure E911 with your VoIP provider."
    echo "This script only creates the Asterisk dialplan routing."
    exit 1
fi

echo "Configuring 911 emergency routing"
echo "  Callback DID: $EMERGENCY_DID"
echo "  Trunk: $TRUNK_NAME"
echo ""
echo "WARNING: Ensure E911 is configured with your VoIP provider before relying on this."

# Create custom dialplan for 911
cat > /etc/asterisk/extensions_override_freepbx.conf << EOF
[from-internal-custom]
; Emergency 911 routing via ${TRUNK_NAME}
exten => 911,1,NoOp(Emergency 911 Call)
 same => n,Set(CALLERID(num)=$EMERGENCY_DID)
 same => n,Set(CALLERID(name)=Emergency)
 same => n,Dial(PJSIP/911@${TRUNK_NAME},300)
 same => n,Hangup()

; Also catch 9-911 (in case users dial 9 for outside line)
exten => 9911,1,Goto(911,1)
EOF

# Reload dialplan
asterisk -rx "dialplan reload"

echo ""
echo "911 routing configured via trunk: $TRUNK_NAME"
echo "Calls to 911 will show caller ID: $EMERGENCY_DID"
echo ""
echo "IMPORTANT: Test this routing before relying on it for emergencies."

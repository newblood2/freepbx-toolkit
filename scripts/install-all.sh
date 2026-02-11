#!/bin/bash
# Quick setup script - run on the FreePBX server after SSH'ing in
# Usage: Copy scripts to server, then run this

# Make executable
chmod +x setup-voipms-trunk.sh create-extensions.sh setup-911.sh

# Configure VoIP.ms trunk
# Replace with your actual VoIP.ms sub-account credentials
./setup-voipms-trunk.sh "YOUR_VOIPMS_USERNAME" "YOUR_VOIPMS_PASSWORD" "YOUR_VOIPMS_SERVER.voip.ms"

# Create extensions (starting number, count, client name)
./create-extensions.sh 200 10 "Your Company"

# Setup 911 routing with your emergency callback DID
./setup-911.sh "5551234567"

echo "All done!"

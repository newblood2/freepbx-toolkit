#!/bin/bash
# Quick setup script - run on the FreePBX server after SSH'ing in
# Usage: Copy scripts to server, then edit the variables below and run this

# ============================================
# EDIT THESE VARIABLES FOR YOUR DEPLOYMENT
# ============================================
TRUNK_NAME="trunk1"                        # Short name, no spaces (e.g., voipms, telnyx)
SIP_USERNAME="your_sip_username"           # SIP auth username from your provider
SIP_PASSWORD="your_sip_password"           # SIP auth password
SIP_SERVER="sip.yourprovider.com"          # SIP server hostname
TRUNK_DISPLAY="My SIP Trunk"              # Friendly display name
EMERGENCY_DID="5551234567"                 # Your E911 callback DID
EXTENSION_START=200                        # First extension number
EXTENSION_COUNT=10                         # How many extensions to create
COMPANY_NAME="Your Company"                # Company name for extension labels
# ============================================

# Make executable
chmod +x setup-sip-trunk.sh create-extensions.sh setup-911.sh

# Configure SIP trunk (works with any provider)
./setup-sip-trunk.sh "$TRUNK_NAME" "$SIP_USERNAME" "$SIP_PASSWORD" "$SIP_SERVER" "$TRUNK_DISPLAY"

# Create extensions
./create-extensions.sh "$EXTENSION_START" "$EXTENSION_COUNT" "$COMPANY_NAME"

# Setup 911 routing (IMPORTANT: configure E911 with your provider first!)
./setup-911.sh "$EMERGENCY_DID" "$TRUNK_NAME"

echo "All done!"

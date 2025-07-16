#!/bin/bash
# hooks/stop-handler.sh - Simple stop hook handler
#
# Purpose: Handle stop events without errors
# This is a minimal handler that just logs and exits cleanly

# Read payload but don't process it
cat > /dev/null

# Always exit successfully
exit 0
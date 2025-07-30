#!/bin/bash
# After creating the repository on GitHub, run this script with your username
# Usage: ./setup-github-remote.sh <your-github-username>

if [ $# -eq 0 ]; then
    echo "Usage: $0 <your-github-username>"
    echo "Example: $0 johnfabienke"
    exit 1
fi

USERNAME=$1
REPO_NAME="NeXTRust"

echo "Setting up GitHub remote for $USERNAME/$REPO_NAME..."

# Add the remote using SSH
git remote add origin "git@github.com:$USERNAME/$REPO_NAME.git"

# Verify the remote was added
echo "Remote added:"
git remote -v

echo ""
echo "To push your code to GitHub, run:"
echo "git push -u origin main"
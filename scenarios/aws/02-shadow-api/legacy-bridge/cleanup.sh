#!/bin/bash

# legacy-bridge Cleanup Script
# Removes terraform state files, backups, and cached data

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"

echo "[*] Cleaning up terraform state and cache files..."

# Remove terraform state files
if [ -f "$TF_DIR/terraform.tfstate" ]; then
    echo "[+] Removing terraform.tfstate"
    rm -f "$TF_DIR/terraform.tfstate"
fi

# Remove terraform state backups
if [ -f "$TF_DIR/terraform.tfstate.backup" ]; then
    echo "[+] Removing terraform.tfstate.backup"
    rm -f "$TF_DIR/terraform.tfstate.backup"
fi

# Remove .terraform directory (cached providers)
if [ -d "$TF_DIR/.terraform" ]; then
    echo "[+] Removing .terraform cache directory"
    rm -rf "$TF_DIR/.terraform"
fi

# Remove lock file
if [ -f "$TF_DIR/.terraform.lock.hcl" ]; then
    echo "[+] Removing .terraform.lock.hcl"
    rm -f "$TF_DIR/.terraform.lock.hcl"
fi

# Remove crash logs if any
if [ -f "$TF_DIR/crash.log" ]; then
    echo "[+] Removing crash.log"
    rm -f "$TF_DIR/crash.log"
fi

echo "[✓] Cleanup complete. Repository is clean."

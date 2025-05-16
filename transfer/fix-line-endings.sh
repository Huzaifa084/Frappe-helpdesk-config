#!/bin/bash
# fix-line-endings.sh
# Script to fix Windows CRLF line endings to Unix LF for shell scripts
# Usage: bash fix-line-endings.sh

echo "========================================="
echo "Fixing line endings for shell scripts"
echo "========================================="

# List of shell scripts to fix
SCRIPTS=("init.sh")

for script in "${SCRIPTS[@]}"; do
  if [ -f "$script" ]; then
    echo "Fixing line endings in $script..."
    # Create a temporary file
    tr -d '\r' < "$script" > "${script}.tmp"
    # Replace the original file
    mv "${script}.tmp" "$script"
    # Make it executable
    chmod +x "$script"
    echo "✓ Fixed $script"
  else
    echo "✗ File $script not found, skipping"
  fi
done

echo "========================================="
echo "Line ending fix complete"
echo "========================================="
echo "You can now restart your Docker containers:"
echo "docker-compose down"
echo "docker-compose up -d"
echo "========================================="

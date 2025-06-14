#!/bin/sh

#  BrewInstalled.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 9/5/24.
  
echo "Checking for Homebrew installation..."

# Check Intel path
if [ -x "/usr/local/bin/brew" ]; then
  echo "✅ Homebrew found at /usr/local/bin/brew"
  /usr/local/bin/brew --version
  exit 0
fi

# Check Apple Silicon path
if [ -x "/opt/homebrew/bin/brew" ]; then
  echo "✅ Homebrew found at /opt/homebrew/bin/brew"
  /opt/homebrew/bin/brew --version
  exit 0
fi

# Try to repair permissions for Intel Macs
if [ -d "/usr/local/Homebrew" ]; then
  echo "⚠️ Homebrew not found, trying to repair permissions for Intel Mac..."
  sudo chown -R $(whoami) /usr/local/bin/brew
  sudo chown -R $(whoami) /usr/local/Homebrew
  sudo chown -R $(whoami) /usr/local/var/homebrew
  # Try again after repair
  if [ -x "/usr/local/bin/brew" ]; then
    echo "✅ Homebrew found at /usr/local/bin/brew after repairing permissions"
    /usr/local/bin/brew --version
    exit 0
  fi
fi

# Try to repair permissions for Apple Silicon Macs
if [ -d "/opt/homebrew" ]; then
  echo "⚠️ Homebrew not found, trying to repair permissions for Apple Silicon Mac..."
  sudo chown -R $(whoami) /opt/homebrew/bin/brew
  sudo chown -R $(whoami) /opt/homebrew
  sudo chown -R $(whoami) /opt/homebrew/var/homebrew
  # Try again after repair
  if [ -x "/opt/homebrew/bin/brew" ]; then
    echo "✅ Homebrew found at /opt/homebrew/bin/brew after repairing permissions"
    /opt/homebrew/bin/brew --version
    exit 0
  fi
fi

echo "❌ Homebrew not found! Please install Homebrew."
exit 1

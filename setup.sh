#!/bin/bash
set -e

echo "================================================"
echo "  GhostLocation – Dependency Setup"
echo "================================================"
echo ""

# 1. Homebrew
if ! command -v brew &>/dev/null; then
    echo "📦 Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Add brew to PATH for Apple Silicon
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
    fi
    echo "✅ Homebrew installed"
else
    echo "✅ Homebrew already installed"
fi

# 2. libimobiledevice
if ! command -v idevicesetlocation &>/dev/null; then
    echo "📱 Installing libimobiledevice..."
    brew install libimobiledevice
    echo "✅ libimobiledevice installed"
else
    echo "✅ libimobiledevice already installed"
fi

echo ""
echo "================================================"
echo "  All dependencies ready!"
echo "  On iOS 17+: Settings → Privacy & Security"
echo "              → Developer Mode → ON"
echo "              (then restart iPhone)"
echo "================================================"
echo ""
echo "Now run:  bash build.sh"

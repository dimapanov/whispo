#!/bin/bash

# Whispo Installation Script
# Installs voice-to-text system with Whisper AI

set -e

echo "🎤 Installing Whispo - Voice-to-Text with Whisper AI"
echo "=================================================="

# Check if running on Linux
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    echo "❌ Error: This script only works on Linux"
    exit 1
fi

# Detect distribution
if command -v pacman &> /dev/null; then
    DISTRO="arch"
elif command -v apt &> /dev/null; then
    DISTRO="debian"
elif command -v dnf &> /dev/null; then
    DISTRO="fedora"
else
    echo "❌ Error: Unsupported Linux distribution"
    echo "   Supported: Arch Linux, Ubuntu/Debian, Fedora"
    exit 1
fi

echo "📋 Detected distribution: $DISTRO"

# Install system dependencies
echo "📦 Installing system dependencies..."
case $DISTRO in
    arch)
        sudo pacman -Sy --needed python python-pip python-virtualenv pipewire pipewire-pulse libnotify ffmpeg wtype
        ;;
    debian)
        sudo apt update
        sudo apt install -y python3 python3-pip python3-venv pipewire libnotify-bin ffmpeg wtype
        ;;
    fedora)
        sudo dnf install -y python3 python3-pip python3-virtualenv pipewire libnotify ffmpeg wtype
        ;;
esac

# Check if virtual environment already exists
if [ -d "venv" ]; then
    echo "🔄 Virtual environment exists, updating..."
    rm -rf venv
fi

# Create virtual environment
echo "🐍 Creating Python virtual environment..."
python3 -m venv --clear venv

# Activate virtual environment
source venv/bin/activate

# Upgrade pip
echo "⬆️ Upgrading pip..."
pip install --upgrade pip setuptools wheel

# Install Whisper and dependencies
echo "🤖 Installing OpenAI Whisper..."
pip install --no-cache-dir openai-whisper torch torchaudio

# Verify installation
echo "✅ Verifying Whisper installation..."
python -c "import whisper; print('Whisper installed successfully')" || {
    echo "❌ Error: Whisper installation failed"
    exit 1
}

# Download default model
echo "📥 Downloading Whisper 'small' model..."
python -c "import whisper; whisper.load_model('small')"

deactivate

# Make scripts executable
echo "🔧 Setting script permissions..."
chmod +x whispo-transcribe.sh whispo-control.sh

# Create temporary directory
echo "📁 Creating temporary directory..."
mkdir -p /tmp/whispo

echo ""
echo "🎉 Installation completed successfully!"
echo ""
echo "Next steps:"
echo "1. Add to your Hyprland config (~/.config/hypr/bindings.conf):"
echo ""
echo "   # Alt+Space for voice input (recommended)"
echo "   bindr = ALT, SPACE, exec, ~/whispo/whispo-control.sh release"
echo "   bind = ALT, SPACE, exec, ~/whispo/whispo-control.sh push"
echo ""
echo "2. Reload Hyprland: hyprctl reload"
echo ""
echo "3. Test with: ./whispo-transcribe.sh toggle"
echo ""
echo "For more information, see README.md"
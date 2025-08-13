#!/bin/bash

# Agently Installation Script
set -e

echo "🚀 Installing Agently..."

# Check if we're on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "❌ Agently only supports macOS"
    exit 1
fi

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    echo "❌ Homebrew is required. Please install it first: https://brew.sh"
    exit 1
fi

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Install system dependencies
echo "📦 Installing system dependencies..."
brew bundle --file="$SCRIPT_DIR/Brewfile"

# Create virtual environment if it doesn't exist
if [ ! -d "$SCRIPT_DIR/venv" ]; then
    echo "🐍 Creating Python virtual environment..."
    python3 -m venv "$SCRIPT_DIR/venv"
fi

# Activate virtual environment and install Python dependencies
echo "📦 Installing Python dependencies..."
source "$SCRIPT_DIR/venv/bin/activate"
pip install --upgrade pip
pip install -r "$SCRIPT_DIR/requirements.txt"

# Build the Swift project
echo "🔨 Building Swift project..."
cd "$SCRIPT_DIR"
swift build -c release

# Create the agently command
echo "🔗 Creating global command..."

# Try to find a writable location for the binary
if [ -w "/usr/local/bin" ]; then
    AGENTLY_BIN="/usr/local/bin/agently"
elif [ -w "$HOME/.local/bin" ]; then
    AGENTLY_BIN="$HOME/.local/bin/agently"
    mkdir -p "$HOME/.local/bin"
elif [ -w "$HOME/bin" ]; then
    AGENTLY_BIN="$HOME/bin/agently"
    mkdir -p "$HOME/bin"
else
    echo "❌ No writable location found for the agently command."
    echo "Please create one of these directories and add it to your PATH:"
    echo "  mkdir -p ~/.local/bin && echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc"
    echo "  OR"
    echo "  mkdir -p ~/bin && echo 'export PATH=\"\$HOME/bin:\$PATH\"' >> ~/.zshrc"
    exit 1
fi

# Create the wrapper script
cat > "$AGENTLY_BIN" << 'EOF'
#!/bin/bash

# Get the directory where agently is installed
AGENTLY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib/agently" 2>/dev/null || echo "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/agently")"

# If the symlink approach doesn't work, try to find the actual installation
if [ ! -d "$AGENTLY_DIR" ]; then
    # Try to find the agently directory
    AGENTLY_DIR="$(find /usr/local -name "agently" -type d 2>/dev/null | head -1)"
fi

# If still not found, try the current directory
if [ ! -d "$AGENTLY_DIR" ]; then
    AGENTLY_DIR="$(pwd)"
fi

# Activate virtual environment
if [ -f "$AGENTLY_DIR/venv/bin/activate" ]; then
    source "$AGENTLY_DIR/venv/bin/activate"
else
    echo "❌ Virtual environment not found. Please reinstall Agently."
    exit 1
fi

# Check if task was provided
if [ $# -eq 0 ]; then
    echo "Usage: agently <task>"
    echo "Examples:"
    echo "  agently \"Open Safari\""
    echo "  agently \"Open Messages and send a text to Aneesh that says 'hello!'\""
    exit 1
fi

# Run the task
cd "$AGENTLY_DIR"
./run.sh task "$*"
EOF

# Make the script executable
chmod +x "$AGENTLY_BIN"

# Create a symlink to the actual agently directory
if [ -w "/usr/local/lib" ]; then
    AGENTLY_LIB_DIR="/usr/local/lib/agently"
    mkdir -p "$AGENTLY_LIB_DIR"
    ln -sf "$SCRIPT_DIR" "$AGENTLY_LIB_DIR"
else
    AGENTLY_LIB_DIR="$HOME/.local/lib/agently"
    mkdir -p "$AGENTLY_LIB_DIR"
    ln -sf "$SCRIPT_DIR" "$AGENTLY_LIB_DIR"
fi

echo "✅ Agently installed successfully!"
echo ""
echo "You can now use Agently with commands like:"
echo "  agently \"Open Safari\""
echo "  agently \"Open Messages and send a text to Aneesh that says 'hello!'\""
echo ""

# Check if the binary location is in PATH
if [[ ":$PATH:" != *":$(dirname "$AGENTLY_BIN"):"* ]]; then
    echo "⚠️  The agently command was installed to: $AGENTLY_BIN"
    echo "   This location may not be in your PATH. To add it, run:"
    echo "   echo 'export PATH=\"$(dirname "$AGENTLY_BIN"):\$PATH\"' >> ~/.zshrc"
    echo "   source ~/.zshrc"
    echo ""
fi

echo "Note: You may need to grant Accessibility permissions in System Settings → Privacy & Security → Accessibility"
echo "Add both 'agently' and 'python' to the allowed applications."

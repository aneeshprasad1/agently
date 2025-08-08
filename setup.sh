#!/bin/bash

# Agently Setup Script
# This script sets up your development environment

set -e

echo "🚀 Setting up Agently Development Environment"
echo "=============================================="

# Check if we're on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "❌ Error: Agently requires macOS"
    exit 1
fi

# Check for Homebrew
if ! command -v brew &> /dev/null; then
    echo "📦 Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
    echo "✅ Homebrew already installed"
fi

# Install system dependencies
echo "📦 Installing system dependencies..."
brew bundle --no-upgrade 2>/dev/null || echo "Some packages may already be installed"

# Set up Python virtual environment
echo "🐍 Setting up Python virtual environment..."
if [[ ! -d "venv" ]]; then
    python3 -m venv venv
    echo "✅ Created virtual environment"
else
    echo "✅ Virtual environment already exists"
fi

# Activate virtual environment and install Python packages
echo "📦 Installing Python dependencies..."
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

echo ""
echo "🔧 Environment Setup Complete!"
echo ""
echo "Next steps:"
echo "1. Activate the virtual environment:"
echo "   source venv/bin/activate"
echo ""
echo "2. Set your OpenAI API key:"
echo "   export OPENAI_API_KEY='your_api_key_here'"
echo ""
echo "3. Grant accessibility permissions:"
echo "   make preflight"
echo ""
echo "4. Test the installation:"
echo "   python3 test_runner.py"
echo ""
echo "5. Build and run:"
echo "   make build"
echo "   swift run agently --task 'Open Calculator'"
echo ""
echo "🎉 Ready to automate your Mac with AI!"

#!/bin/bash

# Agently Runner Script
# This script activates the virtual environment and provides easy access to Agently commands

set -e

# Audio feedback functions
play_step_chime() {
    # Play a gentle chime for step completion
    afplay /System/Library/Sounds/Glass.aiff 2>/dev/null || true
}

play_completion_chime() {
    # Play a more prominent sound for task completion
    afplay /System/Library/Sounds/Ping.aiff 2>/dev/null || true
}

play_error_sound() {
    # Play an error sound for failures
    afplay /System/Library/Sounds/Basso.aiff 2>/dev/null || true
}

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Activate virtual environment
if [ ! -d "venv" ]; then
    echo "❌ Virtual environment not found. Please run 'make deps' first."
    play_error_sound
    exit 1
fi

source venv/bin/activate

# Play startup sound for task execution
if [ "$1" = "task" ] || [ "$1" = "demo" ]; then
    afplay /System/Library/Sounds/Submarine.aiff 2>/dev/null || true
fi

# Function to show usage
show_usage() {
    echo "🚀 Agently Runner"
    echo "=================="
    echo ""
    echo "Usage: ./run.sh [command] [options]"
    echo ""
    echo "Commands:"
    echo "  help                    Show this help message"
    echo "  build                   Build the Swift package"
    echo "  test                    Run tests"
    echo "  preflight               Check accessibility permissions"
    echo "  graph                   Build and display UI graph"
    echo "  task <description>      Execute a task"
    echo "  demo                    Run a demo task"
    echo "  status                  Show project status"
    echo ""
    echo "Examples:"
    echo "  ./run.sh task 'Open Calculator'"
    echo "  ./run.sh task 'Click the close button'"
    echo "  ./run.sh graph"
    echo "  ./run.sh preflight"
    echo ""
}

# Function to check if OpenAI API key is set
check_api_key() {
    if [ -z "$OPENAI_API_KEY" ]; then
        echo "⚠️  Warning: OPENAI_API_KEY is not set"
        echo "   Set it with: export OPENAI_API_KEY='your_api_key_here'"
        echo "   This is required for AI-powered task planning"
        echo ""
    fi
}

# Main command handling
case "${1:-help}" in
    "help")
        show_usage
        ;;
    "build")
        echo "🔨 Building Swift package..."
        swift build
        if [ $? -eq 0 ]; then
            echo "✅ Build completed successfully!"
            play_completion_chime
        else
            echo "❌ Build failed!"
            play_error_sound
            exit 1
        fi
        ;;
    "test")
        echo "🧪 Running tests..."
        swift test
        play_step_chime
        python -m pytest tests/ -v
        play_completion_chime
        ;;
    "preflight")
        echo "🔍 Running accessibility preflight check..."
        swift run agently-runner --preflight
        play_completion_chime
        ;;
    "graph")
        echo "📊 Building and displaying UI graph..."
        swift run agently-runner --graph-only
        play_completion_chime
        ;;
    "task")
        if [ -z "$2" ]; then
            echo "❌ Error: Please provide a task description"
            echo "Example: ./run.sh task 'Open Calculator'"
            play_error_sound
            exit 1
        fi
        check_api_key
        echo "🤖 Executing task: $2"
        
        # Check if verbose flag is provided
        if [ "$3" = "--verbose" ]; then
            swift run agently-runner --task "$2" --verbose | while IFS= read -r line; do
                echo "$line"
                # Play ping for each action completion
                if [[ "$line" == *"Action completed successfully"* ]]; then
                    play_step_chime
                fi
            done
        else
            swift run agently-runner --task "$2" | while IFS= read -r line; do
                echo "$line"
                # Play ping for each action completion
                if [[ "$line" == *"Action completed successfully"* ]]; then
                    play_step_chime
                fi
            done
        fi
        play_completion_chime
        ;;
    "demo")
        check_api_key
        echo "🎯 Running demo task: Open Calculator and calculate 2 + 2"
        play_step_chime
        swift run agently-runner --task "Open Calculator and calculate 2 + 2" | while IFS= read -r line; do
            echo "$line"
            # Play ping for each action completion
            if [[ "$line" == *"Action completed successfully"* ]]; then
                play_completion_chime
            fi
        done
        play_completion_chime
        ;;
    "status")
        echo "📊 Agently Status:"
        echo "=================="
        echo "✅ Virtual environment: Active"
        echo "✅ Python dependencies: Installed"
        echo "✅ Swift package: Built"
        if [ -n "$OPENAI_API_KEY" ]; then
            echo "✅ OpenAI API Key: Set"
        else
            echo "⚠️  OpenAI API Key: Not set"
        fi
        echo ""
        echo "Ready to run tasks! Try: ./run.sh task 'your task here'"
        play_step_chime
        ;;
    *)
        echo "❌ Unknown command: $1"
        echo ""
        show_usage
        play_error_sound
        exit 1
        ;;
esac

# Agently Quick Start Guide

## 🚀 How to Run Agently

### 1. Prerequisites

**System Requirements:**
- macOS 14+ 
- Xcode 15+ (for Swift development)
- Python 3.12+
- Homebrew

### 2. Installation

```bash
# Clone the repository (if you haven't already)
git clone <your-repo-url>
cd agently

# Install system dependencies
make deps

# Set up Python virtual environment (recommended)
python3 -m venv venv
source venv/bin/activate

# Install Python dependencies
pip install -r requirements.txt

# Configure OpenAI API key
export OPENAI_API_KEY="your_api_key_here"
```

### 3. Grant Accessibility Permissions

**CRITICAL:** Agently needs accessibility permissions to control your Mac.

1. Run the preflight check:
   ```bash
   make preflight
   ```

2. If prompted, go to:
   **System Settings → Privacy & Security → Accessibility**

3. Click **"+"** and add:
   - Your terminal app (Terminal.app or iTerm2)
   - Python executable (usually `/usr/bin/python3`)
   - The built `agently` binary

### 4. Test the Installation

#### Test UI Graph Building
```bash
# Build and view the current UI state
make graph
```

#### Test the Planner
```bash
# Test Python planner with a sample task
python -m planner.main --task "click the close button" --graph sample_graph.json
```

#### Run a Simple Task
```bash
# Execute a basic automation task
swift run agently --task "Open Calculator and type 2 + 2"
```

### 5. Available Commands

| Command | Description |
|---------|-------------|
| `make build` | Build the Swift package |
| `make test` | Run all tests |
| `make preflight` | Check accessibility permissions |
| `make graph` | Display current UI graph |
| `make smoke` | Run smoke tests |
| `swift run agently --help` | Show all available options |

### 6. Running Tasks

#### Basic Usage
```bash
swift run agently --task "your task description"
```

#### Examples
```bash
# Simple click task
swift run agently --task "Click the submit button"

# Text input task
swift run agently --task "Type 'hello world' in the search field"

# Multi-step task
swift run agently --task "Open Safari, navigate to google.com, and search for 'AI agents'"

# Get verbose output
swift run agently --task "Open Finder" --verbose

# Get JSON output for analysis
swift run agently --task "Open Calculator" --format json
```

#### Advanced Options
```bash
# Build UI graph only (no execution)
swift run agently --graph-only

# Use specific output format
swift run agently --task "test" --format json

# Enable verbose logging
swift run agently --task "test" --verbose
```

### 7. Understanding the Output

**Successful Execution:**
```json
{
  "task": "Click the submit button",
  "total_actions": 3,
  "successful_actions": 3,
  "execution_time": 1.2,
  "actions": [...]
}
```

**UI Graph Structure:**
```json
{
  "elements": {
    "button_1": {
      "role": "AXButton",
      "title": "Submit",
      "position": {"x": 100, "y": 200},
      "isEnabled": true
    }
  },
  "activeApplication": "Safari"
}
```

### 8. Troubleshooting

#### Permission Issues
```bash
# Check current permissions
make preflight

# Reset accessibility permissions (if needed)
sudo tccutil reset Accessibility
```

#### Build Issues
```bash
# Clean and rebuild
make clean
make build

# Update dependencies
swift package update
```

#### Python Issues
```bash
# Verify virtual environment
which python
pip list

# Reinstall dependencies
pip install -r requirements.txt --force-reinstall
```

#### Common Error: "Element not found"
- The UI may have changed between graph building and execution
- Try adding wait times or retry logic
- Check if the target application is in focus

#### Performance Issues
- Monitor memory usage: Activity Monitor
- Enable verbose logging to see execution timing
- Check for accessibility API rate limiting

### 9. Development Workflow

#### Making Changes
```bash
# Run pre-commit checks
make precommit

# Test your changes
make smoke

# Run specific tests
swift test --filter UIGraphTests
pytest tests/test_planner.py -v
```

#### Debugging
```bash
# Debug UI graph building
swift run agently --graph-only --verbose

# Debug action execution
swift run agently --task "test" --verbose

# Test planner in isolation
python -m planner.main --task "test task" --graph graph.json --verbose
```

### 10. Next Steps

- **Customize prompts** in `planner/prompts.py`
- **Add new action types** in `Sources/Skills/`
- **Enhance UI element detection** in `Sources/UIGraph/`
- **Integrate with OS-World benchmarks** in `bench_harness/`

### 🎯 Ready to Control Your Mac with AI!

You now have a fully functional accessibility-based agent. Start with simple tasks and gradually work up to more complex automation workflows.

**Need help?** Check the logs, run with `--verbose`, or open an issue in the repository.

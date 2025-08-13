# 🚀 Getting Started with Agently

## What is Agently?

Agently is an **AI-powered macOS automation agent** that uses Accessibility APIs to control your Mac. It can:

- Open applications
- Click buttons and UI elements
- Type text
- Navigate through applications
- Perform complex automation tasks

## Quick Setup

### 1. Prerequisites
- **macOS 14+**
- **Xcode 15+** (Command Line Tools)
- **Python 3.12+**
- **Homebrew**

### 2. Installation

The project is already set up with a virtual environment! Just run:

```bash
# Check if everything is ready
./run.sh status

# If you need to install dependencies
make deps
```

### 3. Set up OpenAI API Key (Required for AI planning)

```bash
export OPENAI_API_KEY="your_openai_api_key_here"
```

### 4. Grant Accessibility Permissions

**CRITICAL:** Agently needs accessibility permissions to control your Mac.

```bash
# Run the preflight check
./run.sh preflight
```

Then go to **System Settings → Privacy & Security → Accessibility** and add:
- Your terminal app (Terminal.app or iTerm2)
- Python executable
- The built `agently-runner` binary

## Usage

### Basic Commands

```bash
# Check project status
./run.sh status

# Run a simple task
./run.sh task "Open Calculator"

# Run a demo task
./run.sh demo

# Build UI graph only (no execution)
./run.sh graph

# Check accessibility permissions
./run.sh preflight
```

### Example Tasks

```bash
# Simple tasks
./run.sh task "Open Safari"
./run.sh task "Click the close button"
./run.sh task "Type 'hello world' in the search field"

# Complex tasks
./run.sh task "Open Calculator, calculate 2 + 2, and copy the result"
./run.sh task "Open Safari, navigate to google.com, and search for 'AI agents'"
```

### Advanced Usage

```bash
# Build the project
./run.sh build

# Run tests
./run.sh test

# Get help
./run.sh help
```

## How It Works

1. **UI Graph Builder** (Swift) - Maps your screen's UI elements using Accessibility APIs
2. **AI Planner** (Python) - Converts natural language tasks into action plans
3. **Skill Executor** (Swift) - Executes the planned actions using Accessibility APIs
4. **Memory System** - Learns from previous executions

## Troubleshooting

### Permission Issues
```bash
# Check permissions
./run.sh preflight

# Reset accessibility permissions (if needed)
sudo tccutil reset Accessibility
```

### Build Issues
```bash
# Clean and rebuild
make clean
./run.sh build
```

### Common Errors
- **"Element not found"** - The UI may have changed, try again
- **"Permission denied"** - Check accessibility permissions
- **"API key not set"** - Set your OpenAI API key

## Project Structure

```
agently/
├── Sources/              # Swift source code
│   ├── AgentlyRunner/    # Main executable
│   ├── Skills/           # Action implementations
│   └── UIGraph/          # UI graph builder
├── planner/              # Python AI planner
├── memory/               # Memory system
├── tests/                # Test suites
├── venv/                 # Python virtual environment
├── run.sh                # Easy runner script
└── requirements.txt      # Python dependencies
```

## Next Steps

- Try the demo: `./run.sh demo`
- Experiment with simple tasks
- Check out the benchmark tasks in `benchmark_tasks/`
- Read the full documentation in `docs/`

## Need Help?

- Run `./run.sh help` for command options
- Check the logs for detailed error messages
- Open an issue in the repository

---

**🎯 Ready to automate your Mac with AI!**

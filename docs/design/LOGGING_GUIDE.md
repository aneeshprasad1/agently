# 📊 Agently Logging System

## Overview

Agently now features a comprehensive, organized logging system that captures every aspect of agent execution, including detailed LLM conversations and structured run organization.

## 🗂️ New Directory Structure

```
logs/
├── runs/                                    # Organized by execution runs
│   ├── 2025-01-18_14-30-45_open-messages/  # Human-readable: timestamp + task
│   │   ├── run_metadata.json               # Task info, timing, run ID
│   │   ├── ui_graphs/                       # All UI snapshots for this run
│   │   │   ├── 00_initial_graph.json       # Numbered sequence
│   │   │   ├── 00_initial_graph_summary.txt
│   │   │   ├── 01_after_click.json         # After each action
│   │   │   ├── 01_after_click_summary.txt
│   │   │   ├── 02_after_type.json
│   │   │   ├── recovery_after_action_2.json # Recovery attempts
│   │   │   └── recovery_after_action_2_summary.txt
│   │   ├── llm_conversations/               # 🆕 Full LLM logs!
│   │   │   ├── 01_initial_planning.md       # Complete conversation
│   │   │   ├── 02_error_recovery.md         # Recovery planning
│   │   │   └── 03_element_selection.md      # Element selection
│   │   ├── execution_log.md                 # Human-readable execution summary
│   │   └── results_summary.json            # Machine-readable results
│   └── 2025-01-18_15-15-22_find-file/
└── archived/                               # Optional: move old runs here
```

## 🤖 LLM Conversation Logging

### What Gets Logged

Each LLM conversation is saved as a detailed Markdown file containing:

1. **Full System Prompt** - The complete instructions sent to the LLM
2. **User Prompt** - The task description and UI context
3. **LLM Response** - The raw response before parsing
4. **Metadata** - Model, temperature, tokens used, timing
5. **Error Information** - If the API call failed

### Example LLM Conversation Log

```markdown
# LLM Conversation: initial_planning

**Timestamp:** 2025-01-18T14:30:45.123Z
**Model:** gpt-4o-mini
**Temperature:** 0.1
**Max Tokens:** 2000

## System Message

```
You are an expert AI assistant that creates action plans for automating macOS tasks...
[Full system prompt]
```

## User Message

```
Task: open messages
UI Graph Summary:
Application: Finder
Total elements: 156
Element types: {'AXButton': 12, 'AXTextField': 3, ...}
[Full UI context]
```

## Assistant Response

**Response Timestamp:** 2025-01-18T14:30:46.789Z

**Response Metadata:**
```json
{
  "model": "gpt-4o-mini",
  "usage": {
    "prompt_tokens": 1234,
    "completion_tokens": 567,
    "total_tokens": 1801
  },
  "finish_reason": "stop"
}
```

**Content:**
```
{
  "reasoning": "I need to open the Messages application...",
  "actions": [
    {
      "type": "key_press",
      "parameters": {"key": "Command+Space"},
      "description": "Open Spotlight search"
    }
  ],
  "confidence": 0.9
}
```

---
```

## 📁 Run Organization Benefits

### Easy Browsing
- **Chronological**: Runs are naturally sorted by time
- **Identifiable**: Task name in folder helps identify purpose
- **Self-contained**: Everything for one execution in one place

### Debugging & Analysis
- **UI Evolution**: See how the UI changed with each action
- **LLM Reasoning**: Understand why decisions were made
- **Error Recovery**: Track recovery attempts and their context
- **Performance**: Execution timing and success rates

### Example Usage

```bash
# Find a specific run
ls logs/runs/ | grep "open-messages"

# View LLM reasoning for a failed run
cat logs/runs/2025-01-18_14-30-45_open-messages/llm_conversations/01_initial_planning.md

# Check execution results
jq '.success_rate' logs/runs/2025-01-18_14-30-45_open-messages/results_summary.json

# Compare UI before/after an action
diff logs/runs/*/ui_graphs/00_initial_graph_summary.txt \
     logs/runs/*/ui_graphs/01_after_click_summary.txt
```

## 🔧 Implementation Details

### File Naming Conventions
- **Runs**: `YYYY-MM-DD_HH-mm-ss_sanitized-task-name`
- **UI Graphs**: `NN_descriptive_name.json` (numbered sequence)
- **LLM Conversations**: `NN_conversation_type.md`

### Automatic Cleanup
- Consider archiving runs older than 30 days
- Keep only the most recent 100 runs to prevent disk bloat
- Compress large UI graph files

### Backward Compatibility
- Old flat log files remain untouched
- New system only applies to new runs
- Migration script available if needed

## 🚀 Getting Started

The new logging system is **automatically active**. Run Agently with different logging levels:

```bash
# Default mode - organized logs, NO LLM conversation logging (fastest)
swift run agently --task "open calendar app"

# Enable LLM conversation logging for debugging (slower but detailed)
swift run agently --task "open calendar app" --enable-llm-logging

# Graph-only mode - saves to run directories
swift run agently --graph-only

# Verbose mode for extra detail
swift run agently --task "send email" --verbose
```

### 🏃‍♂️ Performance Modes

**Fast Mode (Default)**:
- ✅ Organized run directories
- ✅ UI graph snapshots  
- ✅ Execution tracking
- ❌ LLM conversation logging (disabled for speed)

**Debug Mode (--enable-llm-logging)**:
- ✅ Everything from Fast Mode
- ✅ Complete LLM conversation logs
- ⚠️ Slower execution due to file I/O

All logs will be organized in the new structure. Use `--enable-llm-logging` only when you need to debug AI decision-making!

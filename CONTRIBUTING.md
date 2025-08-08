# Contributing to Agently

Thank you for your interest in contributing to Agently! This guide will help you get started.

## Development Setup

1. **Prerequisites**
   - macOS 14+ with Xcode 15+
   - Homebrew
   - Python 3.12+

2. **Install Dependencies**
   ```bash
   make deps
   ```

3. **Set up Development Environment**
   ```bash
   make setup-dev
   ```

4. **Configure API Keys**
   ```bash
   export OPENAI_API_KEY=your_api_key_here
   ```

## Development Workflow

1. **Create a Feature Branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make Changes**
   - Follow the existing code style
   - Add tests for new functionality
   - Update documentation as needed

3. **Run Tests and Checks**
   ```bash
   make precommit
   ```

4. **Submit Pull Request**
   - Provide clear description of changes
   - Include test coverage
   - Link any related issues

## Code Style

### Swift
- Follow Swift API Design Guidelines
- Use `swift-format` for consistent formatting
- Prefer explicit types where clarity is important
- Use meaningful variable and function names

### Python
- Follow PEP 8 style guide
- Use `black` for code formatting
- Use `ruff` for linting
- Type hints are required for public APIs
- Docstrings for all public functions and classes

## Testing

### Swift Tests
```bash
swift test
```

### Python Tests
```bash
pytest tests/ -v
```

### Integration Tests
```bash
make smoke
```

## Project Structure

```
agently/
├── Sources/           # Swift source code
│   ├── UIGraph/      # Accessibility graph building
│   ├── Skills/       # Action execution
│   └── AgentlyRunner/ # Main executable
├── planner/          # Python LLM planner
├── memory/           # Episodic memory system
├── bench_harness/    # Benchmark runner
├── tests/            # Python tests
├── Tests/            # Swift tests
└── scripts/          # Utility scripts
```

## Adding New Features

### New Action Types
1. Add to `ActionType` enum in `SkillAction.swift`
2. Implement in `SkillExecutor.swift`
3. Add tests in `SkillActionTests.swift`
4. Update prompts if needed

### New UI Element Support
1. Extend `AccessibilityGraphBuilder.swift`
2. Update `UIElement.swift` if new properties needed
3. Add test coverage

### Planner Improvements
1. Update prompt templates in `prompts.py`
2. Enhance planner logic in `planner.py`
3. Add unit tests

## Debugging

### Accessibility Issues
```bash
# Check permissions
make preflight

# View current UI graph
make graph
```

### Action Execution
```bash
# Enable verbose logging
swift run agently --verbose --task "your task"
```

### Planner Issues
```bash
# Test planner directly
python -m planner.main --task "test" --graph /path/to/graph.json --verbose
```

## Performance Guidelines

1. **Memory Usage**: Keep resident memory under 500MB
2. **Action Speed**: Target human-like timing for actions
3. **Graph Building**: Optimize for minimal latency
4. **LLM Calls**: Cache responses when appropriate

## Documentation

- Update README.md for user-facing changes
- Update DESIGN_DOC.md for architectural changes
- Add inline documentation for complex code
- Include examples in docstrings

## Issue Reporting

When reporting issues, please include:

1. **Environment**
   - macOS version
   - Xcode version
   - Python version

2. **Steps to Reproduce**
   - Exact commands run
   - Expected vs actual behavior

3. **Logs**
   - Relevant log output
   - Error messages

4. **Context**
   - What you were trying to accomplish
   - Any workarounds you found

## Questions?

- Open an issue for bugs or feature requests
- Start a discussion for questions about usage
- Check existing issues before creating new ones

Thank you for contributing to Agently!

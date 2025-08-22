# Agently - Makefile for building and testing

.PHONY: help build test clean install deps bench smoke lint format precommit

# Default target
help:
	@echo "Agently - AI Agent for macOS Automation"
	@echo ""
	@echo "Available targets:"
	@echo "  build       - Build Swift package"
	@echo "  test        - Run all tests"
	@echo "  clean       - Clean build artifacts"
	@echo "  install     - Install dependencies"
	@echo "  deps        - Install dependencies (alias for install)"
	@echo "  bench       - Run full OS-World benchmark suite"
	@echo "  smoke       - Run smoke tests (subset of benchmarks)"
	@echo "  lint        - Run linting"
	@echo "  format      - Format code"
	@echo "  precommit   - Run pre-commit checks"
	@echo "  preflight   - Check accessibility permissions"

# Build targets
build:
	@echo "Building Swift package..."
	swift build

build-release:
	@echo "Building Swift package (release)..."
	swift build -c release

# Test targets
test: test-swift test-python

test-swift:
	@echo "Running Swift tests..."
	swift test

test-python:
	@echo "Running Python tests..."
	source venv/bin/activate && python -m pytest tests/ -v

smoke:
	@echo "Running smoke tests..."
	@./scripts/run_smoke_tests.sh

# Benchmark targets
bench: build-release
	@echo "Running full benchmark suite..."
	@./scripts/run_benchmarks.sh

# Installation targets
install: deps

deps:
	@echo "Installing dependencies..."
	@if command -v brew >/dev/null 2>&1; then \
		echo "Installing Homebrew dependencies..."; \
		brew bundle --no-upgrade; \
	else \
		echo "Homebrew not found, please install manually"; \
	fi
	@echo "Installing Python dependencies..."
	@if [ ! -d "venv" ]; then \
		echo "Creating Python virtual environment..."; \
		python3 -m venv venv; \
	fi
	@source venv/bin/activate && pip install --upgrade pip && pip install -r requirements.txt
	@echo "Resolving Swift dependencies..."
	swift package resolve

# Code quality targets
lint: lint-python lint-swift

lint-python:
	@echo "Linting Python code..."
	@source venv/bin/activate && ruff check planner/ memory/ scripts/
	@source venv/bin/activate && mypy planner/ memory/

lint-swift:
	@echo "Linting Swift code..."
	# Swift has built-in warnings, but we could add SwiftLint if needed

format: format-python format-swift

format-python:
	@echo "Formatting Python code..."
	@source venv/bin/activate && black planner/ memory/ scripts/
	@source venv/bin/activate && ruff check --fix planner/ memory/ scripts/

format-swift:
	@echo "Formatting Swift code..."
	swift-format --in-place --recursive Sources/ Tests/

precommit: format lint test-swift
	@echo "Pre-commit checks complete!"

# Development targets
preflight: build
	@echo "Running accessibility preflight check..."
	swift run agently --preflight

graph:
	@echo "Building and displaying UI graph..."
	swift run agently --graph-only

demo-task:
	@echo "Running demo task..."
	swift run agently --task "Open Calculator and calculate 2 + 2"

# Utility targets
clean:
	@echo "Cleaning build artifacts..."
	swift package clean
	rm -rf .build/
	find . -name "*.pyc" -delete
	find . -name "__pycache__" -delete

# Development setup
setup-dev: deps
	@echo "Setting up development environment..."
	@if command -v pre-commit >/dev/null 2>&1; then \
		source venv/bin/activate && pre-commit install; \
	fi
	@echo "Development environment ready!"

# Package and release
package: build-release
	@echo "Packaging release..."
	@mkdir -p dist/
	cp .build/release/agently dist/
	@echo "Package created in dist/"

# Status check
status:
	@echo "📊 Agently Status:"
	@echo "=================="
	@if [ -d "venv" ]; then \
		echo "✅ Virtual environment: Created"; \
	else \
		echo "❌ Virtual environment: Missing (run 'make deps')"; \
	fi
	@if [ -n "$$OPENAI_API_KEY" ]; then \
		echo "✅ OpenAI API Key: Set"; \
	else \
		echo "⚠️  OpenAI API Key: Not set (export OPENAI_API_KEY=your_key)"; \
	fi
	@echo ""
	@echo "Build Swift package: make build"
	@echo "Run a task: swift run agently --task 'your task'"
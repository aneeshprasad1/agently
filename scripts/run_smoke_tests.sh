#!/bin/bash

# Agently - Smoke Tests
# Runs a subset of quick tests to verify basic functionality

set -e

echo "🧪 Running Agently Smoke Tests"
echo "==============================="

# Check if we're in the right directory
if [[ ! -f "Package.swift" ]]; then
    echo "❌ Error: Must run from agently project root"
    exit 1
fi

# Build the project
echo "🔨 Building project..."
swift build

# Test 1: Accessibility preflight
echo "🔍 Test 1: Accessibility preflight check"
swift run agently --preflight || echo "⚠️  Accessibility check failed (expected if permissions not granted)"

# Test 2: UI graph building
echo "🌐 Test 2: UI graph building"
swift run agently --graph-only --format json > /tmp/agently_test_graph.json
if [[ -s /tmp/agently_test_graph.json ]]; then
    echo "✅ UI graph building successful"
    element_count=$(jq '.elements | length' /tmp/agently_test_graph.json 2>/dev/null || echo "unknown")
    echo "   Found $element_count UI elements"
else
    echo "❌ UI graph building failed"
    exit 1
fi

# Test 3: Python planner integration
echo "🤖 Test 3: Python planner integration"
if [[ -n "$OPENAI_API_KEY" ]]; then
    python -m planner.main --task "test task" --graph /tmp/agently_test_graph.json > /tmp/agently_test_plan.json
    if [[ -s /tmp/agently_test_plan.json ]]; then
        echo "✅ Python planner integration successful"
        confidence=$(jq '.confidence' /tmp/agently_test_plan.json 2>/dev/null || echo "unknown")
        action_count=$(jq '.actions | length' /tmp/agently_test_plan.json 2>/dev/null || echo "unknown")
        echo "   Generated $action_count actions with confidence $confidence"
    else
        echo "❌ Python planner integration failed"
        exit 1
    fi
else
    echo "⚠️  Skipping planner test (OPENAI_API_KEY not set)"
fi

# Test 4: Basic Swift unit tests
echo "🧪 Test 4: Swift unit tests"
swift test

# Cleanup
rm -f /tmp/agently_test_*.json

echo ""
echo "✅ All smoke tests passed!"
echo "🚀 Ready for development"

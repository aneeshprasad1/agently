#!/bin/bash

# Script to capture accessibility graphs before and after agently runs
# to help debug why element counts are increasing

echo "🔍 Capturing accessibility graphs for analysis..."

# Create logs directory
mkdir -p logs

# Capture baseline graph before any agently activity
echo "📊 Capturing baseline graph..."
swift run agently-runner --graph-only --format json > logs/baseline_graph.json 2>/dev/null

# Extract element count from baseline
BASELINE_COUNT=$(grep -o '"elements":{[^}]*}' logs/baseline_graph.json | grep -o '"element_[0-9]*"' | wc -l | tr -d ' ')
echo "Baseline graph: $BASELINE_COUNT elements"

# Run a simple task and capture graphs
echo "🤖 Running simple task to see what changes..."
swift run agently-runner --task "open messages" 2>&1 | tee logs/task_execution.log

# Capture graph after execution
echo "📊 Capturing post-execution graph..."
swift run agently-runner --graph-only --format json > logs/post_execution_graph.json 2>/dev/null

# Extract element count from post-execution
POST_COUNT=$(grep -o '"elements":{[^}]*}' logs/post_execution_graph.json | grep -o '"element_[0-9]*"' | wc -l | tr -d ' ')
echo "Post-execution graph: $POST_COUNT elements"

# Calculate difference
DIFF=$((POST_COUNT - BASELINE_COUNT))
echo "📈 Difference: $DIFF elements ($BASELINE_COUNT → $POST_COUNT)"

if [ $DIFF -gt 0 ]; then
    echo "⚠️  Element count increased! Something is spawning new applications/processes."
else
    echo "✅ Element count stable."
fi

echo "📁 All logs saved to logs/ directory"
echo "🔍 Check logs/*_summary.txt files for detailed breakdowns"

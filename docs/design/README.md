# Agently Design Documents

This directory contains all architectural and design documentation for the Agently project.

## 📋 Document Index

### Core Design Documents

| Document | Purpose | Status | Last Updated |
|----------|---------|--------|--------------|
| [**SYSTEM_ARCHITECTURE.md**](./SYSTEM_ARCHITECTURE.md) | Main system architecture and design principles | Active | - |
| [**ADAPTIVE_AGENT_DESIGN.md**](./ADAPTIVE_AGENT_DESIGN.md) | Adaptive agent behavior and learning mechanisms | Active | - |

### Performance & Optimization

| Document | Purpose | Status | Last Updated |
|----------|---------|--------|--------------|
| [**PERFORMANCE_OPTIMIZATION_PLAN.md**](./PERFORMANCE_OPTIMIZATION_PLAN.md) | Comprehensive performance optimization strategy | **New** | 2025-08-12 |

### Testing & Benchmarking

| Document | Purpose | Status | Last Updated |
|----------|---------|--------|--------------|
| [**BENCHMARKING_PLAN.md**](./BENCHMARKING_PLAN.md) | Benchmarking infrastructure and testing strategy | Active | - |
| [**OSWORLD_INTERFACE.md**](./OSWORLD_INTERFACE.md) | OSWorld evaluation framework integration and testing | Active | - |

### Development & Operations

| Document | Purpose | Status | Last Updated |
|----------|---------|--------|--------------|
| [**LOGGING_GUIDE.md**](./LOGGING_GUIDE.md) | Logging standards, debugging, and observability | Active | - |

## 🎯 Quick Reference

### For Developers
- **New to the project?** Start with [SYSTEM_ARCHITECTURE.md](./SYSTEM_ARCHITECTURE.md)
- **Working on performance?** See [PERFORMANCE_OPTIMIZATION_PLAN.md](./PERFORMANCE_OPTIMIZATION_PLAN.md)
- **Setting up benchmarks?** Check [BENCHMARKING_PLAN.md](./BENCHMARKING_PLAN.md)
- **OSWorld testing?** Review [OSWORLD_INTERFACE.md](./OSWORLD_INTERFACE.md)
- **Debugging issues?** Consult [LOGGING_GUIDE.md](./LOGGING_GUIDE.md)

### For Contributors
- **Understanding AI behavior?** Read [ADAPTIVE_AGENT_DESIGN.md](./ADAPTIVE_AGENT_DESIGN.md)
- **Adding new features?** Review relevant design docs for architectural guidance
- **Performance issues?** Consult the optimization plan for known bottlenecks
- **Development setup?** Follow logging standards in the logging guide

## 📊 System Overview

The Agently system consists of several key components:

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Swift Runner  │───▶│  Python Planner │───▶│  Skill Executor │
│  (UI Automation)│    │   (AI Planning) │    │ (Action Engine) │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   UI Graph      │    │   LLM Models    │    │  macOS APIs     │
│   (Accessibility)│    │   (OpenAI)     │    │ (Accessibility) │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 🔄 Document Lifecycle

### Status Definitions
- **Active**: Currently maintained and up-to-date
- **New**: Recently created, may need review
- **Draft**: Work in progress, not finalized
- **Deprecated**: No longer maintained, kept for reference

### Update Process
1. **Major Changes**: Update the design doc first, then implement
2. **Minor Changes**: Update docs within one sprint of implementation
3. **New Features**: Create design doc before implementation
4. **Performance Changes**: Update optimization plan with results

## 🏗️ Architecture Decisions

### Key Design Principles
1. **Modularity**: Clear separation between UI automation, planning, and execution
2. **Performance**: Sub-human execution times for simple tasks (target: 2-3x human baseline)
3. **Reliability**: >95% success rate for well-defined tasks
4. **Testability**: Comprehensive benchmarking and real execution validation

### Technology Choices
- **Swift**: UI automation and accessibility integration
- **Python**: AI planning and LLM integration  
- **OpenAI API**: LLM-based task planning
- **macOS Accessibility APIs**: UI interaction and graph building

## 📚 Related Documentation

### Root Level Docs
- [README.md](../../README.md) - Project overview and setup
- [QUICK_START.md](../../QUICK_START.md) - Getting started guide
- [CONTRIBUTING.md](../../CONTRIBUTING.md) - Contribution guidelines

### Implementation Docs
- Swift Package documentation in `/Sources`
- Python module documentation in `/planner` and `/benchmark_tasks`
- Test documentation in `/tests`

## 🤝 Contributing to Design Docs

### Guidelines
1. **Clarity**: Write for developers who are new to the project
2. **Specificity**: Include concrete examples and implementation details
3. **Maintenance**: Keep docs updated with implementation changes
4. **Review**: Have design changes reviewed before major implementation

### Template Structure
For new design documents, follow this structure:
```markdown
# Document Title

## Executive Summary
## Problem Statement  
## Proposed Solution
## Implementation Details
## Success Metrics
## Risk Assessment
## Future Considerations
```

---

*For questions about design documents or to propose new ones, create an issue or reach out to the maintainers.*

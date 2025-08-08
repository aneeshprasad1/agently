# Agently — README

> **Mission:** Build a desktop agent that controls macOS purely through Accessibility APIs (no screen‐scraping) and **beats OS‑World autonomous‑agent benchmarks**.

---

## Table of Contents

1. [Why Accessibility?](#why-accessibility)
2. [Goals & Success Metrics](#goals--success-metrics)
3. [Repo Structure](#repo-structure)
4. [Quick Start](#quick-start)
5. [Granting Accessibility Permissions](#granting-accessibility-permissions)
6. [Running the Benchmark Harness](#running-the-benchmark-harness)
7. [Architecture Overview](#architecture-overview)
8. [Development Workflow](#development-workflow)
9. [Roadmap](#roadmap)
10. [Contributing](#contributing)
11. [License](#license)

---

## Why Accessibility?

* **Deterministic UI graph** → Stable element IDs & roles vs. brittle OCR.
* **Semantic context** → Built‑in labels reduce prompt tokens for the LLM planner.
* **Lower latency & memory** → No frame captures or vision models.

## Goals & Success Metrics

| Metric                     | Target               |
| -------------------------- | -------------------- |
| OS‑World vX task pass rate | **≥ 95 %**           |
| Avg. action count / task   | ≤ 1.1 × human median |
| Runtime / task             | ≤ human median       |
| Resident memory            | < 500 MB             |

## Repo Structure

```
agently/
├── planner/           # Prompt templates & LLM wrappers
├── skills/            # Atomic action implementations (Swift & Python)
├── ui_graph/          # Accessibility graph builder
├── bench_harness/     # Forked OS‑World CLI + adapters
├── memory/            # Episodic DB (SQLite)
├── scripts/           # Utility scripts (codegen, lint, fmt)
├── tests/             # pytest & swift‑test suites
└── README.md
```

## Quick Start

```bash
# 1. Clone
$ git clone https://github.com/your‑org/agently.git && cd agently

# 2. Install deps (macOS 14+, Xcode 15+, Homebrew)
$ brew bundle   # installs Python 3.12, pyenv, swift‑format, etc.
$ pip install -r requirements.txt  # PyPI deps (pyobjc, openai, pydantic)
$ swift package resolve            # SwiftPM deps

# 3. Configure OpenAI (or Ollama) key
$ export OPENAI_API_KEY=sk‑...
```

## Granting Accessibility Permissions

1. **System Settings → Privacy & Security → Accessibility**.
2. Click **“+”** → add the generated binary `bench_harness/runner` and `python`.
3. Run once with the `--preflight` flag to auto‑trigger permission prompts.

> **Tip:** During CI we use `tccutil` with a custom profile to pre‑grant permissions.

## Running the Benchmark Harness

```bash
$ make bench   # builds & runs full OS‑World suite, prints pass‑rate table
```

Individual task:

```bash
$ python bench_harness/run_task.py tasks/open_mail.json
```

## Architecture Overview

* **UI Graph Builder** (Swift/pyobjc) → emits JSON of on‑screen AXUIElements.
* **Planner** (LLM) → consumes graph + task → emits high‑level intents.
* **Skill Executor** → translates intents into `AXUIElementPerformAction` or `CGEvent` calls.
* **Feedback loop** → diffs pre/post graph, logs success, and updates SQLite memory.

> For deeper design details see `Accessibility Agent App Design Doc` in the project docs folder.

## Development Workflow

1. **Create feature branch** from `main`.
2. Commit; run `make precommit` (black, ruff, swift‑format, mypy).
3. Open PR → CI runs lint + unit + OS‑World smoke.
4. After review, squash & merge.

### Testing

```bash
$ pytest -q                       # Python logic
$ swift test                      # Swift modules
$ make smoke                      # Subset of benchmark tasks
```

## Roadmap

* **Phase 1 (Weeks 1‑3):** MVP — static scripts passing ≥ 30 % tasks.
* **Phase 2 (Weeks 4‑6):** LLM planner + caching (≥ 70 %).
* **Phase 3 (Weeks 7‑9):** RL fine‑tune; hit ≥ 95 %.
* **Phase 4 (Week 10+):** Cross‑app generalization & packaging.

## Contributing

Pull requests welcome! Please read `CONTRIBUTING.md` and open an issue for major proposals.

## License

MIT — see `LICENSE` for full text.

---

*Questions or suggestions? Open an issue or ping @maintainers in Discord.*

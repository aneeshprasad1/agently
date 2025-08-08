# Accessibility Agent App — Design & Execution Plan

## 1. Purpose

Build a macOS (and eventually cross‑platform) agent that **controls the computer purely through system Accessibility APIs** rather than pixel‑based vision, with the explicit goal of **surpassing the latest “OS‑World” autonomous‑agent benchmarks** (task success rate, time‑to‑completion, and resource efficiency).

---

## 2. Success Criteria

| Metric                            | Target                          |
| --------------------------------- | ------------------------------- |
| OS‑World vX Task Pass Rate        | **≥ 95 %** on core suite        |
| Avg. Action Count / Task          | Within **1.1×** of median human |
| Total Runtime / Task              | ≤ human median                  |
| Memory Usage                      | < 500 MB resident               |
| % Tasks Requiring Manual Override | **0 %**                         |

---

## 3. Benchmark Recap

* **OS‑World** bundles desktop tasks (file search, email replies, calendar edits, IDE edits, etc.).
* Evaluates success via headless audit script that checks resulting OS state.
* Current SOTA: \~88 % pass using computer‑vision screen parsing.

---

## 4. High‑Level Approach

1. **Semantic UI Graph** — Crawl active application windows via Accessibility (AXUIElement) & Quartz Event Services; build a live object graph (nodes: UI elements; edges: hierarchy & spatial).
2. **LLM‑Driven Planner** — Prompt‑based planner (GPT‑4o or local mix‑LLM) receives task + UI graph → emits high‑level intent actions ("click Button\[id=Save]", "type ‘hello’ in Field\[label=Subject]").
3. **Skill Library** — Deterministic Python/Swift functions implementing each intent via Accessibility API + CGEvent taps.
4. **Feedback & Memory** — Observe post‑action UI deltas; store episodic memory for efficient future planning.
5. **Heuristic Optimizer** — Prunes long‑tail actions, caches successful sub‑plans, applies RL fine‑tuning over planner outputs.

---

## 5. System Architecture

```
┌─────────────┐      Task Prompt      ┌──────────────┐
│  BenchRig   │──────────────────────▶│   Planner    │
└─────────────┘                       └─────┬────────┘
        ▲                                      │ Intents
        │   UI Graph & Events                  ▼
┌───────┼────────────────────────┐      ┌─────────────┐
│ UI Observer & Graph Builder    │◀────▶│ Skill Exec  │
└───────┼────────────────────────┘      └─────┬───────┘
        │ Feedback Δ                            │ CG / AX Events
        ▼                                      ▼
    Episodic Memory                     macOS Accessibility
```

---

## 6. Key Components & APIs

| Layer                 | Technology                                                                          | Notes                                    |
| --------------------- | ----------------------------------------------------------------------------------- | ---------------------------------------- |
| **Graph Builder**     | Swift + AppKit `AXUIElement`, Python `pyobjc`, or Rust `accesskit`                  | Enumerate windows, roles, labels, states |
| **Skill Exec**        | `CGEventCreateKeyboardEvent`, `CGEventCreateMouseEvent`, `AXUIElementPerformAction` | Atomic, deterministic                    |
| **Planner**           | OpenAI Assistants / Ollama LLMs                                                     | Prompt templates stored locally          |
| **Memory**            | SQLite + JSON diff                                                                  | Persist UI snapshots & successful plans  |
| **Benchmark Harness** | fork of OS‑World CLI                                                                | Injects tasks & collects metrics         |

---

## 7. Advantages vs. Vision‑Based Agents

* **Deterministic Element IDs** → less brittle than OCR.
* **Lower Latency & Memory** — no large image rendering.
* **Accessibility Labels** → built‑in semantic context reduces prompt‑token count.

---

## 8. Development Roadmap

| Phase                           | Duration    | Milestones                                                                                                        |
| ------------------------------- | ----------- | ----------------------------------------------------------------------------------------------------------------- |
| **0. Setup**                    | Week 1      | Fork OS‑World; create Swift command‑line skeleton; obtain Accessibility perm via `NSAppleEventsUsageDescription`. |
| **1. MVP**                      | Weeks 2‑3   | Graph Builder + manual script to click buttons; pass ≥ 30 % tasks.                                                |
| **2. LLM Planner**              | Weeks 4‑6   | Integrate planner; hit 70 % pass, latency < 2× human.                                                             |
| **3. Optimizer & RL**           | Weeks 7‑9   | Cache sub‑plans, fine‑tune; surpass 95 %.                                                                         |
| **4. Cross‑App Generalization** | Weeks 10‑12 | Safari, VS Code, Mail; extend Skill Library.                                                                      |
| **5. Packaging**                | Week 13     | Sign & notarize; release under MIT license.                                                                       |

---

## 9. Risk & Mitigation

* **Permission Prompts** — Automate tccutil scripts & user onboarding.
* **Dynamic UIs** — Fallback to heuristic search when labels change.
* **LLM Hallucination** — Safety layer validates intents against live graph.
* **Benchmark Drift** — CI runs nightly against latest benchmark repo.

---

## 10. Next Steps

1. **Assess OS‑World task taxonomy** — tag required skills.
2. **Pick language bindings** — Swift vs. Python (speed vs. prototyping).
3. **Spike Graph Builder** — enumerate all elements in Finder window.
4. Schedule design review & set up repo scaffolding.

---

> *Let’s iterate: drop comments or request deeper dives into any section.*

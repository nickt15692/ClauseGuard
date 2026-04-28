# ClauseGuard — Session Context

This file exists to bring a new Claude instance up to speed on the full history of this project: what was built, what was wrong with it, what was fixed, and the reasoning behind every decision.

---

## What This Project Is

ClauseGuard is a contract conflict detection tool built for a university course (BUAN 6v99.s01, UT Dallas, April 2026). You upload two contract PDFs — your company's standard terms and a vendor's proposed terms — and a Claude-powered agent finds every conflicting clause, ranks them by legal risk, and produces a structured redline brief with suggested resolution language.

It is Project 1 of 3 for the course. The grading criteria includes a "BUILD vs BEND" score — whether the agent was built from scratch using the SDK (BUILD) or assembled from a no-code platform (BEND). This project scores BUILD.

Stack: FastAPI backend, React + Vite frontend, Anthropic SDK (raw agentic loop), PyMuPDF for PDF parsing.

---

## The Original Spec vs What Was Actually Built

The design spec is in `PROJECT1_ClauseGuard.md`. The initial implementation diverged from it in several ways:

**Tools: 5 in the spec → 4 in the initial build → 2 after all fixes**
- The spec listed `suggest_resolution` as a standalone tool. It was never implemented — resolution language was folded into the conflict objects Claude passes to `generate_redline_brief`.
- The spec also implied a `parser.py` file. PDF parsing ended up inside `extract_clauses()` in `tools.py` instead.
- `assess_risk` existed in the initial build but was removed in v1.1.
- `find_conflicts` existed through v1.2 but was removed in v1.3 as a wasted API round trip (see below).

**`find_conflicts` was a stub, not real logic**
The spec implied `find_conflicts` did the semantic comparison. In practice it returned a lightweight instruction string — the actual conflict detection always happened inside Claude's reasoning. It was removed in v1.3 and its instruction was folded into the system prompt, saving one complete API round trip per analysis.

**The agent loop has a 20-turn safety limit**
The spec showed `while True`. The real implementation uses `while turn < max_turns` with `max_turns = 20`.

**SSE streaming was added**
Not in the spec. The backend streams progress as Server-Sent Events so the frontend can show a live progress bar as tool calls fire. This became a key demo moment.

---

## Weaknesses Found and How They Were Prioritized

After reviewing the initial codebase, 11 weaknesses were identified and ranked by impact:

### P1 — Would break the demo
1. `assess_risk` disconnect — keyword matcher could contradict Claude's own risk reasoning
2. No file validation on upload — any file, any size accepted
3. Token budget fixed at 4096 — too small for real contracts, likely to truncate mid-response

### P2 — Correctness problems
4. 40-clause cap with no warning — silently drops later sections of long contracts
5. Redline report captured via side effect — fragile, depended on tool call order
6. `find_conflicts` re-injected full clause arrays — doubled token usage mid-loop

### P3 — Security / reliability
7. No session cleanup on error paths — files accumulate on disk indefinitely
8. `uploads/` path relative to cwd — breaks if uvicorn launched from wrong directory
9. SSE `onerror` not handled — UI hangs forever on network drop or backend crash

### P4 — Minor
10. `SYSTEM_PROMPT` duplicated in `main.py` and `agent.py`
11. Using Opus instead of Sonnet — 5x more expensive with no quality benefit for this task

All 11 were addressed in v1.1. Further issues were found and fixed in v1.2 and v1.3.

---

## Change History

### v1.1 — Initial fixes (full detail in `CHANGES_1_1.md`)

| # | File | Change |
|---|---|---|
| 1 | `config.py` | Model → `claude-sonnet-4-6`, overridable via `CLAUSEGUARD_MODEL` env var |
| 2 | `config.py` | `MAX_TOKENS` → 16000 |
| 3 | `config.py` | Added `MAX_FILE_SIZE = 10MB`, `MAX_CLAUSES = 60` |
| 4 | `config.py` | Added `SYSTEM_PROMPT` — single source of truth |
| 5 | `backend/tools.py` | Removed `assess_risk` entirely |
| 6 | `backend/tools.py` | Clause cap raised 40 → 60, truncation warning surfaced to UI |
| 7 | `backend/tools.py` | `find_conflicts` no longer echoes clause arrays in return value |
| 8 | `backend/main.py` | Imports `SYSTEM_PROMPT` from config |
| 9 | `backend/main.py` | `UPLOAD_DIR` anchored to project root via `Path(__file__).parent.parent` |
| 10 | `backend/main.py` | File validation: extension, MIME type, 10MB size limit |
| 11 | `backend/main.py` | `try/finally` in `event_stream` — files always cleaned up |
| 12 | `backend/main.py` | `assess_risk` removed from step_map, progress steps updated 5 → 4 |
| 13 | `backend/agent.py` | Imports `SYSTEM_PROMPT` from config |
| 14 | `backend/agent.py` | `redline_report` properly returned in `end_turn` branch |
| 15 | `frontend/src/App.jsx` | Added `evtSource.onerror` for network/backend crash handling |
| 16 | `frontend/src/App.jsx` | Removed client-side `DELETE /session/{id}` — backend handles cleanup |

### v1.2 — Downloads and startup (full detail in `CHANGES_1_2.md`)

| # | Change |
|---|---|
| 1 | Added JSON download button — exports full report as `clauseguard-redline-brief.json` |
| 2 | Added PDF download button — POSTs report to `/generate-pdf`, returns formatted PDF via `backend/report.py` (new file, built with ReportLab) |
| 3 | Added `start.sh` — single-command launcher: creates venv, installs deps, starts both servers, shuts down on Ctrl+C |

### v1.3 — Reliability and correctness (full detail in `CHANGES_1_3.md`)

| # | Change |
|---|---|
| 1 | Scanned PDF detection — checks avg chars/page < 80, returns actionable error message with OCR instructions |
| 2 | Raised `MAX_CLAUSES` 60 → 120 and `MAX_TOKENS` 16K → 32K to handle real enterprise contracts |
| 3 | Removed `find_conflicts` tool — eliminated a wasted API round trip; its instruction moved into the system prompt |
| 4 | Added optional Bearer token auth (`CLAUSEGUARD_API_KEY` env var) to protect `/upload` and `/analyze` endpoints |
| 5 | Switched to `anthropic.AsyncAnthropic` + `client.messages.stream()` — fixes SSE connection dropping mid-analysis caused by the sync client blocking the event loop |
| 6 | Fixed stale SSE step count after `find_conflicts` removal (4 → 3) |
| 7 | Fixed ambiguous `favor` field — rewrote system prompt definition to use company's perspective; updated UI badges to plain-English labels ("Your terms are stronger" / "Vendor has the advantage") |
| 8 | Fixed download buttons — `appendChild` before `click()`, `revokeObjectURL` delayed 1s to prevent corrupt downloads in Safari |
| 9 | Added `start.bat` (Windows) and `start.command` (macOS double-click) launchers |

---

## Key Design Decisions

**Why `assess_risk` was dropped rather than fixed:**
The tool wasn't just inaccurate — it was structurally wrong. Claude assigns risk through legal reasoning while reading the conflict. Having a separate keyword-based tool second-guess that assignment after the fact creates a two-source-of-truth problem. The right fix is to eliminate the tool and let Claude own risk assignment entirely, which it was already doing implicitly.

**Why `find_conflicts` was eventually dropped:**
It was considered whether to make it do real work (e.g., vector similarity pre-filtering). Decision: remove it entirely. The clause data is already in Claude's context window — any pre-filtering in Python would be worse than Claude's semantic reasoning. The tool existed only as a workflow checkpoint and forced a full API round trip with no analytical value.

**Why cleanup moved to `finally` instead of a client DELETE:**
Client-side cleanup is unreliable by design — tabs close, networks drop, errors happen. Server-side `finally` is the only guarantee.

**Why async client + streaming:**
The sync client blocked Python's event loop during Claude API calls (10–30s), preventing SSE keepalive frames from being sent. The browser treated the silence as a dropped connection. The async client + `stream()` yields control back to the event loop during the wait.

**Why `favor` needed a rewrite:**
After `find_conflicts` was removed, Claude no longer had a tool call anchoring its interpretation of "favor." It defaulted to a neutral third-party view ("vendor's terms favor the vendor") rather than the company's perspective. The system prompt definition was rewritten to be unambiguous.

---

## Current State

The project is at v1.3. The code is demo-ready.

Key files:
- `config.py` — all tuneable settings and the system prompt
- `backend/tools.py` — 2 tools: `extract_clauses`, `generate_redline_brief`
- `backend/main.py` — FastAPI with SSE streaming, async Claude client, optional auth
- `backend/agent.py` — CLI entry point for the agentic loop (sync client)
- `backend/report.py` — ReportLab PDF generation
- `frontend/src/App.jsx` — full React UI
- `start.sh` / `start.command` / `start.bat` — one-command launchers
- `CHANGES_1_1.md`, `CHANGES_1_2.md`, `CHANGES_1_3.md` — detailed before/after for every change

---

*ClauseGuard · Project 1/3 · BUAN 6v99.s01 · UT Dallas · April 2026*

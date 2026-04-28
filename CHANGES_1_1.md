# ClauseGuard — Changes & Rationale

A record of every change made after the initial implementation, why each was made, and what problem it solves.

---

## 1. Switched model from Opus to Sonnet

**File:** `config.py`

**Before:**
```python
MODEL = "claude-opus-4-6"
```

**After:**
```python
MODEL = os.getenv("CLAUSEGUARD_MODEL", "claude-sonnet-4-6")
```

**Why:** Opus is the most expensive model and adds no meaningful quality benefit for this task. Clause extraction and structured JSON generation are well within Sonnet's capability. The env var override means you can still run Opus for a specific session without changing code:
```bash
CLAUSEGUARD_MODEL=claude-opus-4-6 uvicorn backend.main:app --reload --port 8000
```

---

## 2. Raised MAX_TOKENS from 4096 to 16000

**File:** `config.py`

**Before:**
```python
MAX_TOKENS = 4096
```

**After:**
```python
MAX_TOKENS = 16000
```

**Why:** A typical commercial contract is 5,000–15,000 words. After extracting clauses from two contracts and running conflict analysis, Claude can easily exhaust 4096 output tokens mid-response, producing a truncated or malformed JSON brief. 16000 gives sufficient headroom for real contracts while staying well within the model's output limit.

---

## 3. Removed `assess_risk` as a tool

**Files:** `backend/tools.py`, `backend/main.py`, `backend/agent.py`, `config.py` (SYSTEM_PROMPT)

**Before:** `assess_risk` was a separate tool Claude called for each conflict. It used keyword matching to assign CRITICAL/HIGH/MEDIUM/LOW based on words like "indemnif", "terminat", "payment", etc.

**After:** Removed entirely. Risk level is now assigned by Claude directly inside each conflict object passed to `generate_redline_brief`.

**Why:** The tool created a silent inconsistency. Claude would decide a risk level through its own legal reasoning, then call `assess_risk` which might return a different level based on keywords. The result fed back into context could confuse subsequent reasoning. Claude's judgment is more accurate than keyword matching for legal risk assessment — the tool was adding noise, not signal. Removing it also eliminates an unnecessary API round-trip per conflict.

---

## 4. Moved `SYSTEM_PROMPT` to `config.py`

**Files:** `config.py`, `backend/main.py`, `backend/agent.py`

**Before:** The system prompt was copy-pasted identically into both `main.py` and `agent.py`.

**After:** Defined once in `config.py`, imported by both files.

**Why:** Two copies of the same string means updating behavior requires finding and editing both places. The existing `config.py` was already the intended single source of truth for settings — the prompt belongs there.

---

## 5. Added file validation on upload

**File:** `backend/main.py`

**Before:** No validation — any file of any size and type was accepted and saved to disk.

**After:** Three checks before saving:
- Extension must be `.pdf`
- `Content-Type` must be `application/pdf` or `application/octet-stream`
- File size must be under 10MB (configurable via `MAX_FILE_SIZE` in `config.py`)

**Why:** Without validation, a non-PDF or oversized file would be saved, passed to PyMuPDF, and either produce garbage output or crash the agent mid-analysis with no useful error message. Catching this at the upload boundary gives the user an immediate, clear error instead.

---

## 6. Anchored `uploads/` directory to project root

**File:** `backend/main.py`

**Before:**
```python
UPLOAD_DIR = Path("uploads")
```

**After:**
```python
UPLOAD_DIR = Path(__file__).parent.parent / "uploads"
```

**Why:** A relative path resolves against the current working directory of the process, not the file. Running `uvicorn` from any directory other than the project root would silently create a second `uploads/` folder in the wrong location, and session lookups would fail.

---

## 7. Raised clause cap from 40 to 60 with truncation warning

**File:** `backend/tools.py`

**Before:** Silently capped at 40 clauses with no indication to the user.

**After:** Capped at `MAX_CLAUSES` (60, configurable). If truncation occurs, returns a `truncation_warning` string that is surfaced as a status event in the UI progress bar.

**Why:** Silently dropping clauses means conflicts in the latter half of a long contract are never found, with no indication to the user that coverage is incomplete. The warning makes the limitation visible so the user can decide whether to increase the cap or split the contract.

---

## 8. Fixed `find_conflicts` to not re-inject clause arrays

**File:** `backend/tools.py`

**Before:** `find_conflicts` received both full clause arrays as arguments from Claude, returned them in the tool result, and they were re-injected into the message history.

**After:** The tool still accepts the arrays (Claude needs to pass them to trigger the call), but the return value is a lightweight confirmation object — it does not echo the arrays back.

**Why:** Claude already has the clause content in its context window from the `extract_clauses` calls. Echoing 80+ clause objects back through the tool result added significant token overhead and pushed the conversation toward the output token limit faster, increasing the risk of a truncated final report.

---

## 9. Added `try/finally` cleanup in `event_stream`

**File:** `backend/main.py`

**Before:** Session cleanup (`shutil.rmtree`) was triggered by the frontend sending a `DELETE /session/{id}` request after receiving the `complete` event. No cleanup happened on error or disconnect.

**After:** The entire `event_stream` generator is wrapped in `try/finally`. The session directory is deleted when the stream exits for any reason — success, error, or client disconnect.

**Why:** The old approach had two failure modes: the frontend might never send the DELETE (tab closed, network drop, JS error), and on error paths there was no cleanup at all. Files accumulate on disk indefinitely. The `finally` block guarantees cleanup regardless of how the stream terminates. The client-side DELETE call was also removed as it became redundant.

---

## 10. Added `onerror` handler on `EventSource`

**File:** `frontend/src/App.jsx`

**Before:** Only a custom `"error"` SSE event was handled. Built-in `EventSource` connection errors were unhandled.

**After:**
```js
evtSource.onerror = () => {
  evtSource.close();
  setErrorMsg("Connection lost. Check that the backend is running on port 8000.");
  setPhase("error");
};
```

**Why:** The browser's `EventSource` API fires two distinct things: a custom `"error"` event (sent by the server as an SSE message) and a built-in `onerror` callback (fired on connection failures, network drops, and backend crashes). These are different. Without `onerror`, a backend crash or network hiccup would leave the UI stuck in the "analyzing" spinner indefinitely with no way for the user to recover.

---

*ClauseGuard · Project 1/3 · BUAN 6v99.s01 · UT Dallas · April 2026*

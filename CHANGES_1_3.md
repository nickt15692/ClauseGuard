# ClauseGuard — Changes & Rationale (v1.3)

Changes made after v1.2. For earlier history see `CHANGES_1_1.md` and `CHANGES_1_2.md`.

---

## 1. Scanned PDF detection with actionable error

**File:** `backend/tools.py`

**Problem:** PyMuPDF's `page.get_text()` returns an empty string for image-based (scanned) PDFs. Previously, this would silently produce zero clauses and cause Claude to either fabricate output or return an empty report — with no indication to the user that the PDF was unreadable.

**Fix:** After extracting text from all pages, compute the average character count per page. If it falls below 80 characters, return an early error with an explicit message:

```python
avg_chars_per_page = total_chars / max(page_count, 1)
if avg_chars_per_page < 80:
    return {
        "success": False,
        "error": (
            f"'{party_label}' contract appears to be a scanned (image-based) PDF "
            f"with only ~{int(avg_chars_per_page)} characters per page. "
            "ClauseGuard requires text-based PDFs. "
            "Please use an OCR tool (e.g. Adobe Acrobat, pdf2searchablepdf) "
            "to convert the scanned document to a searchable PDF first."
        ),
        ...
    }
```

**Why this threshold:** A single page of a typical contract has 1,500–3,000 characters. Scanned pages produce 0–20. 80 is a conservative floor that avoids false positives (cover pages, signature pages) while reliably catching fully scanned documents.

---

## 2. Raised clause cap from 60 to 120, MAX_TOKENS from 16K to 32K

**File:** `config.py`

**Problem:** The 60-clause cap was too low for real enterprise contracts, which routinely have 80–120 numbered sections. Any contract over 60 clauses would have its latter sections silently dropped, meaning conflicts in payment schedules, IP assignment, or termination clauses at the end of a contract could be missed entirely.

**Fix:**

```python
MAX_TOKENS = 32000   # was 16000
MAX_CLAUSES = 120    # was 60
```

**Why 32K tokens:** Claude Sonnet supports up to 64K output tokens. The previous 16K limit was inherited from an earlier, more conservative estimate. With two 120-clause contracts in context, Claude needs more headroom to produce a complete, untruncated redline brief. 32K covers all realistic contracts without approaching the model's actual ceiling.

**Why 120 clauses:** Doubles the previous cap while remaining within the token budget. The truncation warning (added in v1.1) is still surfaced if even 120 clauses is exceeded, so users with unusually long contracts are notified rather than silently short-changed.

---

## 3. Removed `find_conflicts` tool — eliminated a wasted API round trip

**Files:** `backend/tools.py`, `backend/main.py`, `config.py`

**Problem:** `find_conflicts` was a passthrough tool that did no real work. It accepted both clause arrays, confirmed receipt, and returned an instruction string telling Claude to perform semantic comparison. But Claude already had both clause lists in its context window from the two `extract_clauses` calls, and the instruction duplicated guidance already in the system prompt. The tool existed as a workflow checkpoint, not as a computation.

**The cost:** Every call to `find_conflicts` forced a full API round trip — request, response, tool call, tool result, next request — adding latency with zero analytical value.

**Fix:** Remove the tool entirely. Move its semantic instruction into the system prompt so Claude reasons over both clause lists immediately after extraction:

*System prompt, step 3 (before):*
> Call find_conflicts() passing both clause arrays

*System prompt, step 3 (after):*
> Carefully analyze every meaningful conflict between the two clause lists now in your context. For each clause topic, compare the company and vendor language side-by-side...

**Impact:** Saves one complete API round trip per analysis. On a typical analysis that takes 15–25 seconds, this removes roughly 3–5 seconds of pure overhead. The agentic loop now runs in 2 tool calls (extract × 2 + generate) instead of 3, and the SSE step count was updated from 4 to 3 accordingly.

---

## 4. Optional API key authentication

**Files:** `backend/main.py`, `.env`

**Problem:** The `/upload` and `/analyze` endpoints had no authentication. Any process running on the same machine (or on a local network if the server was exposed beyond loopback) could submit contracts and trigger paid Anthropic API calls.

**Fix:** Added an optional Bearer token check using FastAPI's `HTTPBearer` dependency:

```python
_APP_API_KEY = os.getenv("CLAUSEGUARD_API_KEY")

def require_api_key(credentials: HTTPAuthorizationCredentials = Depends(_bearer)):
    if not _APP_API_KEY:
        return  # Auth disabled — local/dev mode (default)
    if not credentials or credentials.credentials != _APP_API_KEY:
        raise HTTPException(status_code=401, detail="Invalid or missing API key")
```

**Opt-in design:** If `CLAUSEGUARD_API_KEY` is not set in `.env`, the guard is a no-op and the app behaves exactly as before. To enable protection, add one line:

```bash
CLAUSEGUARD_API_KEY=your-secret-key-here
```

The `.env` file now includes this as a commented-out example. The guard applies to `/upload` and `/analyze/{session_id}` only — `/health` and `/generate-pdf` remain open.

---

## 5. Fixed SSE connection dropping mid-analysis

**File:** `backend/main.py`

**Problem:** The backend was using the synchronous `anthropic.Anthropic` client inside an `async` generator. Every call to `client.messages.create()` blocked Python's entire async event loop for the duration of the Claude API call (10–30 seconds). While the event loop was frozen, FastAPI could not send SSE keepalive frames, and the browser's `EventSource` treated the silence as a dropped connection — firing `onerror` and showing "Connection lost." before the analysis even completed.

**Fix:** Switch to the async client and `await` the call:

```python
# Before
client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)
response = client.messages.create(...)

# After
client = anthropic.AsyncAnthropic(api_key=ANTHROPIC_API_KEY)
response = await client.messages.create(...)
```

**Why it matters:** The async client yields control back to the event loop while waiting for Claude, so SSE frames continue to flow and the browser connection stays alive for the full duration of the analysis.

---

## 6. Fixed SDK streaming requirement for 32K token budget

**File:** `backend/main.py`

**Problem:** After raising `MAX_TOKENS` to 32,000 (change #2 above), the Anthropic SDK rejected non-streaming API calls with the error: *"Streaming is required for operations that may take longer than 10 minutes."* The SDK enforces streaming mode for large token budgets to prevent runaway blocking requests.

**Fix:** Replace `client.messages.create()` with `client.messages.stream()` using `get_final_message()` to collect the complete response:

```python
async with client.messages.stream(
    model=MODEL,
    max_tokens=MAX_TOKENS,
    system=SYSTEM_PROMPT,
    tools=TOOLS,
    messages=messages
) as stream:
    response = await stream.get_final_message()
```

**Why this approach:** `get_final_message()` streams the response under the hood but returns the same `Message` object that `messages.create()` would have returned, so the rest of the agentic loop (tool call parsing, stop reason checking) required no changes.

---

## 7. Fixed stale step number in SSE completion event

**File:** `backend/main.py`

**Problem:** After removing `find_conflicts` and reducing the step count from 4 to 3, the completion status event still sent `"step": 4` — one beyond the new total. This caused the progress bar to advance past its final state on completion.

**Fix:** Updated the completion event to `"step": 3, "total": 3`.

---

## 8. Fixed ambiguous `favor` field — system prompt and UI

**Files:** `config.py`, `frontend/src/App.jsx`, `frontend/src/App.css`

**Problem:** The `favor` field in each conflict object was defined as `"whose language is more favorable"` — genuinely ambiguous, because in every conflict both parties have language that is favorable to themselves. Without the `find_conflicts` tool anchoring Claude's interpretation (removed in change #3), Claude defaulted to a neutral third-party view ("vendor's terms favor the vendor") rather than the company's perspective ("company's terms are stronger for the company"). This caused every conflict to flip from `"Company"` to `"Vendor"` after the tool was removed.

**Fix (system prompt):** Rewrote the field definition to be unambiguous from the company's perspective:

```python
"favor": "<'Company' or 'Vendor' — from the company's perspective, which party's language
gives the company the stronger position: 'Company' if the company's standard terms are more
protective of the company's interests and should be retained; 'Vendor' only if the vendor's
proposed terms are genuinely more favorable or balanced from the company's standpoint>"
```

**Fix (UI):** Replaced the plain `"Favors: Company"` / `"Favors: Vendor"` text with color-coded badges that use plain-English labels:

- Green pill: **✓ Your terms are stronger**
- Orange pill: **⚠ Vendor has the advantage**

This eliminates ambiguity about what "Company" and "Vendor" meant in context, and makes the negotiating posture on each conflict immediately scannable without reading the fine print.

---

## 9. Fixed PDF and JSON download buttons

**File:** `frontend/src/App.jsx`

**Problem:** Both download buttons used `a.click()` on a detached DOM element and called `URL.revokeObjectURL(url)` immediately after. Two distinct bugs:

1. Clicking a detached anchor (`createElement` without `appendChild`) silently fails in Safari and some Chromium builds — the download never starts.
2. `revokeObjectURL` was called synchronously after `click()`, before the browser had read the blob. On slower machines or large files this freed the blob URL mid-download, producing a corrupt or empty file.

**Fix:**

```js
document.body.appendChild(a);
a.click();
document.body.removeChild(a);
setTimeout(() => URL.revokeObjectURL(url), 1000);
```

Applied to both `downloadPDF` and `downloadJSON`.

---

## 10. Added Windows startup script (`start.bat`)

**File:** `start.bat` (new)

**Problem:** The existing `start.sh` and `start.command` scripts only work on macOS/Linux. Windows users had no equivalent double-clickable launcher.

**Fix:** Created `start.bat`, a Windows batch file that mirrors the Mac script's behaviour:

1. Checks that `.env` exists with the API key
2. Checks that Python and Node.js are on `PATH` (with install instructions if missing)
3. Creates the Python virtual environment if absent
4. Runs `pip install -r requirements.txt`
5. Runs `npm install` in the frontend directory
6. Launches the backend and frontend in two separate named terminal windows (`ClauseGuard Backend` / `ClauseGuard Frontend`)

**Why two windows:** Unlike the Mac script (which uses background processes in a single terminal), Windows batch files have no clean equivalent of `wait` + `trap SIGINT`. Opening each server in its own `cmd /k` window gives each server its own visible log stream and lets the user stop them independently by closing the window — more transparent and reliable than background process management in batch.

**Usage:** Double-click `start.bat` in File Explorer. Windows may show a SmartScreen prompt on first run — click "More info → Run anyway" (the script is not signed).

---

## 11. Added macOS double-click launcher (`start.command`)

**File:** `start.command` (new)

**Problem:** Double-clicking `start.sh` in macOS Finder opens the file in a text editor rather than running it. The `.sh` extension has no default executable association in Finder.

**Fix:** Created `start.command` — an exact copy of `start.sh` with the `.command` extension, which macOS recognises as a double-clickable terminal script. Made executable with `chmod +x`. macOS will prompt for permission on first run — click Open.

---

*ClauseGuard · Project 1/3 · BUAN 6v99.s01 · UT Dallas · April 2026*

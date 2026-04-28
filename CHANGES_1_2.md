# ClauseGuard — Changes & Rationale (v1.2)

Changes made after v1.1. For the full v1.1 history see `CHANGES_1_1.md`.

---

## 1. Added JSON download

**File:** `frontend/src/App.jsx`

**What:** A "↓ JSON" button appears in the results view after analysis completes. Clicking it downloads the full report as a formatted JSON file (`clauseguard-redline-brief.json`).

**Why:** The report data already lives in the browser after analysis — this just needed a button to trigger a download. No backend involvement required. Useful for anyone who wants to pipe the results into another tool or inspect the raw output.

---

## 2. Added polished PDF download

**Files:** `backend/report.py` (new), `backend/main.py`, `frontend/src/App.jsx`, `frontend/src/App.css`, `requirements.txt`

**What:** A "↓ PDF" button appears alongside the JSON button. Clicking it POSTs the report data to a new `/generate-pdf` endpoint, which generates and returns a formatted PDF.

**Why:** A presentable PDF is what you'd actually hand to a lawyer or send to a counterparty. The JSON download is for developers; the PDF is for everyone else.

**PDF layout:**
- Cover page with title, generation date, and a CRITICAL/HIGH/MEDIUM/LOW summary badge row
- One card per conflict, sorted by risk level (CRITICAL first), each containing:
  - Colored risk badge + topic heading + which party's language is more favorable
  - Side-by-side clause comparison (Your Contract vs Vendor Contract) with section references
  - "Why This Conflicts" explanation
  - "Suggested Resolution" highlighted in blue
- Closing recommendation section
- Navy header bar and page-numbered footer on every page

**Implementation notes:**
- Built with `reportlab` (added to `requirements.txt`)
- The frontend POSTs the report JSON it already has in state — no session dependency, no cleanup timing issue
- The backend `/generate-pdf` endpoint accepts the report as a JSON body and returns the PDF as a file download
- PDF generation lives in `backend/report.py` to keep it separate from routing logic

---

## 3. Added `start.sh` startup script

**File:** `start.sh` (new)

**What:** A single shell script that sets up and launches the entire app. Run with `bash start.sh` from the VS Code terminal or any Mac terminal.

**What it does on each run:**
1. Checks that `.env` exists with the API key
2. Checks that Node.js and Python 3 are installed
3. Creates the Python virtual environment if it doesn't exist yet
4. Runs `pip install -r requirements.txt` — picks up any new dependencies automatically
5. Runs `npm install` in the frontend directory
6. Starts the backend (uvicorn) and frontend (vite) as background processes
7. Shuts both down cleanly on Ctrl+C

**Why:** Previously required two separate terminals and manual setup steps. The script handles everything in one command and keeps the terminal open with visible error messages if anything goes wrong.

---

*ClauseGuard · Project 1/3 · BUAN 6v99.s01 · UT Dallas · April 2026*

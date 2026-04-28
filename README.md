# ClauseGuard

**AI-powered contract conflict detector.** Upload two contract PDFs — your company's standard terms and a vendor's proposed terms — and a Claude-powered agent finds every conflicting clause, ranks them by legal risk, and produces a structured redline brief with suggested resolution language.

Built with the Anthropic SDK from scratch (no no-code platforms). Streams live tool call progress to the browser as the agent works.

---

## Features

- Detects and ranks conflicts across two contracts by severity (Critical / High / Medium / Low)
- Generates resolution language for each conflict from your company's perspective
- Live progress bar via Server-Sent Events — watch tool calls fire in real time
- Export results as JSON or formatted PDF
- Scanned PDF detection with actionable error messages
- Optional Bearer token auth for protecting endpoints
- One-command startup on Mac, Linux, and Windows

---

## Tech Stack

| Layer | Technology |
|---|---|
| AI agent | Anthropic SDK (raw agentic loop, async streaming) |
| Backend | FastAPI + uvicorn |
| PDF parsing | PyMuPDF |
| PDF export | ReportLab |
| Frontend | React + Vite |
| Model | claude-sonnet-4-6 (configurable) |

---

## What You're Running

| Component | What it does | Port |
|---|---|---|
| FastAPI backend | Runs the Claude agent, handles file uploads | 8000 |
| React frontend | Upload UI + results dashboard | 3000 |

You need **two terminals open** — one for the backend, one for the frontend.

---

## Prerequisites

Make sure you have these installed:

| Tool | Check | Install |
|---|---|---|
| Python 3.10+ | `python3 --version` | python.org |
| Node.js 18+ | `node --version` | nodejs.org |
| npm | `npm --version` | comes with Node |
| Anthropic API key | — | console.anthropic.com |

---

## Step 1 — Get your API key into the project

```bash
cd clauseguard
cp .env.example .env
```

Open `.env` and replace `your_api_key_here` with your actual key:

```
ANTHROPIC_API_KEY=sk-ant-api03-xxxxxxxxxxxxxxxx
```

---

## Step 2 — One-command startup (recommended)

**Mac (Terminal):**
```bash
cd clauseguard
bash start.sh
```

**Mac (double-click):** Open Finder → `clauseguard/` → double-click `start.command`

**Windows:**
```
start.bat
```

`start.sh` / `start.command` / `start.bat` will create the venv, install all dependencies, and start both servers automatically. Press `Ctrl+C` to shut everything down.

---

## Manual setup (alternative)

If you prefer to run each server yourself:

### Backend (Terminal 1)

```bash
# From the clauseguard/ folder:
python3 -m venv venv
source venv/bin/activate          # Mac / Linux
# OR
venv\Scripts\activate             # Windows

pip install -r requirements.txt
uvicorn backend.main:app --reload --port 8000
```

You should see:
```
INFO:     Uvicorn running on http://0.0.0.0:8000
INFO:     Application startup complete.
```

### Frontend (Terminal 2)

```bash
cd clauseguard/frontend
npm install
npm run dev
```

You should see:
```
  VITE v5.x  ready in XXX ms
  ➜  Local:   http://localhost:3000/
```

Your browser should open automatically. If not, go to **http://localhost:3000**

---

## Step 3 — Run the demo

1. The app opens showing two upload zones
2. Upload `sample_contracts/company_standard_terms.pdf` on the left
3. Upload `sample_contracts/vendor_proposed_terms.pdf` on the right
4. Click **Analyze Contracts →**
5. Watch the progress bar as the agent calls each tool
6. The full redline brief appears with all conflicts ranked by risk
7. Use **Download JSON** or **Download PDF** to export the report

---

## What to show during the 10-minute presentation

```
0:00  Open browser → localhost:3000
1:00  Upload both sample PDFs (show the filenames)
2:00  Click Analyze — switch to Terminal 1 so audience sees tool calls printing live
4:30  Switch back to browser — walk through the CRITICAL conflict (Liability cap)
6:30  Read the resolution language Claude generated
8:00  Show BUILD vs BEND slide — explain 5/6 BUILD score
9:00  Business case — who buys this?
```

**Pro tip:** Keep Terminal 1 visible on a second screen or split view during the demo.
The audience seeing `[Tool] extract_clauses()` → `[Tool] extract_clauses()` → `[Tool] generate_redline_brief()`
printing live is your biggest wow moment.

---

## Configuration

All tuneable settings live in `config.py`:

| Setting | Default | Override |
|---|---|---|
| Model | `claude-sonnet-4-6` | Set `CLAUSEGUARD_MODEL` env var |
| Max output tokens | `32000` | Edit `MAX_TOKENS` in `config.py` |
| Max file size | `10MB` | Edit `MAX_FILE_SIZE` in `config.py` |
| Max clauses per contract | `120` | Edit `MAX_CLAUSES` in `config.py` |
| API auth (optional) | disabled | Set `CLAUSEGUARD_API_KEY` env var |

To use a different model without editing code:
```bash
CLAUSEGUARD_MODEL=claude-opus-4-6 uvicorn backend.main:app --reload --port 8000
```

To require a Bearer token on `/upload` and `/analyze`:
```bash
CLAUSEGUARD_API_KEY=your-secret uvicorn backend.main:app --reload --port 8000
```

---

## Troubleshooting

**Backend won't start:**
```bash
# Make sure venv is activated — you should see (venv) in your prompt
# Then try:
pip install -r requirements.txt --force-reinstall
```

**"ANTHROPIC_API_KEY not found" error:**
```bash
# Check your .env file exists and has no spaces around the = sign:
cat .env
# Should show: ANTHROPIC_API_KEY=sk-ant-...
```

**Frontend can't connect to backend (CORS error):**
```bash
# Make sure backend is running on port 8000 — not 8001 or another port
# Check Terminal 1 shows: Uvicorn running on http://0.0.0.0:8000
```

**"File too large" error:**
- PDFs must be under 10MB
- If testing with large contracts, increase `MAX_FILE_SIZE` in `config.py`

**Analysis returns no conflicts:**
- This can happen if the PDFs are scanned images (not text-based)
- The sample contracts included are text-based and will always produce results
- If testing with your own PDFs, make sure they are text-searchable

**"Contract has N sections — only the first 120 were analyzed" warning:**
- The agent caps extraction at 120 clauses per contract for token efficiency
- You'll see this warning in the progress bar if your contract is very long
- Increase `MAX_CLAUSES` in `config.py` if you need full coverage

**npm install fails:**
```bash
# Try clearing npm cache:
npm cache clean --force
npm install
```

---

## Project Structure (for the presentation)

```
clauseguard/
├── config.py                          ← Single source of truth (model, prompt, limits)
├── requirements.txt                   ← Python dependencies
├── .env                               ← Your API key (never commit this)
├── start.sh                           ← One-command launcher (Mac/Linux)
├── start.command                      ← Double-click launcher (macOS Finder)
├── start.bat                          ← One-command launcher (Windows)
│
├── backend/
│   ├── tools.py                       ← 2 tool functions + JSON schemas for Claude
│   ├── agent.py                       ← The agentic loop (CLI entry point)
│   ├── main.py                        ← FastAPI: /upload + /analyze SSE stream
│   └── report.py                      ← ReportLab PDF generation for /generate-pdf
│
├── frontend/
│   └── src/
│       ├── App.jsx                    ← Full React UI (includes download buttons)
│       └── App.css                    ← Legal-tech design system
│
├── sample_contracts/
│   ├── company_standard_terms.pdf     ← Demo Contract A (10 deliberate conflicts)
│   └── vendor_proposed_terms.pdf      ← Demo Contract B
│
├── scripts/
│   └── build_presentation_v3.js       ← Regenerates the PPTX if needed
│
└── ClauseGuard_Presentation_v3.pptx   ← Ready-to-present slides
```

---

## Regenerating the presentation (if needed)

```bash
# From clauseguard/ folder:
node scripts/build_presentation_v3.js
```

Requires `pptxgenjs` globally installed:
```bash
npm install -g pptxgenjs
```

---

## License

MIT


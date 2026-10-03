# DDD AI Workforce Management System — v6.0

*Digital Divide Data — Changing How the World Works.*

Time clock, 8-hour tracker, attendance, leave, live supervisor monitor and the **Mr. Uber • 8u113t** bilingual (English / Kiswahili) assistant, built to run a workforce of **550 employees** on one machine and to be hosted on your own domain.

---

## 1. Quick start

| | Windows | Linux / macOS |
|---|---|---|
| Install (once) | `SETUP.bat` | Node.js 22.13+, then `npm install --omit=dev` |
| Run on this PC / office LAN | `START_DDD.bat` | `./START_DDD.sh` |
| Put online + keep running 24/7 | `DDD_HOSTING.bat` | `./DDD_HOSTING.sh` |
| Admin tools (logs, backups, CSV import) | `DDD_ADMIN.bat` | see §7 |

Open `http://localhost:8765`. Staff on the same network use the **LAN** address printed in the console.

**Fresh-database demo accounts.** Change these before going live (Settings → Security):

| ID | Password | Role |
|---|---|---|
| EMP-312 | sarah123 | Employee |
| SUP-101 | supervisor123 | Supervisor |
| MGR-001 | manager123 | Manager |
| ADM-001 | admin123 | Admin |
| DEV-001 | DDD@SuperDev2026! | SuperAdmin |

Demo accounts are created **only on an empty database** and are no longer reset on every start. Lost the DEV-001 password? Set `SUPER_ADMIN_PASS` in `.env` and restart.

---

## 2. Hosting Centre (`DDD_HOSTING.bat` / `DDD_HOSTING.sh`)

| # | Option | Best for | Permanent? |
|---|---|---|---|
| 1 | **Custom domain** with Caddy (free automatic HTTPS) | Your own PC/server with a public IP | Yes (boot task / systemd) |
| 2 | **Netlify** | Hosting the web page on Netlify | The page yes; backend via 1/3/6–8 |
| 3 | **Cloudflare Tunnel** ⭐ | Most offices: your domain, no router setup, free | Yes (system service) |
| 4 | Cloudflare Quick Tunnel | Instant demo link | No (random URL) |
| 5 | ngrok | Quick link, free static domain | While running |
| 6 | Fly.io | Managed cloud, Johannesburg region | Yes |
| 7 | Render | Git-based deploy (`render.yaml`) | Yes (paid plan + disk) |
| 8 | Railway | CLI deploy (`railway.json`) | Yes (add a volume) |
| 9 | **Run forever** | Auto-start at boot, auto-restart on crash | Yes |
| 10 | Docker Compose | Any VPS (optional HTTPS profile) | Yes |

**Recommended setup for an office:** option **9** (run forever) + option **3** (Cloudflare Tunnel). You get your own HTTPS domain, no router port-forwarding, and both parts start themselves after a power cut.

**About Netlify:** Netlify serves static websites and serverless functions. It cannot run DDD's always-on server, WebSocket live monitor or database. Option 2 therefore publishes the web app to Netlify and points it at your backend (from option 1, 3, 6, 7 or 8). The script builds the bundle (`config.js` → your backend URL) and adds the Netlify site to `ALLOWED_ORIGINS`.

**About "running for eternity":** no hosting is literally permanent. DDD gets as close as is practical:
- The server restarts itself within seconds of any crash (watchdog, systemd, PM2 or Docker).
- It starts at boot, before anyone logs in.
- Caddy retries for 10 s during a restart, so users don't see errors.
- The database is snapshotted every hour (48 kept) with consistent online backups.
- `/api/health` and `/api/ready` let any platform monitor it.

Keep the machine powered (UPS recommended), and copy a backup off-site regularly (`DDD_ADMIN.bat` → 6).

---

## 3. What changed from v5 — architecture review

v5 was a single 1,300-line `server.js`. v6 is layered so each concern can be reasoned about, tested and replaced on its own:

```
server.js                 boot sequence + graceful shutdown
src/config.js             one validated, frozen config (.env + env vars)
src/core/                 time (EAT), buffered logger, typed HTTP errors, roles
src/db/                   SQLite access + statement cache, versioned migrations, seed
src/security/             scrypt passwords, DB-backed sessions, rate limits, headers/CORS
src/http/middleware.js    auth, role guards, audit
src/services/             presence (live status), archive (removal dossiers)
src/services/chat/        the ML assistant (see §4)
src/routes/               auth · work · leave · chat · notes · users · admin
src/realtime/             WebSocket gateway
src/jobs/                 inactivity alerts, retention, hourly backups
public/                   the web app (only folder served over HTTP)
tools/                    deploy helper, CSV import, load test
deploy/                   Caddy, Docker, Fly, Render, Railway, Netlify, PM2, systemd, Windows watchdog
```

### Defects fixed

| Severity | v5 problem | v6 fix |
|---|---|---|
| Critical | Any schema version change ran `DROP TABLE` on everything (all history lost on upgrade) | Forward-only, additive migrations in transactions; v4/v5 databases upgrade in place |
| Critical | `express.static(__dirname)` served the app folder: source code and any data folder placed beside it | Only `public/` is served |
| Critical | Wrong-password message revealed which other account the password belongs to | One generic message, timing-equalised for unknown IDs |
| High | Demo passwords re-applied on every boot, undoing admin changes | Seed only on an empty DB; explicit recovery via `SUPER_ADMIN_PASS` |
| High | XSS: chat, notes, names and leave reasons inserted with `innerHTML` | Escaping everywhere + a whitelist markdown renderer; strict CSP |
| High | CORS reflected any origin with credentials | Allow-list (`ALLOWED_ORIGINS`), WebSocket origin check |
| High | Inactivity alerts could never fire: each heartbeat reset "last activity" | Client reports real input idle time (skew-proof duration) |
| High | Generated passwords written to disk in plain text | Shown once; file logging only if `DDD_LOG_GENERATED_PASSWORDS=1` |
| Medium | `/api/insights`, `/api/system`, `/api/export.csv` called but missing; supervisor records query used a non-existent column | Implemented and fixed |
| Medium | Sync bcrypt froze the server during login rushes | scrypt on the thread pool; legacy bcrypt hashes verified then upgraded |
| Medium | Sessions in memory: every restart logged everyone out | SHA-256-hashed tokens in SQLite with a memory cache |
| Medium | One socket per user: closing a 2nd tab showed a working employee offline | Multi-tab presence; dead sockets reaped by ping/pong |
| Medium | Port conflict handler ran `taskkill /F` on whatever owned the port | Clear error message instead |
| Low | Leave could be self-approved / reviewed twice; no date validation | Guards + validation; employee notified live of decisions |

### Built for 550 employees
- **Seat capacity** enforced (`DDD_MAX_EMPLOYEES=550`); disable or remove an account to free a seat.
- **Database:** WAL mode, prepared-statement cache, indexes on every hot query, paginated lists, transactional multi-step writes.
- **Live updates:** broadcasts go to supervisors only (O(supervisors), not O(everyone)).
- **Office networks:** rate limits are sized for 550 people behind one office NAT IP; brute force is stopped per account (8 failures → 15-minute lock).
- **Why a single process:** live presence and rate limits live in memory, and SQLite has one writer, so clustering would split state. One Node process serves 550 comfortably (measured below).

### Measured: 550 simultaneous employees

Measured with `node tools/loadtest.js --users=550` on **one CPU core**, with the load generator sharing that core:

| Phase | Result |
|---|---|
| 550 WebSocket connections registered | 550/550, p95 259 ms |
| Clock-in / chat / break / resume, all 550 at once | 0 errors; p95 0.9–3.4 s |
| Supervisor live monitor during the rush | p50 6 ms |
| 550 simultaneous logins | 0 errors; 23 s total (CPU-bound by design, see below) |
| Errors across ~5,500 requests | **0** |
| JS heap | 14 MB |

The login figure follows from scrypt's deliberate cost (38 ms × 550 on one core). On a 4-core server, the same worst case finishes in about 5 s, and real arrivals spread over 30+ minutes. Run the test on your own hardware before go-live.

---

## 4. Mr. Uber • 8u113t — the assistant

```
language ID → intent (Naive Bayes, online) → context rewriting (memory)
  → BM25F retrieval + bilingual expansion + typo correction + learned priors
  → calibrated confidence → extractive answer / grounded LLM / honest fallback
```

**Retrieval and understanding**
- **BM25F retrieval** with field weighting (title > category > body), term-frequency saturation and length normalisation.
- **Index caching:** the index is built once and rebuilt only when notes change; v5 rebuilt it on every message.
- **Bilingual concept expansion** bridges how people ask and how policy is written ("time off" / "likizo" → *Annual Leave Policy*). **Concept pooling** stops one word from counting as many synonyms.
- **Typo and morphology tolerance:** Damerau–Levenshtein correction and prefix variants ("levae", "harassed" → "harassment").
- **Intent classification:** multinomial Naive Bayes over all evidence, replacing v5's "first keyword list wins". It rejects low-evidence guesses.

**Answering**
- **Calibrated confidence** combines query coverage, term match ratio and the top-1/top-2 margin.
- **Low confidence is never bluffed:** the assistant says it doesn't know, points to reception, and logs a knowledge gap.
- **Extractive answers** return the most relevant sentences instead of whole documents.
- **Conversation memory** resolves follow-ups ("how many days is it?", "tell me more").

**Learning from use**
- 👍/👎 feedback updates a Beta prior per note and adds confirmed examples to the intent model live, with no retraining or restart.
- Supervisors see **Knowledge Gaps** (unanswered topics ranked by frequency) and click **Teach**. The answer becomes a note, and rephrased versions of the question are then answered.

**Optional generative mode**
- Set `ANTHROPIC_API_KEY` for natural-language answers grounded strictly on the retrieved notes, streamed token-by-token.
- High-confidence questions are still answered instantly from the knowledge base.

**Responsive chat UI**
- Replies stream word by word over SSE.
- Suggestion chips, copy and retry, and history restored on return.
- Mobile layout uses `100dvh` (keyboard-safe), safe-area insets and a 16 px input (prevents iOS zoom).
- Auto-scroll respects a reader scrolling back.
- Screen-reader live region.

**Measured on the test set:** 20/20 correct (English, Kiswahili, typos, follow-ups, honest "don't know"); typical retrieval latency about 6 ms.

---

## 5. Configuration (`.env`)

| Variable | Default | Purpose |
|---|---|---|
| `PORT` / `HOST` | 8765 / 0.0.0.0 | Listen address |
| `PUBLIC_URL` | — | Your public address (set by the hosting scripts) |
| `TRUST_PROXY` | 0 | `1` behind Caddy / Cloudflare / Fly / Render (correct client IPs, secure cookies) |
| `ALLOWED_ORIGINS` | — | Extra sites allowed to call the API (e.g. your Netlify URL) |
| `DDD_DATA_DIR` | `%APPDATA%\DDD_WorkforceSystem` / `~/DDD_WorkforceSystem` | Data, logs, backups. Use an absolute path for services |
| `DDD_MAX_EMPLOYEES` | 550 | Seat capacity |
| `SESSION_TTL_HOURS` | 12 | Session length |
| `INACTIVITY_MIN` | 45 | Inactivity alert threshold |
| `BACKUP_EVERY_HOURS` / `BACKUP_KEEP` | 1 / 48 | Hot backups |
| `ANTHROPIC_API_KEY` / `ANTHROPIC_MODEL` | — / claude-haiku-4-5-20251001 | Optional generative answers |
| `SUPER_ADMIN_PASS` | — | Re-applies the DEV-001 password at start (recovery) |
| `RATE_*` | sized for 550 | Per-IP flood guards |

---

## 6. Upgrading from v4/v5

1. Stop the old server and **copy your data folder somewhere safe**.
2. Unzip v6 into a new folder and run `SETUP.bat`.
3. v6 uses the same default data folder and database file name as v5 (`DDD_WorkforceSystem\database\ddd.sqlite3`), so existing accounts and history are picked up and upgraded in place. Old bcrypt passwords keep working.
4. If your data lives elsewhere, point `DDD_DATA_DIR` at the folder containing `database\`. For example, your `software_info.txt` shows `...\Downloads\b\ddd_data` with a file named `ddd_workforce.sqlite3`. In that case, copy that file to `ddd.sqlite3` in the same folder first.

---

## 7. Operations

- **Bulk onboarding:** `node tools/import-employees.js staff.csv`. See `tools/employees_template.csv`. Existing IDs are skipped, and seat capacity is enforced.
- **Health:** `node tools/deploy-helper.js health [https://your.domain]`
- **Load test:** `node tools/loadtest.js --url=http://localhost:8765 --users=550 --cleanup`
- **Logs:** `<data>/logs/{events,audit,logins,chat,alerts,errors}`
- **Backups:** `<data>/backups`
- **Removed-employee dossiers:** `<data>/removed_employees`
- **Restore a backup:** stop the server, copy a `backup_*.sqlite3` over `database/ddd.sqlite3`, then start the server.
- **Policy content:** the seeded notes, such as statutory deductions (SHA/SHIF, NSSF, Housing Levy), are examples. Have HR review the knowledge base before launch.

*DDD — Digital Divide Data · AI Workforce System v6.0 · Kenya (EAT)*

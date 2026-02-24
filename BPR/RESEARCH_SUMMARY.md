# BPR Bot - Research Summary & Master Plan (Phase 0)

*Updated: 2026-02-24 — incorporates broker intel, system discovery, and user requirements*

---

## 0. Environment & Broker Discovery

### 0.1 Local MT5 Installation (Discovered)

MT5 is already installed via the **official MetaQuotes Wine bundle** (Wine 10.0, Rosetta 2 on Apple Silicon):

| Component | Path |
|-----------|------|
| **App bundle** | `/Applications/MetaTrader 5.app` (v5.0.5260) |
| **Wine binary** | `/Applications/MetaTrader 5.app/Contents/SharedSupport/wine/bin/wine64` |
| **Wine prefix** | `~/Library/Application Support/net.metaquotes.wine.metatrader5/` |
| **terminal64.exe** | `...drive_c/Program Files/MetaTrader 5/terminal64.exe` |
| **metaeditor64.exe** | `...drive_c/Program Files/MetaTrader 5/metaeditor64.exe` |
| **metatester64.exe** | `...drive_c/Program Files/MetaTrader 5/metatester64.exe` |
| **MQL5 root** | `...drive_c/Program Files/MetaTrader 5/MQL5/` |
| **Experts dir** | `.../MQL5/Experts/` (has Advisors/, Examples/, Free Robots/) |
| **Include dir** | `.../MQL5/Include/` (standard library with Trade/Trade.mqh) |
| **Tester dir** | `.../MetaTrader 5/Tester/` (empty — no backtests run yet) |
| **Config dir** | `.../MetaTrader 5/config/` (terminal.ini, common.ini, etc.) |

**No Parallels needed.** The Wine bundle is sufficient for both development and automation.

### 0.2 Broker: GTC Global Trade

| Detail | Value |
|--------|-------|
| **Portal** | mygtcportal.com (main site: gtcfx.com) |
| **MT5 server** | `GTCGlobalTrade-Server` |
| **Login** | `5935483` |
| **Account types** | Standard (1:2000), Pro (1:2000), ECN (1:500) |
| **Likely account mode** | **Hedging** (most retail forex brokers; needs confirmation via diagnostic script) |
| **Server GMT offset** | **Unknown — likely GMT+2 / GMT+3 (DST)** (standard broker convention; needs confirmation) |
| **Symbols** | Likely `XAUUSD`, `BTCUSD` (standard naming; needs confirmation) |
| **Filling modes** | Unknown (needs confirmation) |
| **Regulation** | FCA + ASIC (tier-1), VFSC + FSC (tier-3 offshore) |
| **Caution** | Mixed reviews on withdrawals for large amounts; platform stability generally positive |

### 0.3 What Must Be Confirmed (Diagnostic Script)

Before coding the EA, a small MQL5 script must be run on the live server to get definitive answers:

```
1. ACCOUNT_MARGIN_MODE         → hedging or netting?
2. TimeCurrent() - TimeGMT()   → server GMT offset (hours)
3. Symbol names for gold/BTC   → exact strings (XAUUSD? XAUUSDm? GOLD?)
4. SYMBOL_FILLING_MODE         → FOK, IOC, or both?
5. SYMBOL_TRADE_EXEMODE        → instant, market, exchange, request?
6. SYMBOL_VOLUME_MIN/MAX/STEP  → lot sizing constraints per symbol
7. SYMBOL_TRADE_TICK_VALUE/SIZE → for position sizing formula
8. SYMBOL_POINT / SYMBOL_DIGITS → price precision per symbol
```

### 0.4 Existing Code References

| File | Description | Usefulness |
|------|-------------|------------|
| `github.com/borghei/MQ5-BPR/BPR_Bot.mq5` (V1) | Single FVG detector mislabeled as BPR. 457 lines. Uses ATR displacement. | Low — wrong strategy. |
| `github.com/borghei/MQ5-BPR/BPR_Bot_V2.mq5` (V2) | Real BPR detector. 1413 lines. 10 critical bugs. | Medium — correct BPR overlap logic, but needs full rewrite. |
| `~/Desktop/All/BPR/V2/ICT_BPR.mq5` | **Indicator** (not EA). Proper FVG/BPR detection with ATR-based filter, IFVG inversion logic, proximal/distal zones, alert system. 630 lines. | **High** — cleanest FVG detection code. Good reference for filter thresholds. |

**Key insight from ICT_BPR.mq5 indicator**: It uses a 4-tier ATR-based FVG filter (Very Aggressive: 0.1x ATR, Aggressive: 0.2x, Defensive: 0.3x, Very Defensive: 0.5x) and correctly identifies FVG inversions (when price closes through an FVG, it flips polarity). We should incorporate the ATR-based filter into the EA.

---

## 1. Strategy Understanding

### 1.1 Fair Value Gaps (FVGs)

An FVG is a three-candle price imbalance where price moved so aggressively that it left an "untraded" zone. The gap is measured between the **wicks** of candles 1 and 3 (not bodies).

**Bullish FVG** (bars indexed present-to-past: `[i]`, `[i+1]`, `[i+2]`):
- `Low[i] > High[i+2]` — the low of the newest candle is above the high of the oldest candle
- FVG zone: `[High[i+2], Low[i]]`
- Represents aggressive buying — price expected to retrace into this zone and find support

**Bearish FVG** (same indexing):
- `High[i] < Low[i+2]` — the high of the newest candle is below the low of the oldest candle
- FVG zone: `[High[i], Low[i+2]]`
- Represents aggressive selling — price expected to retrace and find resistance

**Key findings:**
- An FVG that gets violated (price closes through it) becomes an **Inversion FVG (IFVG)** — polarity flips
- Micro-FVGs (tiny gaps) are noise — use ATR-based filter (0.1x to 0.5x ATR threshold, configurable)
- FVGs should NOT be traded in isolation — need HTF trend + session + structure confluence

### 1.2 Balanced Price Ranges (BPRs)

A BPR is the **overlapping zone** where a bullish FVG and a bearish FVG coexist. Double imbalance = stronger zone.

**Formation:**
1. Price makes a strong move in one direction → leaves an FVG
2. Price reverses aggressively → leaves an opposite FVG
3. If the two FVGs **overlap in price** → the overlap = BPR
4. BPR bounds = `[max(bull_FVG_low, bear_FVG_low), min(bull_FVG_high, bear_FVG_high)]`

**Direction = which FVG formed LAST:**
- **Bullish BPR**: bearish FVG first → bullish FVG overlaps it → LONG entries
- **Bearish BPR**: bullish FVG first → bearish FVG overlaps it → SHORT entries

**SL placement (PATCH 2):**
- `full_high` = max of both FVGs' upper edges
- `full_low` = min of both FVGs' lower edges
- For LONG: SL = `full_low - buffer`
- For SHORT: SL = `full_high + buffer`

### 1.3 Market Structure

**Swing detection**: Bar whose High > High of N bars on each side (swing high). Default N=5 for reliability, N=3 for responsiveness.

**Classification** (need 3-4 swing points minimum):
- **Bullish**: HH + HL sequence
- **Bearish**: LH + LL sequence
- **Range**: mixed — no clear bias

**Multi-timeframe**: Trade direction of HTF. Ratio 4:1 (e.g., H1 structure, M15 entry).

### 1.4 Session Filtering

| Session | UTC Hours | Use |
|---------|-----------|-----|
| Asia (block) | 22:00 - 08:00 | No new entries |
| London | 08:00 - 17:00 | Best for entries |
| New York | 13:00 - 22:00 | Best for entries |
| London+NY overlap | 13:00 - 17:00 | Highest probability |

---

## 2. Key Technical Challenges & Solutions

| Challenge | Solution |
|-----------|----------|
| `TimeGMT()` broken in Tester | Use `TimeCurrent() + configurable GMT offset` input per broker |
| FVG arrays grow unbounded (V2 bug) | Fixed-size arrays with aging — remove FVGs > lookback bars old; daily reset |
| Bar indices shift every bar | Store `datetime` timestamps, use `iBarShift()` when needed |
| Filling mode varies per broker | `CTrade::SetTypeFillingBySymbol()` auto-detection |
| Tick value changes mid-session | Read `SYMBOL_TRADE_TICK_VALUE` fresh per trade + `OrderCalcProfit()` fallback |
| Wine + macOS automation | Command-line via `wine64 terminal64.exe /config:...` from macOS shell |
| XAUUSD vs EURUSD point sizes | All sizing via dynamic `SYMBOL_POINT`, `SYMBOL_DIGITS`, `SYMBOL_TICK_VALUE` |
| BTCUSD high volatility | ATR-based FVG filter auto-adapts; per-pair config profiles |

---

## 3. Multi-Broker / Multi-Pair Architecture

Per the user's requirements, the system must support **multiple brokers** and **per-pair configs**.

### 3.1 Config System Design

```
configs/
├── brokers/
│   ├── gtc_global.json          # GTC-specific: server name, GMT offset, symbol names
│   └── another_broker.json      # Future broker
├── pairs/
│   ├── XAUUSD.json              # Gold-specific: timeframes, swing lookback, FVG filter, R:R
│   ├── BTCUSD.json              # BTC-specific params
│   └── EURUSD.json              # Future pair
└── profiles/
    ├── aggressive.json           # 5-10% risk, wide parameters
    └── medium.json               # 2-3% risk, conservative parameters
```

### 3.2 How It Works in MQL5

Since MQL5 EAs use `input` parameters (set at load time), we have two approaches:

**Approach A — Single EA with .set files (Recommended):**
- One `BPR_Bot.mq5` file
- Per-pair `.set` files (MT5 native parameter preset format) stored in `MQL5/Presets/`
- Load the appropriate preset per chart: `XAUUSD.set`, `BTCUSD.set`, etc.
- The automation scripts generate these `.set` files from the JSON configs

**Approach B — Per-pair EA copies:**
- Not recommended — hard to maintain, same code duplicated

### 3.3 Broker-Specific Parameters (in EA inputs)

```mql5
// Broker settings
input int      Inp_GMTOffset          = 2;      // Server GMT offset (hours) — GTC likely +2/+3
input int      Inp_MagicNumber        = 240001;  // Unique per pair+broker combo
```

### 3.4 Pair-Specific Considerations

| Aspect | XAUUSD (Gold) | BTCUSD (Bitcoin) |
|--------|---------------|------------------|
| Typical spread | 15-30 points | 50-500 points |
| Volatility | High | Very high |
| Point value | ~$0.01/point | Varies wildly |
| Digits | 2 (e.g., 2650.50) | 2 (e.g., 95000.00) |
| FVG filter | Defensive (0.3x ATR) | Very Defensive (0.5x ATR) |
| Swing lookback | 5 | 5-7 |
| BPR lookback | 30 bars | 20 bars (faster moves) |
| Session filter | Strong (avoid Asia) | Weaker (crypto trades 24/7) |
| Default R:R | 2.0 | 1.5 (wider stops) |

---

## 4. Analysis of Previous Implementations

### 4.1 Old V2 (BPR_Bot_V2.mq5) — 10 Critical Bugs

| # | Bug | Severity | Fix in New Version |
|---|-----|----------|-------------------|
| 1 | FVG arrays grow unbounded → stops detecting after 100 | **Critical** | Fixed-size arrays with aging/cleanup |
| 2 | Default risk 10% per trade | **Critical** | Default 1% backtest, configurable profiles |
| 3 | Session uses `TimeCurrent()`, labels say "UTC" | **High** | `TimeCurrent() + GMT_offset` with clear labeling |
| 4 | `ObjectFind` return value inverted | **High** | Correct check: `ObjectFind() < 0` |
| 5 | BPR direction inverted vs ICT convention | **High** | Last FVG = direction (standard) |
| 6 | Tick value cached in OnInit → stale | **Medium** | Read fresh per trade |
| 7 | `Inp_CleanBPROnly` declared, never used | **Low** | Implement or remove |
| 8 | `OnTester()` always returns 100 | **Medium** | Proper custom metric (profit factor weighted) |
| 9 | JSON filename loses `.json` extension | **Low** | Fix StringReplace to only target date dots |
| 10 | No OnDeinit cleanup | **Medium** | Full object cleanup with prefix matching |

### 4.2 ICT_BPR.mq5 Indicator — Good Reference Code

This indicator (on Desktop) has the cleanest FVG detection. Key patterns to adopt:
- **ATR-based FVG filter** with 4 tiers (Very Aggressive to Very Defensive)
- **FVG inversion detection** (price closes through → polarity flip)
- **Proximal/Distal zone concept** (entry at proximal, target at distal)
- **Validity period** (FVGs expire after N bars — default 500)
- **Proper overlap check** for BPR formation

---

## 5. Autonomous Operation Pipeline

### 5.1 Architecture (Wine-Native on macOS — No Parallels)

```
┌──────────────────────────────────────────────────────────────────┐
│                      macOS Apple Silicon                          │
│                                                                  │
│  ┌─────────────────┐                                             │
│  │  Claude Code     │  ◀── Analyzes results, modifies code,     │
│  │  (orchestrator)  │      generates configs, iterates           │
│  └────────┬────────┘                                             │
│           │                                                      │
│           ▼                                                      │
│  ┌─────────────────┐     ┌────────────────────────────────────┐ │
│  │  Python Scripts  │────▶│  Wine (bundled in MT5.app)         │ │
│  │  scripts/        │     │  ┌──────────────────────────────┐  │ │
│  │  - compile.py    │     │  │ metaeditor64.exe /compile     │  │ │
│  │  - backtest.py   │◀────│  │ terminal64.exe  /config:...   │  │ │
│  │  - parse.py      │     │  │ → runs backtest               │  │ │
│  │  - optimize.py   │     │  │ → writes report to Tester/    │  │ │
│  └────────┬────────┘     │  └──────────────────────────────┘  │ │
│           │               └────────────────────────────────────┘ │
│           ▼                                                      │
│  ┌─────────────────┐                                             │
│  │  reports/        │  ← Parsed HTML/XML backtest results       │
│  │  configs/        │  ← Per-pair, per-broker JSON configs      │
│  │  src/BPR_Bot.mq5 │  ← The EA (modified by AI each iteration)│
│  └─────────────────┘                                             │
└──────────────────────────────────────────────────────────────────┘
```

### 5.2 Automation Commands (via Wine from macOS shell)

```bash
# Variables
WINE="/Applications/MetaTrader 5.app/Contents/SharedSupport/wine/bin/wine64"
WINEPREFIX="$HOME/Library/Application Support/net.metaquotes.wine.metatrader5"
MT5_ROOT="$WINEPREFIX/drive_c/Program Files/MetaTrader 5"

# Compile EA
WINEPREFIX="$WINEPREFIX" "$WINE" "$MT5_ROOT/metaeditor64.exe" \
    /compile:"C:\Program Files\MetaTrader 5\MQL5\Experts\BPR_Bot.mq5" /log

# Run backtest (with INI config)
WINEPREFIX="$WINEPREFIX" "$WINE" "$MT5_ROOT/terminal64.exe" \
    /config:"C:\Program Files\MetaTrader 5\config\backtest.ini"
```

### 5.3 INI Config for Automated Backtesting

```ini
[Tester]
Expert=Experts\BPR_Bot
Symbol=XAUUSD
Period=M15
Optimization=0
Model=1                    ; 0=every tick, 1=1min OHLC, 2=open price
FromDate=2025.01.01
ToDate=2025.12.31
ForwardMode=0
Deposit=10000
Currency=USD
Leverage=2000
ExecutionMode=120
Report=Tester\BPR_XAUUSD_backtest.xml
ReplaceReport=1
ShutdownTerminal=1         ; Exit MT5 after test completes
```

### 5.4 Full Autonomous Loop

```
PHASE A — Setup (once)
  1. Write BPR_Bot.mq5 to MQL5/Experts/
  2. Write diagnostic script to MQL5/Scripts/
  3. Compile via Wine + metaeditor64.exe
  4. User runs diagnostic script once → get broker params
  5. Configure per-pair .set files

PHASE B — Iterative Optimization (autonomous)
  Loop:
    1. Claude Code modifies EA code or parameters
    2. Copy .mq5 to MQL5/Experts/
    3. Compile via Wine (check for errors in log)
    4. Generate backtest INI for target pair + date range
    5. Launch backtest via Wine + terminal64.exe
    6. Wait for completion (poll for report file)
    7. Parse report (HTML/XML → metrics)
    8. Analyze: profit factor, Sharpe, max DD, win rate, trade count
    9. Diagnose issues → propose changes
    10. Apply changes → go to step 1

PHASE C — Optimization Passes
  - Run MT5's built-in genetic optimizer for parameter sweeps
  - Walk-forward: train on 6 months, validate on 2 months, roll forward
  - Save best parameters per pair as .set files

PHASE D — Live Deployment
  - User provides live account credentials
  - Set risk profiles: Aggressive (5-10%), Medium (2-3%)
  - Deploy EA with optimized .set file per pair
  - Monitor via daily log analysis
```

### 5.5 Key Uncertainty: Wine Automation

**What needs testing before committing to this path:**

1. **Can `metaeditor64.exe /compile` run headlessly via Wine?**
   - Should work — MetaEditor CLI compilation is a common automation pattern
   - Check: does it produce a `.log` file we can parse for errors?

2. **Can `terminal64.exe /config:backtest.ini` run via Wine without GUI interaction?**
   - The INI approach should work — MT5 reads the config and runs the test
   - `ShutdownTerminal=1` should make it exit after completion
   - Risk: Wine may pop up dialog boxes that block execution

3. **Do backtest reports get written to the Tester directory?**
   - With `Report=...` in the INI, MT5 should write the report
   - Need to verify the path mapping between Wine and macOS filesystem

4. **Performance of Strategy Tester under Wine + Rosetta 2?**
   - Expected to be 2-5x slower than native Windows
   - For heavy optimization, consider a cloud Windows VPS ($20-30/mo)

**Fallback if Wine automation fails:**
- User manually opens MT5 → loads EA → runs backtest → saves report
- Claude Code reads the report file from the Tester directory
- Less autonomous but still works for the iterative loop

---

## 6. Recommended Architecture (EA)

### 6.1 Module Layout (Single File: `BPR_Bot.mq5`)

```
BPR_Bot.mq5
├── [Header] Includes, copyright, version
├── [Inputs] All configurable parameters (grouped by category)
│   ├── Broker settings (magic number, GMT offset)
│   ├── Symbol & timeframe
│   ├── Session filter (UTC hours)
│   ├── Risk & execution (R:R, SL buffer, risk fraction, risk profile)
│   ├── FVG detection (lookback, ATR filter tier, min range)
│   ├── BPR detection (lookback, max active, min range)
│   ├── Market structure (swing lookback, HTF timeframe)
│   └── Visuals (draw boxes, colors, shade sessions)
├── [Enums & Structs]
│   ├── MARKET_STRUCTURE enum
│   ├── FVG_FILTER_TIER enum (VeryAggressive/Aggressive/Defensive/VeryDefensive)
│   ├── FVG struct (timestamp, bounds, direction, active, day_date)
│   ├── BPR struct (overlap bounds, full bounds, direction, active, used, formed_date)
│   └── SwingPoint struct (price, time, type)
├── [Globals] CTrade, arrays, state variables, symbol properties
├── [Event Handlers]
│   ├── OnInit()        — validate symbol, read symbol props, init CTrade, create timer
│   ├── OnTick()        — new bar gate → full pipeline
│   ├── OnDeinit()      — cleanup all chart objects, release resources
│   └── OnTimer()       — periodic maintenance (10-second interval)
├── [Market Structure]
│   ├── DetectSwingPoints(timeframe) — find pivots with configurable lookback
│   └── ClassifyStructure()          — HH/HL/LH/LL → bullish/bearish/range
├── [FVG Detection]
│   ├── DetectFVGs()     — scan last completed bar for new FVGs
│   ├── FilterFVG()      — ATR-based size filter (4 tiers)
│   └── CleanupFVGs()    — age out old/used, daily reset
├── [BPR Detection]
│   ├── DetectBPRs()         — match overlapping opposite FVGs
│   ├── ValidateBPRs()       — invalidate breached BPRs (close through zone)
│   └── ExpireDailyBPRs()    — PATCH 3: remove BPRs from previous trading day
├── [Trade Execution]
│   ├── CheckEntry()             — BPR zone + structure + session alignment
│   ├── CalculatePositionSize()  — equity-risk sizing (fresh tick value)
│   ├── ExecuteTrade()           — CTrade + mark BPR used (PATCH 1)
│   └── HasOpenPosition()        — check by magic number (not PositionsTotal)
├── [Session & Time]
│   ├── IsBlockedSession()   — check if current time falls in no-trade window
│   ├── GetGMTTime()         — TimeCurrent() - GMT_offset*3600
│   └── GetDayStart()        — trading day boundary for PATCH 3
├── [Visuals]
│   ├── DrawBPRBox()     — create rectangle with sequential ID
│   ├── UpdateBPRBox()   — change color when used/expired
│   └── CleanupObjects() — remove all with prefix in OnDeinit
├── [Custom Tester Metric]
│   └── OnTester()       — weighted metric (profit factor + Sharpe + recovery factor)
└── [Utility]
    ├── LogMessage()       — structured logging with timestamp + context
    ├── IsNewBar()         — bar change detection via datetime comparison
    └── NormalizeLots()    — clamp to min/max, snap to step
```

### 6.2 Data Flow Per New Bar

```
OnTick()
  │
  ├─ IsNewBar()? ── No → return
  │
  ├─ CopyRates(entry_TF)
  ├─ CopyRates(HTF)
  │
  ├─ DetectSwingPoints(HTF)
  ├─ ClassifyStructure() → BULLISH / BEARISH / RANGE
  │
  ├─ DetectFVGs() → scan bar[1] for new bullish/bearish FVGs
  ├─ FilterFVG() → ATR-based minimum size check
  ├─ CleanupFVGs() → remove aged FVGs (> lookback bars old)
  │
  ├─ DetectBPRs() → match overlapping opposite FVGs → create BPR
  ├─ ValidateBPRs() → remove BPRs breached by close
  ├─ ExpireDailyBPRs() → PATCH 3: expire previous-day BPRs
  │
  ├─ IsBlockedSession()? ── Yes → skip entry, manage existing trades only
  │
  ├─ HasOpenPosition()? ── Yes + !AllowMultiple → skip entry
  │
  ├─ CheckEntry() → for each active, unused BPR:
  │   ├─ Direction matches structure?
  │   ├─ Price in BPR zone? (use previous bar close)
  │   └─ BPR not used? (PATCH 1)
  │
  ├─ CalculatePositionSize() → equity × risk% / SL_distance
  ├─ ExecuteTrade() → CTrade.Buy/Sell + mark BPR.used = true
  │
  └─ DrawBPRBox() → update visuals for all active BPRs
```

### 6.3 Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| BPR direction | Last FVG determines direction | Standard ICT convention |
| FVG filter | ATR-based, 4 tiers (from ICT_BPR indicator) | Eliminates noise, adapts to volatility |
| FVG array management | Fixed-size (200) with aging + daily reset | Prevents V2 unbounded growth bug |
| BPR lifecycle | Daily expiry (PATCH 3) + close-through invalidation | Intraday strategy; stale BPRs are dangerous |
| Time handling | `TimeCurrent() - GMT_offset * 3600` | Works in both tester and live |
| Position sizing | Fresh tick_value per trade + OrderCalcProfit fallback | Accurate for XAUUSD/BTCUSD cross pairs |
| Visual objects | Sequential ID naming, full OnDeinit cleanup | No name collisions, clean chart |
| One trade per BPR | `used` flag on execution (PATCH 1) | No double-dipping |
| Magic number | Per-pair unique (e.g., 240001=XAUUSD, 240002=BTCUSD) | Tracks positions per EA instance |
| Entry check | Previous bar close in zone (not current tick) | Consistent with new-bar-only logic |
| OnTester metric | 0.4×ProfitFactor + 0.3×Sharpe + 0.3×RecoveryFactor | Meaningful for genetic optimizer |

---

## 7. Proposed File Structure

```
MT5-Bots/
├── BPR/
│   ├── src/
│   │   └── BPR_Bot.mq5                    # Single compile-ready EA
│   ├── scripts/
│   │   ├── compile.sh                      # Wine + metaeditor compile wrapper
│   │   ├── backtest.sh                     # Wine + terminal64 backtest launcher
│   │   ├── parse_report.py                 # HTML/XML report → JSON metrics
│   │   ├── generate_set.py                 # JSON config → .set file generator
│   │   ├── generate_ini.py                 # Backtest INI generator
│   │   └── deploy.sh                       # Copy EA + presets to MQL5 directory
│   ├── configs/
│   │   ├── brokers/
│   │   │   └── gtc_global.json             # GMT offset, server, symbol map
│   │   ├── pairs/
│   │   │   ├── XAUUSD.json                 # Gold-specific params
│   │   │   └── BTCUSD.json                 # BTC-specific params
│   │   └── profiles/
│   │       ├── backtest.json               # 1% risk for testing
│   │       ├── aggressive.json             # 5-10% risk for live
│   │       └── medium.json                 # 2-3% risk for live
│   ├── presets/                             # Generated .set files for MT5
│   │   ├── BPR_XAUUSD_backtest.set
│   │   ├── BPR_BTCUSD_backtest.set
│   │   └── ...
│   ├── models/                              # Future: ONNX models per pair
│   ├── reports/                             # Parsed backtest results per iteration
│   ├── docs/
│   │   └── BACKTEST_NOTES.md               # Analysis of each backtest run
│   ├── RESEARCH_SUMMARY.md                  # This document
│   ├── CHANGELOG.md                         # Iteration tracking
│   └── CLAUDE.md                            # AI development instructions
└── README.md                                # Project overview
```

---

## 8. Execution Plan (Phases)

### Phase 0.5 — Diagnostics & Validation (NEXT)

**Goal**: Confirm all unknowns about the broker before writing the EA.

1. Write `BPR_Diagnostic.mq5` script — prints all broker/symbol properties
2. Copy to `MQL5/Scripts/`
3. Compile via Wine CLI
4. **User runs the script once in MT5** (drag onto chart → reads Journal tab)
5. Parse results → update broker config JSON
6. Also test: can we compile via Wine CLI? Can we launch terminal via Wine CLI?

### Phase 1 — Core EA Development

**Goal**: Compile-ready EA that implements the full BPR strategy with all 3 patches.

1. Write `BPR_Bot.mq5` with all functions from section 6.1
2. Incorporate ATR-based FVG filter from ICT_BPR indicator
3. Deploy to MQL5/Experts/
4. Compile and verify zero warnings
5. Self-test: trace through 5 scenarios mentally
6. Create default `.set` files for XAUUSD and BTCUSD

### Phase 2 — Automation Scripts

**Goal**: Full hands-off compile → backtest → parse → analyze loop.

1. Write `compile.sh` — Wine + metaeditor wrapper
2. Write `backtest.sh` — Wine + terminal64 wrapper with INI generation
3. Write `parse_report.py` — extract metrics from HTML/XML reports
4. Write `generate_set.py` — create .set files from JSON configs
5. Test the full loop end-to-end

### Phase 3 — Iterative Backtesting & Optimization

**Goal**: Find optimal parameters per pair.

1. Run initial backtest on XAUUSD M15 (2024-01-01 to 2025-12-31)
2. Analyze results → identify issues (too many trades? bad SL? wrong structure?)
3. Adjust parameters and/or code → re-test
4. Repeat until profit factor > 1.5, max DD < 20%
5. Run walk-forward validation (train 6mo, validate 2mo, roll)
6. Save best params as .set file
7. Repeat for BTCUSD

### Phase 4 — Live Deployment

**Goal**: Deploy on real account with risk-managed profiles.

1. User provides live account credentials
2. Deploy with "medium" risk profile first (2-3% per trade)
3. Monitor daily — Claude Code reads trade logs, analyzes performance
4. After 2 weeks stable → optionally switch to "aggressive" (5-10%)
5. Ongoing: weekly parameter review, monthly walk-forward re-optimization

### Phase 5 — ML Enhancement (Future)

**Goal**: Add AI-based trade filtering.

1. Collect trade data (features: BPR width, time of day, structure strength, ATR, session)
2. Train logistic regression or small neural net in Python
3. Export to ONNX
4. Embed in EA → filter low-probability setups
5. Re-backtest → compare with/without ML filter

---

## 9. Edge Cases & XAUUSD/BTCUSD-Specific Risks

### XAUUSD (Gold) Risks:
- **Wide spreads during news** (NFP, FOMC) — need spread filter or news time blackout
- **Point value** is high (~$1 per 0.01 lot per point) — position sizing must be precise
- **Volatile session opens** — London open can create false FVGs from stop hunts
- **Correlation with DXY** — USD strength inversely affects gold

### BTCUSD (Bitcoin) Risks:
- **24/7 market** — Asia session filter less relevant; may need different session logic
- **Extreme volatility** — FVGs and BPRs can be very wide; need larger buffers
- **Weekend gaps** — crypto doesn't have traditional weekend gaps but can have exchange-specific gaps
- **Leverage risk** — 1:2000 on BTC with 5-10% risk per trade is extremely dangerous
- **Spread widening** — can be 10x normal during volatile periods

### General Edge Cases:
1. **Overlapping BPRs at same price** — trade only the freshest
2. **Zero-width BPR** — enforce minimum range (in points, per pair)
3. **BPR wider than reasonable SL** — max SL distance filter
4. **Structure flip mid-day** — re-evaluate open trades? (currently: hold until SL/TP)
5. **Multiple magic numbers on same account** — strict magic number filtering in HasOpenPosition

---

## 10. Risk Profiles

| Profile | Risk/Trade | Use Case | Default R:R |
|---------|-----------|----------|-------------|
| Backtest | 1% | Parameter optimization | 2.0 |
| Medium | 2-3% | Conservative live trading | 2.0 |
| Aggressive | 5-10% | High-risk live trading | 2.0 |

**Note**: Even "aggressive" should never exceed 10% per trade. With 1:2000 leverage, a 10% risk trade on XAUUSD with a 50-point SL could use 5+ lots — ensure lot size doesn't exceed broker max.

---

## 11. Open Questions

1. **Wine CLI automation** — Will `metaeditor64.exe /compile` and `terminal64.exe /config:` work headlessly through Wine on macOS? **Must test in Phase 0.5.**

2. **BPR direction edge case** — When bullish and bearish FVGs form on the exact same bar (e.g., doji with wicks), how do we determine direction? Proposed: skip — same-bar FVGs are noise.

3. **BTCUSD session filtering** — Crypto is 24/7. Do we still apply Asia filter, or use a different approach (e.g., volume-based quiet period detection)?

4. **DST handling** — GTC server likely shifts GMT+2 → GMT+3 in March/November. Should the EA auto-detect DST, or use a fixed offset? Proposed: configurable input, user updates seasonally.

---

*Phase 0 research complete. Ready for Phase 0.5 (Diagnostics) upon approval.*

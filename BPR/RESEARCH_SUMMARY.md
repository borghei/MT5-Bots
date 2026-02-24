# BPR Bot - Research Summary (Phase 0)

## 1. Strategy Understanding

### 1.1 Fair Value Gaps (FVGs)

An FVG is a three-candle price imbalance where price moved so aggressively that it left an "untraded" zone. The gap is measured between the **wicks** of candles 1 and 3 (not bodies).

**Bullish FVG** (3-candle pattern, bars indexed present-to-past: `[i]`, `[i+1]`, `[i+2]`):
- `Low[i] > High[i+2]` — the low of the newest candle is above the high of the oldest candle
- FVG zone: `[High[i+2], Low[i]]`
- Represents aggressive buying — price is expected to retrace into this zone and find support

**Bearish FVG** (same indexing):
- `High[i] < Low[i+2]` — the high of the newest candle is below the low of the oldest candle
- FVG zone: `[High[i], Low[i+2]]`
- Represents aggressive selling — price is expected to retrace into this zone and find resistance

**Key findings:**
- An FVG that gets violated (price closes through it) becomes an **Inversion FVG (IFVG)** — polarity flips
- Micro-FVGs (tiny gaps) are noise — a minimum size filter (e.g., % of ATR) is recommended
- FVGs should NOT be traded in isolation — higher-timeframe trend, premium/discount context, and liquidity are essential filters

### 1.2 Balanced Price Ranges (BPRs)

A BPR is the **overlapping zone** where a bullish FVG and a bearish FVG coexist in the same price area. This creates a "double imbalance" — a significantly stronger zone than a single FVG.

**Formation:**
1. Price makes a strong move in one direction, leaving an FVG (e.g., bearish FVG from a down-move)
2. Price reverses aggressively, leaving an opposite FVG (e.g., bullish FVG from an up-move)
3. If these two FVGs **overlap in price**, the overlapping region is the BPR
4. BPR bounds = `[max(bullish_FVG_low, bearish_FVG_low), min(bullish_FVG_high, bearish_FVG_high)]`

**Direction determination:**
- The BPR direction is determined by **which FVG formed second** (the most recent displacement)
- **Bullish BPR**: bearish FVG forms first, then bullish FVG overlaps it → long entries
- **Bearish BPR**: bullish FVG forms first, then bearish FVG overlaps it → short entries
- The last displacement indicates where smart money is pushing price

**Invalidation:**
- A BPR is invalidated when price **closes** decisively through the entire zone in the opposite direction
- For our strategy: BPRs expire at end of trading day (intraday-only entities per PATCH 3)

**SL placement (PATCH 2):**
- SL goes beyond the **entire BPR** (including both FVGs' full extent), NOT just the overlap zone
- `full_high` = max of both FVGs' upper edges
- `full_low` = min of both FVGs' lower edges
- For LONG: SL = `full_low - buffer`
- For SHORT: SL = `full_high + buffer`

### 1.3 Market Structure

**Swing detection algorithm:**
- A swing high: bar whose High > High of N bars on left AND right
- A swing low: bar whose Low < Low of N bars on left AND right
- Recommended default: N=5 for reliable structure, N=3 for more responsive detection
- Swing points are only confirmed after right-side bars form (introduces N-bar lag)

**Structure classification:**
- **Bullish**: HH (Higher High) + HL (Higher Low) sequence
- **Bearish**: LH (Lower High) + LL (Lower Low) sequence
- **Range**: mixed HH/LL, HL/LH — no clear directional bias
- Minimum 3-4 swing points (2 highs + 2 lows) needed for reliable classification

**Multi-timeframe alignment:**
- Trade direction of higher timeframe (HTF)
- Common ratio: 4:1 between timeframes (e.g., H1 for structure, M15 for entry)
- If HTF is range → either avoid trades or trade range reversals

### 1.4 Session Filtering

| Session | UTC Start | UTC End | Characteristic |
|---------|-----------|---------|----------------|
| Sydney | 21:00 | 06:00 | Low volume |
| Tokyo (Asia) | 23:00 | 08:00 | Low-medium, accumulation |
| London | 08:00 | 17:00 | Highest volume, manipulation |
| New York | 13:00 | 22:00 | High volume, distribution |
| London+NY overlap | 13:00 | 17:00 | Most volatile — best for entries |

**Why avoid Asia for entries:**
- Low volatility → tight ranges, unsuitable for directional entries
- Asia range creates liquidity pools that London sweeps (stop hunts)
- ICT "Power of 3" model: Asia = Accumulation, London = Manipulation, NY = Distribution

---

## 2. Key Technical Challenges

### 2.1 TimeGMT() is broken in Strategy Tester
- In the Tester, `TimeGMT()` equals `TimeTradeServer()` — no true GMT available
- **Solution**: Use `TimeCurrent()` (server time) with a configurable GMT offset input parameter. Default to 0 for UTC brokers. The user sets their broker's offset for accurate backtesting.
- Alternative: amrali's TimeGMT library for tester (uses XAUUSD data to estimate offset)

### 2.2 FVG Array Lifecycle (Bug in old V2)
- Old V2 had unbounded FVG arrays that stopped recording after 100 entries
- **Solution**: Implement FVG aging — remove FVGs older than N bars or that have been used in BPRs. Daily reset clears all FVGs.

### 2.3 Bar Index Staleness
- Bar indices shift every new bar (bar 1 becomes bar 2)
- **Solution**: Store `datetime` timestamps instead of bar indices for FVGs and BPRs. Use `iBarShift()` when needing current index from timestamp.

### 2.4 Filling Mode Compatibility
- `ORDER_FILLING_FOK` fails on some brokers
- **Solution**: Use `CTrade::SetTypeFillingBySymbol()` to auto-detect supported filling mode

### 2.5 Position Sizing Accuracy
- `SYMBOL_TRADE_TICK_VALUE` can change during session (cross-currency pairs)
- **Solution**: Read tick_value/tick_size fresh in `CalculatePositionSize()`, not cached from OnInit. Add `OrderCalcProfit()` fallback if tickValue returns 0.

### 2.6 Running on macOS Apple Silicon
- MT5 is Windows-only; on macOS needs Wine/CrossOver/Parallels
- **Best option for development**: Parallels Desktop with Windows 11 ARM (~$99/yr)
- **Best option for automation**: Docker + QEMU (`silicon-metatrader5` package) for headless Python automation
- **Python MT5 package**: Windows-only — use `siliconmetatrader5` drop-in replacement for macOS
- Strategy Tester works in Parallels; degraded performance in Wine/CrossOver

### 2.7 Autonomous Testing Pipeline
- MT5 supports command-line backtesting via INI config files
- `terminal64.exe /config:backtest.ini` with `ShutdownTerminal=1`
- Reports can be exported as HTML/XML and parsed programmatically
- Full autonomous loop: Python generates params → writes INI → launches MT5 → parses results → AI analyzes → repeat

---

## 3. Analysis of Previous Implementation (github.com/borghei/MQ5-BPR)

### What existed:
- **V1 (BPR_Bot.mq5)**: 457 lines, "Context-Aware Engine v7.0" — but **NOT actually a BPR detector**. It detects single FVGs with ATR displacement filtering. Mislabeled as BPR.
- **V2 (BPR_Bot_V2.mq5)**: 1413 lines, "v2.20" — proper BPR detection with FVG overlap logic, JSON logging, visual debugging.

### Critical bugs in old V2:
1. **FVG arrays grow unbounded** — stops finding new BPRs after 100 FVGs. No cleanup/aging.
2. **Default risk 10% per trade** — extremely dangerous. Should be 1%.
3. **Session filter uses `TimeCurrent()` not `TimeGMT()`** — timezone mismatch with "UTC" labels.
4. **`ObjectFind` logic inverted** — visual updates silently fail.
5. **BPR direction logic questionable** — "bearish FVG more recent = bullish BPR" contradicts standard ICT convention.
6. **Tick value cached in OnInit** — stale for cross-currency pairs.
7. **`Inp_CleanBPROnly` and `Inp_RangeThresholdPts` declared but never used.**
8. **`OnTester()` always returns 100** — custom metric useless for optimization.
9. **JSON filename loses `.json` extension** — `StringReplace` replaces the extension dot too.
10. **No `OnDeinit` cleanup** — chart objects persist after EA removal.

### What we're keeping from V2:
- The core BPR detection approach (FVG overlap matching) — but with corrections
- The struct-based architecture (FVG_Data, BPR_Zone)
- The visual debugging concept (BPR boxes on chart)
- The session filtering concept (but fixed to use proper UTC handling)

### What we're replacing:
- Everything else. Full rewrite with lessons learned.

---

## 4. Recommended Architecture

### 4.1 Module Layout (Single File)

```
BPR_Bot.mq5
├── [Header] Includes, copyright, version
├── [Inputs] All configurable parameters
├── [Enums & Structs] FVG, BPR, MARKET_STRUCTURE, SwingPoint
├── [Globals] CTrade, arrays, state variables
├── [Event Handlers]
│   ├── OnInit()        — validate symbol, cache properties, init CTrade
│   ├── OnTick()        — new bar gate → orchestration pipeline
│   ├── OnDeinit()      — cleanup all chart objects
│   └── OnTimer()       — periodic cleanup tasks
├── [Market Structure]
│   ├── DetectSwingPoints()    — find pivots on given timeframe
│   └── ClassifyStructure()    — HH/HL/LH/LL → bullish/bearish/range
├── [FVG Detection]
│   ├── DetectFVGs()           — scan recent bars for new FVGs
│   └── CleanupFVGs()          — age out old/used FVGs
├── [BPR Detection]
│   ├── DetectBPRs()           — match overlapping opposite FVGs
│   ├── ValidateBPRs()         — invalidate breached/expired BPRs
│   └── ExpireDailyBPRs()      — PATCH 3 enforcement
├── [Trade Execution]
│   ├── CheckEntry()           — BPR + structure + session alignment
│   ├── CalculatePositionSize() — equity-risk sizing
│   └── ExecuteTrade()          — CTrade + mark BPR used (PATCH 1)
├── [Session & Time]
│   ├── IsAsiaSession()        — UTC check with midnight wrap
│   ├── GetDayStart()          — trading day boundary
│   └── GetGMTTime()           — server time + offset
├── [Visuals]
│   ├── DrawBPRBox()           — create/update rectangles
│   └── DeleteBPRBox()         — remove chart objects
└── [Utility]
    ├── LogMessage()           — structured logging
    ├── IsNewBar()             — bar change detection
    └── NormalizeLots()        — volume step/min/max clamping
```

### 4.2 Data Flow Per Tick

```
OnTick()
  → IsNewBar() — skip if same bar
  → CopyRates() for entry TF and HTF
  → DetectSwingPoints() on HTF
  → ClassifyStructure() from recent swings
  → DetectFVGs() on new bars
  → CleanupFVGs() — remove aged FVGs
  → DetectBPRs() — find new BPR overlaps
  → ValidateBPRs() — remove invalidated/expired
  → ExpireDailyBPRs() — PATCH 3 daily lifecycle
  → IsAsiaSession() — check session
  → CheckEntry() — evaluate all active BPRs
  → ExecuteTrade() — if signal found
  → DrawBPRBox() — update visuals
```

### 4.3 Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| BPR direction | Last FVG determines direction | Standard ICT convention: last displacement = smart money direction |
| FVG matching window | Configurable lookback (default 30 bars) | Too wide = stale matches; too narrow = missed BPRs |
| FVG array management | Fixed-size with aging (remove > lookback bars old) | Prevents unbounded growth bug from V2 |
| BPR lifecycle | Daily expiry (PATCH 3) + invalidation on close-through | Intraday strategy — stale BPRs are dangerous |
| Time handling | `TimeCurrent() + GMT_offset` input | Works in both tester and live; user configures per broker |
| Position sizing | Fresh tick_value per trade + OrderCalcProfit fallback | Accurate for cross-currency pairs |
| Visual objects | Named by sequential ID, cleaned in OnDeinit | Prevents name collisions, ensures cleanup |
| One trade per BPR | `used` flag set immediately on execution (PATCH 1) | Prevents double-dipping on retracements |

---

## 5. Autonomous Operation Pipeline

### 5.1 Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    macOS Apple Silicon                       │
│                                                             │
│  ┌──────────────┐     ┌──────────────┐    ┌──────────────┐ │
│  │  Python       │     │  MT5 via     │    │  Claude API  │ │
│  │  Orchestrator │────▶│  Parallels   │    │  (Analysis)  │ │
│  │  (scripts/)   │◀────│  or Docker   │    │              │ │
│  └──────┬───────┘     └──────────────┘    └──────┬───────┘ │
│         │                                         │         │
│         │         ┌──────────────┐                │         │
│         └────────▶│  Reports &   │◀───────────────┘         │
│                   │  Logs        │                           │
│                   │  (reports/)  │                           │
│                   └──────────────┘                           │
└─────────────────────────────────────────────────────────────┘
```

### 5.2 Automation Loop

1. **Python orchestrator** (`scripts/optimize.py`):
   - Generates INI config with parameter sets
   - Compiles EA via `metaeditor64.exe /compile:BPR_Bot.mq5 /log`
   - Launches MT5 backtest via `terminal64.exe /config:backtest.ini`
   - Waits for completion (`ShutdownTerminal=1`)
   - Parses HTML/XML report into structured metrics

2. **AI analysis** (`scripts/analyze.py`):
   - Reads backtest metrics (profit factor, Sharpe, max DD, win rate, trade count)
   - Sends to Claude API with current parameters and code
   - Receives: diagnosis of issues, suggested parameter changes, code modifications
   - Applies changes automatically

3. **Iteration tracking** (`reports/` + `CHANGELOG.md`):
   - Each iteration saved with parameters, metrics, and AI analysis
   - CHANGELOG updated with what changed and why
   - Git commit per iteration for full traceability

### 5.3 macOS-Specific Setup

**Option A — Parallels (Recommended for GUI + Tester):**
- Install Parallels Desktop → Windows 11 ARM
- Install MT5 inside Windows VM
- Share project folder between macOS and VM
- Python orchestrator runs on macOS, launches MT5 via Parallels CLI
- `prlctl exec "Windows 11" "C:\\Program Files\\MetaTrader 5\\terminal64.exe" /config:...`

**Option B — Docker + QEMU (Headless automation):**
- `colima start --arch x86_64 --vm-type=qemu --cpu 4 --memory 8`
- Use `siliconmetatrader5` Python package for API access
- Run backtests headlessly with virtual framebuffer
- Slower but fully automated, no GUI needed

**Option C — Hybrid (Recommended):**
- Use Parallels for development, manual testing, and visual debugging
- Use Docker/QEMU for automated optimization runs
- Use a Windows VPS ($20-30/mo) for heavy optimization and 24/7 live trading

### 5.4 MT5 ONNX Integration (Future ML Phase)

MT5 natively supports ONNX models since build 3620:
```mql5
long handle = OnnxCreate("model.onnx", ONNX_DEFAULT);
float input_data[], output[];
OnnxRun(handle, 0, input_data, output);
if(output[0] > threshold) { /* filter trade */ }
```
- Train models in Python (scikit-learn, PyTorch, TensorFlow) → export to ONNX
- Embed .onnx file as resource in EA
- No external Python process needed at runtime

---

## 6. Proposed File Structure

```
MT5-Bots/
├── BPR/
│   ├── src/
│   │   └── BPR_Bot.mq5          # Single compile-ready EA
│   ├── scripts/
│   │   ├── optimize.py           # Parameter optimization orchestrator
│   │   ├── analyze.py            # AI-driven backtest analysis
│   │   ├── compile.py            # MetaEditor compilation wrapper
│   │   ├── parse_report.py       # HTML/XML report parser
│   │   └── config_template.ini   # MT5 backtest INI template
│   ├── models/                   # Future: ONNX models per pair
│   ├── reports/                  # Backtest results per iteration
│   ├── docs/
│   │   └── BACKTEST_NOTES.md     # Analysis of each backtest run
│   ├── RESEARCH_SUMMARY.md       # This document
│   ├── CHANGELOG.md              # Iteration tracking
│   ├── CLAUDE.md                 # AI development instructions
│   └── README.md                 # Project overview
```

---

## 7. Strategy Edge Cases & Improvements Identified

### Edge Cases to Handle:
1. **Overlapping BPRs**: Multiple BPRs at similar price levels — only trade the freshest
2. **Zero-width BPR**: When FVGs barely overlap — enforce minimum range filter
3. **Gap bars**: Weekend gaps or news gaps can create false FVGs — consider ATR-based minimum displacement
4. **Thin BPR with wide SL**: When `full_high - full_low` is much larger than the overlap zone, R:R becomes poor — consider maximum SL distance filter
5. **Multiple timeframe conflicts**: HTF bullish but LTF shows BOS (break of structure) bearish — prioritize HTF

### Potential Improvements (Post Phase 1):
1. **ATR-based minimum FVG size**: Filter out noise FVGs smaller than 0.5x ATR
2. **Premium/Discount filter**: Only take bullish BPRs in discount zone (below 50% of range), bearish in premium
3. **Liquidity sweep confirmation**: Enter after a sweep of nearby liquidity, not just on retracement
4. **Partial TP**: Close 50% at 1R, trail remainder
5. **Volatility-adjusted R:R**: Wider R:R in high-volatility environments
6. **Time-of-day scoring**: Weight trades by historical profitability of the hour

---

## 8. Questions / Clarifications Needed

Before proceeding to Phase 1 (coding), I need clarity on:

1. **Broker GMT offset**: What broker do you use, and what is its server time offset from UTC? This affects session filtering accuracy in backtests.

2. **Account type**: Netting or hedging? (Most forex retail brokers use hedging.)

3. **Primary pairs**: EURUSD only, or multiple pairs? This affects whether we need multi-symbol handling.

4. **macOS setup preference**: Do you already have Parallels/CrossOver installed, or should we plan for Wine/Docker?

5. **Automation priority**: Should the autonomous pipeline be the very first thing we build (before the EA itself), or should we build the EA first and add automation later?

6. **Risk appetite for default settings**: The old V2 defaulted to 10% risk per trade. The prompt specifies 10% as well. Confirm this is intentional — 10% per trade is very aggressive and can lead to rapid account drawdown. Recommend 1-2% for live trading, 10% only for backtesting/demo.

---

*Research completed: 2026-02-24*
*Ready for Phase 1 upon approval.*

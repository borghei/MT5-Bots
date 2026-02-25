# BPR Bot — Master Execution Plan

*This is the single source of truth. Every phase, decision, and document is referenced here.*

---

## Document Map

| Document | Purpose | Status |
|----------|---------|--------|
| **[PLAN.md](PLAN.md)** | This file — master plan, phase tracking, decisions, full strategy spec | Active |
| **[RESEARCH_SUMMARY.md](RESEARCH_SUMMARY.md)** | Strategy deep-dive (FVG/BPR rules, XAUUSD/BTCUSD specifics, session filtering, previous code analysis) | Complete |
| **[docs/MQL5_TECHNICAL_REFERENCE.md](docs/MQL5_TECHNICAL_REFERENCE.md)** | Every MQL5 function, property, formula, error code that can cost money | Complete |
| **[docs/AUTOMATION_PIPELINE.md](docs/AUTOMATION_PIPELINE.md)** | Wine commands, INI format, .set file format, report parsing, autonomous loop | Complete |
| **[CLAUDE.md](CLAUDE.md)** | AI development rules — critical technical constraints, coding rules, iteration workflow | Complete |
| **[CHANGELOG.md](CHANGELOG.md)** | What changed per version, with rationale | Ongoing |
| **[docs/BACKTEST_NOTES.md](docs/BACKTEST_NOTES.md)** | Analysis of each backtest run (created during Phase 3) | Not started |

---

## Project Summary

**What**: MT5 Expert Advisor trading the ICT Balanced Price Range (BPR) strategy — overlapping bullish and bearish Fair Value Gaps as entry zones, filtered by market structure and session.

**Where**: GTC Global Trade broker (`GTCGlobalTrade-Server`), macOS Apple Silicon, MT5 build 5640 via Wine 10.0.

**Pairs**: XAUUSD (primary), BTCUSD (secondary). Per-pair per-broker configs.

**Goal**: Fully autonomous — AI handles code, backtesting, optimization, and iteration. Human only approves live deployment.

---

## Phase Overview

| Phase | Name | Status | Depends On |
|-------|------|--------|------------|
| 0 | Research & Planning | **COMPLETE** | — |
| 0.5 | Diagnostics & Wine Validation | **IN PROGRESS** | Phase 0 |
| 1 | Core EA Development | Not started | Phase 0.5 |
| 2 | Automation Scripts | Not started | Phase 1 |
| 3 | Iterative Backtesting & Optimization | Not started | Phase 2 |
| 4 | Live Deployment | Not started | Phase 3 + user approval |
| 5 | ML Enhancement | Future | Phase 4 stable |

---

## Strategy Specification (Authoritative)

*This section captures the EXACT strategy from the original prompt. It is the authoritative spec for Phase 1 development. Research findings in RESEARCH_SUMMARY.md provide additional depth but this spec takes precedence for defaults and formulas.*

### Step 1 — Market Structure Analysis

- Multi-timeframe analysis with swing highs and swing lows
- **Bullish**: Higher Highs (HH) + Higher Lows (HL)
- **Bearish**: Lower Highs (LH) + Lower Lows (LL)
- **Range**: Price oscillates without clear directional bias
- Swing pivot: a bar is a swing high if its High is the maximum over N bars on each side (configurable lookback, default N=3)
- HTF (default H1) determines overall bias, entry TF (default M15) for FVG/BPR and entry
- If HTF = Range → skip all trades

### Step 2 — Session Filter

- **Asia Session**: configurable, default **00:00 to 09:00 UTC** (inclusive start, exclusive end)
- When enabled and current UTC time is within window → **block all new entries**
- Manage already-open trades normally regardless of session
- Use `TimeGMT()` for UTC baseline (with tester workaround — see CLAUDE.md)
- Handle midnight wraparound correctly (e.g., if start > end in hours)

> **Research note**: For XAUUSD specifically, research suggests 22:00-07:00 UTC may be better (covers Sydney + Tokyo). The default from the original spec (00:00-09:00) is the starting point — optimization in Phase 3 will determine the best window.

### Step 3 — FVG Detection

**Bullish FVG** (bar index `i`, where `i >= 2`):
```
Low[i] > High[i-2]  AND  Close[i-1] > High[i-2]
```

**Bearish FVG** (bar index `i`, where `i >= 2`):
```
High[i] < Low[i-2]  AND  Close[i-1] < Low[i-2]
```

Where: `i` = newest candle (candle 3), `i-1` = middle candle (candle 2), `i-2` = oldest candle (candle 1).

**The close-confirmation condition** (`Close[i-1]` check) ensures the middle candle's close confirms the directional intent, filtering out weak FVGs.

**Zone boundaries use WICKS (High/Low), NEVER bodies (Open/Close):**
- Bullish FVG zone: `[High[i-2], Low[i]]`
- Bearish FVG zone: `[High[i], Low[i-2]]`

> **MQL5 series indexing**: With `ArraySetAsSeries(rates, true)`, candle 1 (oldest) = `rates[i+2]`, candle 2 (middle) = `rates[i+1]`, candle 3 (newest) = `rates[i]`. See [RESEARCH_SUMMARY.md §1.1](RESEARCH_SUMMARY.md).

### Step 4 — BPR Detection (Double FVG)

- When a bullish FVG and a bearish FVG overlap in price, the overlapping zone is the BPR
- **On detecting a new FVG, scan backward** for opposite-direction FVGs within the configurable lookback window
- If price ranges overlap → create BPR with bounds = overlapping edges:
  ```
  BPR_low  = max(B_low, S_low)
  BPR_high = min(B_high, S_high)
  BPR exists if: BPR_high > BPR_low
  ```
- **BPR direction**: The **last (most recent) FVG** determines direction
  - Bullish FVG came last → Bullish BPR → LONG
  - Bearish FVG came last → Bearish BPR → SHORT

### Step 5 — Entry & Exit Logic

- **Entry**: When price retraces into BPR zone AND market structure aligns:
  - Bullish structure + Bullish BPR → **LONG** (market order)
  - Bearish structure + Bearish BPR → **SHORT** (market order)
- **Stop Loss**: Beyond the **highest/lowest point of the ENTIRE BPR** (both FVGs), plus configurable buffer:
  - For LONG: `SL = full_low - buffer`
  - For SHORT: `SL = full_high + buffer`
  - `full_low = min(B_low, S_low)`, `full_high = max(B_high, S_high)`
- **Take Profit**: Based on Risk:Reward ratio (default 2:1)
- **Position Sizing**: Risk-based on account equity (default 10% risk per trade)

### Three Non-Negotiable Patches

> **PATCH 1 — One Trade Per BPR**: Once a trade is opened on a specific BPR, that BPR is "consumed" and must NOT trigger any further trades. Mark it as `used` immediately upon trade execution. Each BPR = maximum one trade.

> **PATCH 2 — SL Placement Correction**: Stop Loss must be placed beyond the **highest/lowest point of the ENTIRE BPR zone**, NOT behind a single FVG edge. Specifically: For LONG: `SL = BPR.full_low - buffer`. For SHORT: `SL = BPR.full_high + buffer`.

> **PATCH 3 — Daily BPR Lifecycle**: Each BPR belongs to the day it was formed. If a BPR is not triggered on that same trading day, it expires at end of day and must NOT extend or carry over to the next day. BPRs are intraday-only entities.

### Required Input Parameters

```mql5
// Symbol & Timeframe
input string               Inp_Symbol              = "XAUUSD";        // Primary pair (changed from EURUSD)
input ENUM_TIMEFRAMES      Inp_Timeframe           = PERIOD_M15;

// Session filter (UTC)
input bool                 Inp_AsiaEnabled         = true;
input string               Inp_AsiaStartUTC        = "00:00";         // inclusive
input string               Inp_AsiaEndUTC          = "09:00";         // exclusive

// Risk/Reward & execution
input double               Inp_RR                  = 2.0;
input int                  Inp_SLBufferPoints      = 1;               // buffer beyond BPR extreme
input double               Inp_RiskFractionEquity  = 0.10;            // 10% equity risk (default)
input bool                 Inp_AllowMultiplePos    = false;
input int                  Inp_DeviationPoints     = 5;

// BPR / FVG detection
input int                  Inp_BPRLookbackBars     = 30;
input int                  Inp_MaxActiveBPRs       = 10;
input int                  Inp_BPRMinRangePoints   = 0;
input bool                 Inp_CleanBPROnly        = false;
input bool                 Inp_DeleteInvalidBPR    = true;

// Market structure
input int                  Inp_SwingLookback       = 3;               // bars on each side for swing detection
input int                  Inp_RangeThresholdPts   = 0;
input ENUM_TIMEFRAMES      Inp_HTF_Timeframe       = PERIOD_H1;       // higher timeframe for structure

// Visuals
input bool                 Inp_DrawBPRBoxes        = true;
input color                Inp_BullBPRColor        = clrGreen;
input color                Inp_BearBPRColor        = clrRed;
input bool                 Inp_ShadeAsiaSession    = false;

// Broker time (added from research — TimeGMT broken in tester)
input int                  Inp_GMTOffsetWinter     = 2;               // broker GMT offset (winter)
input int                  Inp_GMTOffsetSummer     = 3;               // broker GMT offset (summer/DST)

// Trade management
input int                  Inp_MagicNumber         = 240001;
input int                  Inp_FVGFilterTier       = 2;               // 0=VeryAggressive, 1=Aggressive, 2=Defensive, 3=VeryDefensive
```

> **Research-adjusted defaults**: During Phase 3 optimization, we may adjust `Inp_RiskFractionEquity` from 10% to lower values (2-3% for medium risk profile, 5-10% for aggressive). The 10% default from the original spec is kept as the starting point. `Inp_GMTOffsetWinter/Summer` and `Inp_FVGFilterTier` were added from research — not in original prompt but necessary for correct operation.

### Required Data Structures

```mql5
struct FVG {
    int        bar_index;       // formation bar
    datetime   time;            // formation time
    double     high_bound;      // upper edge (WICK, not body)
    double     low_bound;       // lower edge (WICK, not body)
    int        direction;       // +1 bullish, -1 bearish
    bool       active;
    datetime   day_date;        // which trading day it belongs to
};

struct BPR {
    double     high_bound;      // overlap zone upper
    double     low_bound;       // overlap zone lower
    double     full_high;       // highest point of entire BPR (for SL — PATCH 2)
    double     full_low;        // lowest point of entire BPR (for SL — PATCH 2)
    int        direction;       // +1 bullish, -1 bearish
    bool       active;
    bool       used;            // PATCH 1: one trade per BPR
    datetime   formed_date;     // PATCH 3: daily lifecycle
    datetime   left_time;
    datetime   right_time;
    string     box_name;        // for visual rectangle
};

enum MARKET_STRUCTURE { STRUCT_BULLISH, STRUCT_BEARISH, STRUCT_RANGE };
```

> **Research additions**: FVG struct should also store `datetime` timestamps instead of bar indices (indices shift every bar). Fixed-size arrays (200) with aging — see [RESEARCH_SUMMARY.md §7.1](RESEARCH_SUMMARY.md).

### Required Core Functions (All Must Be Implemented)

| # | Function | Purpose |
|---|----------|---------|
| 1 | `OnInit()` | Validate symbol, cache properties, initialize buffers, CTrade setup |
| 2 | `OnTick()` | New bar detection, state update, session check, entry logic |
| 3 | `OnDeinit()` | Cleanup all chart objects |
| 4 | `DetectSwingPoints()` | Find swing highs/lows on given timeframe |
| 5 | `ClassifyStructure()` | Determine bullish/bearish/range from recent swings |
| 6 | `DetectFVGs()` | Scan recent bars for new FVGs (with close-confirmation) |
| 7 | `DetectBPRs()` | Match overlapping opposite FVGs into BPRs |
| 8 | `ValidateBPRs()` | Invalidate breached BPRs, expire end-of-day BPRs (PATCH 3) |
| 9 | `CheckEntry()` | Price in BPR + structure alignment + session OK + BPR not used |
| 10 | `CalculatePositionSize()` | Equity-risk sizing with proper tick value conversion |
| 11 | `ExecuteTrade()` | CTrade with retcode handling, mark BPR as used (PATCH 1) |
| 12 | `DrawBPRBox()` / `DeleteBPRBox()` | Visual rectangles on chart |
| 13 | `IsAsiaSession()` | UTC session check with midnight wraparound |
| 14 | `GetDayStart()` | Helper to determine trading day boundary for PATCH 3 |
| 15 | `LogMessage()` | Structured logging for debugging |

### Safety & Robustness Requirements

- Query all symbol properties dynamically: `SYMBOL_POINT`, `SYMBOL_DIGITS`, `SYMBOL_TRADE_TICK_VALUE`, `SYMBOL_TRADE_TICK_SIZE`, `SYMBOL_VOLUME_MIN/MAX/STEP`, filling modes
- Handle netting vs hedging account modes
- Check `CTrade` retcodes after every operation
- Clamp lot size to min/max, snap to step; if below min → skip trade and log
- Handle `CopyRates()` failures gracefully (can return fewer bars than requested)
- Use `TimeGMT()` for session logic; use tester workaround when `MQL_TESTER` is true

### Self-Test Scenarios (Must Trace Through Before Shipping)

| Scenario | Setup | Expected Result |
|----------|-------|-----------------|
| **A** | Bullish structure, bullish BPR forms at 10:00 UTC, price retraces at 14:00 | Enter LONG |
| **B** | Same BPR from scenario A touched again at 15:00 | NO entry (PATCH 1 — BPR already used) |
| **C** | BPR formed at 16:00, not triggered, new day starts | BPR expires (PATCH 3 — daily lifecycle) |
| **D** | Valid signal at 02:00 UTC, Asia session active | NO entry (session filter blocks) |
| **E** | Bearish structure but bullish BPR | NO entry (direction mismatch) |

### Backtest Analysis Protocol (Phase 3)

When analyzing backtest results:
1. Parse the equity curve, drawdown, win rate, profit factor
2. Diagnose:
   - Entering too frequently? → BPR detection too loose, lower filter tier
   - Missing entries? → Detection too strict, session filter too wide
   - Stopping out too much? → SL placement issue, buffer too tight
   - Not reaching TP? → R:R too aggressive, wrong structure classification
3. Propose specific code changes with rationale
4. Implement changes and explain what was modified

### Code Quality Standards

- Every function must have a header comment explaining purpose, inputs, outputs
- Complex logic blocks must have inline comments
- Use meaningful variable names (no single letters except loop counters)
- Group related functions together with section separators
- Log important events: trade execution, BPR creation/invalidation/expiry, structure changes

---

## Phase 0 — Research & Planning [COMPLETE]

**Deliverables produced:**
- [x] FVG/BPR strategy deep-dive with exact formulas → [RESEARCH_SUMMARY.md §1-2](RESEARCH_SUMMARY.md)
- [x] Market structure classification rules → [RESEARCH_SUMMARY.md §3](RESEARCH_SUMMARY.md)
- [x] Session filtering with precise UTC hours → [RESEARCH_SUMMARY.md §4](RESEARCH_SUMMARY.md)
- [x] XAUUSD trading specifics (spreads, sessions, position sizing example) → [RESEARCH_SUMMARY.md §5](RESEARCH_SUMMARY.md)
- [x] BTCUSD trading specifics (flash crash risks, leverage danger, swap costs) → [RESEARCH_SUMMARY.md §6](RESEARCH_SUMMARY.md)
- [x] Analysis of old MQ5-BPR repo (10 critical bugs) → [RESEARCH_SUMMARY.md §7](RESEARCH_SUMMARY.md)
- [x] MQL5 technical reference (CopyRates, CTrade, position sizing, errors) → [docs/MQL5_TECHNICAL_REFERENCE.md](docs/MQL5_TECHNICAL_REFERENCE.md)
- [x] Automation pipeline design (Wine commands, INI format, report parsing) → [docs/AUTOMATION_PIPELINE.md](docs/AUTOMATION_PIPELINE.md)
- [x] MT5 installation fully mapped (all paths, Wine prefix, broker config)
- [x] ICT_BPR.mq5 indicator analyzed — ATR filter adopted

**Key decisions made:**

| Decision | Choice | Rationale | Documented In |
|----------|--------|-----------|---------------|
| BPR direction | Last FVG = direction | Standard ICT convention, cross-referenced 6+ sources | [RESEARCH_SUMMARY.md §2.2](RESEARCH_SUMMARY.md) |
| FVG detection | Gap condition + close confirmation | Original spec requires both conditions | This file (Strategy Spec §Step 3) |
| FVG filter | ATR-based, 4 tiers | Eliminates noise, adapts to volatility per pair | [RESEARCH_SUMMARY.md §1.8](RESEARCH_SUMMARY.md) |
| Time handling | `TimeCurrent() - GMT_offset * 3600` | `TimeGMT()` broken in tester | [MQL5_TECHNICAL_REFERENCE.md §7](docs/MQL5_TECHNICAL_REFERENCE.md) |
| Position sizing | MathFloor (not NormalizeDouble) | NormalizeDouble rounds UP → risks more than intended | [MQL5_TECHNICAL_REFERENCE.md §2.2](docs/MQL5_TECHNICAL_REFERENCE.md) |
| FVG arrays | Fixed-size (200) + aging | Old V2 unbounded arrays stopped working after 100 FVGs | [RESEARCH_SUMMARY.md §7.1 bug #1](RESEARCH_SUMMARY.md) |
| File encoding | UTF-16 LE with BOM | Confirmed from actual .set/.ini files on system | [AUTOMATION_PIPELINE.md §4](docs/AUTOMATION_PIPELINE.md) |
| Compilation check | .ex5 existence (not exit code) | MetaEditor exit code unreliable | [AUTOMATION_PIPELINE.md §2.2](docs/AUTOMATION_PIPELINE.md) |
| Bar indexing | Only bar 1+ for signals | Bar 0 is still forming — OHLC changes every tick | [MQL5_TECHNICAL_REFERENCE.md §1.1](docs/MQL5_TECHNICAL_REFERENCE.md) |
| ObjectFind check | `>= 0` means found | Old V2 used `!ObjectFind()` which is TRUE for main window | [MQL5_TECHNICAL_REFERENCE.md §6.1](docs/MQL5_TECHNICAL_REFERENCE.md) |
| Session default | 00:00-09:00 UTC (original spec) | Research suggests 22:00-07:00 for XAUUSD — to be tested in Phase 3 | This file (Strategy Spec §Step 2) |
| Risk default | 10% per trade (original spec) | Research suggests lower — risk profiles to be tuned in Phase 3 | This file (Strategy Spec §Step 5) |
| SwingLookback default | N=3 (original spec) | Research suggests N=5 for reliability — tunable parameter | This file (Strategy Spec §Step 1) |

---

## Phase 0.5 — Diagnostics & Wine Validation [NEXT]

**Goal**: Confirm all broker unknowns and validate that Wine automation works.

### Tasks

- [x] **0.5.1** Write `BPR_Diagnostic.mq5` script that prints:
  - Account margin mode (hedging/netting)
  - Server GMT offset (via `TimeCurrent() - TimeGMT()`)
  - All symbols containing "XAU" and "BTC" (exact naming)
  - `SYMBOL_FILLING_MODE`, `SYMBOL_TRADE_EXEMODE` per symbol
  - `SYMBOL_VOLUME_MIN/MAX/STEP`, `SYMBOL_TRADE_TICK_VALUE/SIZE` per symbol
  - `SYMBOL_TRADE_CONTRACT_SIZE`, `SYMBOL_TRADE_STOPS_LEVEL`, `SYMBOL_SPREAD` per symbol
  - `SYMBOL_SWAP_LONG/SHORT`, `SYMBOL_SWAP_ROLLOVER3DAYS` per symbol
  - Leverage, account currency

- [x] **0.5.2** Test Wine compilation:
  - Copy diagnostic script to `MQL5/Scripts/`
  - Run `metaeditor64.exe /compile:...` via Wine from macOS terminal
  - Verify `.ex5` produced, parse `.log` for errors
  - Document exact working command
  - **FINDING**: Paths with spaces fail silently. Must use `C:\temp\` staging dir.

- [ ] **0.5.3** User runs diagnostic script:
  - Open MT5 → drag script onto XAUUSD chart → read Journal tab
  - Copy output back to Claude Code

- [x] **0.5.4** Test Wine backtesting:
  - Used ExpertMACD on XAUUSD.ecn M15, Jan 2025
  - Generated INI file (UTF-16 LE with BOM)
  - Ran `terminal64.exe /config:C:\temp\backtest.ini /portable` via Wine
  - **Result**: 384 trades, reports generated in Tester/, ~15s total
  - **FINDINGS**: INI path must not have spaces, EA path no Experts\ prefix, port 3000 must be free

- [ ] **0.5.5** Update configs:
  - Create `configs/brokers/gtc_global.json` with confirmed values
  - Create `configs/pairs/XAUUSD.json` and `BTCUSD.json` with confirmed properties

**Deliverables:**
- Confirmed broker parameters (account mode, GMT offset, symbol names, filling, stops level)
- Working Wine compilation command
- Working Wine backtest command
- Broker and pair config files

---

## Phase 1 — Core EA Development

**Goal**: Single compile-ready `BPR_Bot.mq5` that implements the full strategy with all 3 patches.

**Source of truth for all inputs, structs, functions, and formulas**: Strategy Specification section above.

### Tasks

- [ ] **1.1** Write EA skeleton: inputs, structs, globals, event handlers
  - ALL inputs from Strategy Specification above (exact names, types, defaults)
  - FVG, BPR structs with exact fields from spec (use `datetime` timestamps, not bar indices)
  - MARKET_STRUCTURE enum
  - CTrade initialization with `SetTypeFillingBySymbol(_Symbol)`

- [ ] **1.2** Implement market structure module:
  - `DetectSwingPoints(timeframe, lookback)` — swing high if High is max over N bars each side
  - `ClassifyStructure()` — HH/HL → bullish, LH/LL → bearish, mixed → range
  - Multi-TF: HTF (H1) for bias, entry TF (M15) for signals
  - Minimum 3-4 swing points required for classification
  - If HTF = Range → skip all trades

- [ ] **1.3** Implement FVG detection:
  - **Both conditions**: gap check AND close-confirmation (see Strategy Spec §Step 3)
  - Scan from bar 1 backward (NEVER bar 0)
  - ATR-based size filter (4 tiers via `Inp_FVGFilterTier`)
  - Temporal continuity check (reject weekend gap FVGs)
  - Deduplication by candle 2's datetime
  - FVG lifecycle tracking (active → tested → mitigated → invalidated)
  - Aging cleanup (remove FVGs > lookback bars old)
  - Fixed-size arrays (200) — see [RESEARCH_SUMMARY.md §7.1](RESEARCH_SUMMARY.md)

- [ ] **1.4** Implement BPR detection:
  - On new FVG, scan backward for opposite-direction FVGs within `Inp_BPRLookbackBars`
  - Overlap calculation: `max(B_low, S_low)` to `min(B_high, S_high)`
  - Direction: last FVG's direction (NOT inverted like old V2)
  - Full bounds for SL: `full_low = min(both lows)`, `full_high = max(both highs)` (PATCH 2)
  - Minimum BPR width filter (`Inp_BPRMinRangePoints` + ATR-based)
  - Max active BPRs: `Inp_MaxActiveBPRs` (default 10)
  - PATCH 1: `used` flag initialized to `false`
  - PATCH 3: `formed_date` stored on creation

- [ ] **1.5** Implement BPR validation (`ValidateBPRs()`):
  - Close-through invalidation (not wick-through) — candle close beyond opposing zone edge
  - For bullish BPR: invalidated when close < BPR_low
  - For bearish BPR: invalidated when close > BPR_high
  - Daily expiry check (PATCH 3): expire when `GetDayStart(current_time) > GetDayStart(formed_date)`
  - `Inp_DeleteInvalidBPR`: if true, delete chart objects for invalidated BPRs
  - `Inp_CleanBPROnly`: if true, only allow BPRs where both FVGs are untested (clean)

- [ ] **1.6** Implement session filter:
  - `IsAsiaSession()` using `GetGMTTime()` with tester-aware broker offset
  - Configurable block window via `Inp_AsiaStartUTC` / `Inp_AsiaEndUTC` (default: 00:00-09:00 UTC)
  - Midnight wraparound handling (when start hour > end hour)
  - `Inp_ShadeAsiaSession`: if true, draw rectangle on chart for session
  - DST detection using `Inp_GMTOffsetWinter` / `Inp_GMTOffsetSummer`

- [ ] **1.7** Implement entry logic (`CheckEntry()`):
  - Price in BPR zone (previous bar close, not current tick)
  - Structure alignment (bullish structure + bullish BPR → LONG, bearish + bearish → SHORT)
  - BPR not used (PATCH 1: `!bpr.used`)
  - Session not blocked (`!IsAsiaSession()` when `Inp_AsiaEnabled`)
  - No existing position for this magic number (unless `Inp_AllowMultiplePos`)

- [ ] **1.8** Implement position sizing (`CalculatePositionSize()`):
  - Risk amount = `AccountInfoDouble(ACCOUNT_EQUITY) * Inp_RiskFractionEquity`
  - Fresh `SYMBOL_TRADE_TICK_VALUE` per trade (NEVER cache)
  - If tickValue ≤ 0: use `OrderCalcProfit()` fallback
  - `MathFloor` for lot normalization (NEVER NormalizeDouble alone)
  - Clamp to `SYMBOL_VOLUME_MIN/MAX`, snap to `SYMBOL_VOLUME_STEP`
  - If below min → skip trade and log

- [ ] **1.9** Implement trade execution (`ExecuteTrade()`):
  - `CTrade.Buy/Sell` with `Inp_DeviationPoints` slippage
  - SL = `full_low - buffer` (LONG) or `full_high + buffer` (SHORT) — PATCH 2
  - TP = entry ± (SL distance × `Inp_RR`)
  - Check `SYMBOL_TRADE_STOPS_LEVEL` before placing SL/TP
  - Retry logic for: REQUOTE (10004), PRICE_CHANGED (10020)
  - Do NOT retry: NO_MONEY (10019), INVALID_STOPS (10016), INVALID_VOLUME (10014)
  - Mark BPR as used immediately (PATCH 1: `bpr.used = true`)
  - Full retcode handling per [MQL5_TECHNICAL_REFERENCE.md §3](docs/MQL5_TECHNICAL_REFERENCE.md)

- [ ] **1.10** Implement visuals:
  - `DrawBPRBox()` / `DeleteBPRBox()` — BPR rectangles on chart
  - Color coding: `Inp_BullBPRColor` (default green), `Inp_BearBPRColor` (default red)
  - Used BPR = gray, expired = dotted
  - Sequential ID naming for box objects
  - Full cleanup in `OnDeinit()`
  - Correct `ObjectFind` usage (`>= 0` means found, not `!`)

- [ ] **1.11** Implement `LogMessage()`:
  - Structured logging for: trade execution, BPR creation/invalidation/expiry, structure changes
  - Include timestamp, symbol, direction, price levels

- [ ] **1.12** Implement OnTester metric:
  - `0.4 * ProfitFactor + 0.3 * Sharpe + 0.3 * RecoveryFactor`
  - Returns meaningful fitness for genetic optimizer

- [ ] **1.13** Self-test:
  - Trace through all 5 scenarios (see Self-Test Scenarios table above)
  - Verify all 3 patches are correctly implemented in code
  - Verify FVG detection matches spec exactly (both conditions)
  - Verify SL at `full_high`/`full_low` (not overlap zone edges)
  - Verify BPRs expire at end of trading day
  - Check for compilation issues: all variables declared, no type mismatches, CTrade methods correct
  - Compile with zero warnings

**Deliverables:**
- `src/BPR_Bot.mq5` — single compile-ready file (no additional files except standard includes)
- Default `.set` files for XAUUSD and BTCUSD
- Zero compilation warnings
- Must work in both Strategy Tester and live trading

---

## Phase 2 — Automation Scripts

**Goal**: Full hands-off compile → backtest → parse → analyze loop.

### Tasks

- [ ] **2.1** `scripts/compile.sh` — Wine + MetaEditor wrapper with .ex5 verification and .log parsing
- [ ] **2.2** `scripts/backtest.sh` — Wine + terminal64 launcher with INI generation and report polling
- [ ] **2.3** `scripts/parse_report.py` — HTML report → JSON metrics extraction
- [ ] **2.4** `scripts/generate_set.py` — JSON config → UTF-16 LE .set file generator
- [ ] **2.5** `scripts/generate_ini.py` — Generate backtest INI (UTF-16 LE) from parameters
- [ ] **2.6** `scripts/deploy.sh` — Copy EA + presets to MQL5 directory
- [ ] **2.7** End-to-end test: modify param → compile → backtest → parse → verify metrics extracted

**Deliverables:**
- All scripts in `scripts/`
- Documented in [AUTOMATION_PIPELINE.md](docs/AUTOMATION_PIPELINE.md)
- End-to-end test passing

---

## Phase 3 — Iterative Backtesting & Optimization

**Goal**: Find optimal parameters per pair through data-driven iteration.

### Tasks

- [ ] **3.1** Initial XAUUSD backtest: M15, 2024-01-01 to 2025-12-31
- [ ] **3.2** Analyze results using Backtest Analysis Protocol (see above) → document in [docs/BACKTEST_NOTES.md](docs/BACKTEST_NOTES.md)
- [ ] **3.3** Iterate: adjust parameters and/or code based on diagnosis
  - Too many trades? → Tighten FVG filter tier, narrow session window
  - Missing entries? → Loosen FVG filter, widen session window
  - Stopping out? → Increase SL buffer, check structure classification
  - Not reaching TP? → Lower R:R ratio, verify entry timing
- [ ] **3.4** Target metrics:
  - Profit Factor > 1.5
  - Max Drawdown < 20%
  - Win Rate > 45%
  - Total Trades > 100 (statistical significance)
  - Sharpe Ratio > 1.0
- [ ] **3.5** Parameters to optimize:
  - `Inp_AsiaStartUTC` / `Inp_AsiaEndUTC` (00:00-09:00 vs 22:00-07:00 vs other windows)
  - `Inp_RR` (1.5 to 4.0)
  - `Inp_SLBufferPoints` (1 to 50)
  - `Inp_RiskFractionEquity` (0.01 to 0.10)
  - `Inp_BPRLookbackBars` (10 to 50)
  - `Inp_SwingLookback` (3 to 7)
  - `Inp_FVGFilterTier` (0 to 3)
- [ ] **3.6** Walk-forward validation: train 6 months, validate 2 months, roll forward
- [ ] **3.7** Save best XAUUSD params as `.set` file
- [ ] **3.8** Repeat for BTCUSD (with adjusted defaults: Very Defensive filter, lower leverage, lower risk)
- [ ] **3.9** Multi-broker support: if second broker added, create separate configs

**Deliverables:**
- Optimized `.set` files per pair per broker
- Walk-forward validation results
- [docs/BACKTEST_NOTES.md](docs/BACKTEST_NOTES.md) with analysis of every iteration

---

## Phase 4 — Live Deployment

**Goal**: Deploy on real account with risk management.

### Tasks

- [ ] **4.1** User provides live account credentials
- [ ] **4.2** Deploy with "medium" risk profile (2-3% per trade)
- [ ] **4.3** Monitor daily: read trade logs, analyze performance
- [ ] **4.4** After 2 weeks stable → option to switch to "aggressive" (5-10%)
- [ ] **4.5** Weekly parameter review
- [ ] **4.6** Monthly re-optimization (walk-forward)

**Risk profiles:**

| Profile | Risk/Trade | XAUUSD | BTCUSD |
|---------|-----------|--------|--------|
| Backtest | 10% (original default) | Any leverage | 5x-10x effective leverage |
| Medium | 2-3% | Full leverage OK | Max 5x effective leverage |
| Aggressive | 5-10% | Full leverage OK | Max 10x effective leverage |

---

## Phase 5 — ML Enhancement (Future)

**Goal**: AI-based trade filtering to reject low-probability setups.

### Tasks

- [ ] **5.1** Collect trade features: BPR width, time of day, structure strength, ATR, session, spread
- [ ] **5.2** Train classifier in Python (logistic regression or small neural net)
- [ ] **5.3** Export to ONNX format
- [ ] **5.4** Embed in EA via `OnnxCreate()` / `OnnxRun()`
- [ ] **5.5** Backtest with vs without ML filter — compare metrics
- [ ] **5.6** If improvement > 10% in profit factor → keep. Otherwise → discard.
- [ ] **5.7** Per-pair parameter optimization: save optimal parameters per symbol to CSV/JSON
- [ ] **5.8** Walk-forward optimization: train on N months, validate on next M months, roll forward

**Deliverables:**
- ONNX model in `models/`
- Comparison backtest results
- Decision: keep or discard ML filter

---

## Final Deliverables (Phase 4 Complete)

1. `BPR_Bot.mq5` — single compile-ready EA file, fully commented
2. `RESEARCH_SUMMARY.md` — strategy research findings
3. `CHANGELOG.md` — track all iterations and fixes
4. `BACKTEST_NOTES.md` — analysis of each backtest run
5. (Future) `models/` directory with per-pair model files if ML phase is reached

---

## Constraints & Rules

1. **Do NOT skip the research phase.** Understanding before building.
2. **Do NOT deviate from the 3 patches.** They are non-negotiable corrections to the base strategy.
3. **Always explain reasoning** when making architectural or strategic decisions.
4. **When a bug is found**, explain what went wrong, why, and how it's being fixed.
5. **Ask questions** if anything in the strategy spec is ambiguous — don't assume.
6. **Output compile-ready code** — no pseudocode, no placeholder functions, no TODOs.
7. **Use only standard MQL5 includes** — no third-party libraries.
8. **Test awareness**: code must work in Strategy Tester (visual and non-visual) and live.

---

## Open Questions

| # | Question | Default | Impact | Resolves In |
|---|----------|---------|--------|-------------|
| 1 | Wine CLI reliable for automation? | Assumed yes | Autonomous vs semi-manual | Phase 0.5 |
| 2 | GTC account: hedging or netting? | Assumed hedging | Position management code | Phase 0.5 |
| 3 | GTC GMT offset? | Assumed +2/+3 | Session filter accuracy | Phase 0.5 |
| 4 | XAUUSD exact symbol name? | Assumed `XAUUSD` | EA symbol parameter | Phase 0.5 |
| 5 | BTCUSD session filter? | Same Asia block | May miss valid BTC setups | Phase 3 |
| 6 | BPR max bar gap? | 30 bars (M15) | Trade frequency | Phase 3 |
| 7 | Spread filter threshold? | 2x average spread | May block valid entries | Phase 3 |
| 8 | Optimal Asia window for gold? | 00:00-09:00 UTC (spec) vs 22:00-07:00 (research) | Entry timing | Phase 3 |
| 9 | Optimal risk per trade? | 10% (spec) — likely too high | Account survival | Phase 3 |

---

*Last updated: 2026-02-25*

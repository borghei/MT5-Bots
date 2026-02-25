# BPR Bot — Master Execution Plan

*This is the single source of truth. Every phase, decision, and document is referenced here.*

---

## Document Map

| Document | Purpose | Status |
|----------|---------|--------|
| **[PLAN.md](PLAN.md)** | This file — master plan, phase tracking, decisions | Active |
| **[RESEARCH_SUMMARY.md](RESEARCH_SUMMARY.md)** | Strategy deep-dive (FVG/BPR rules, XAUUSD/BTCUSD specifics, session filtering, previous code analysis) | Complete |
| **[docs/MQL5_TECHNICAL_REFERENCE.md](docs/MQL5_TECHNICAL_REFERENCE.md)** | Every MQL5 function, property, formula, error code that can cost money | Complete |
| **[docs/AUTOMATION_PIPELINE.md](docs/AUTOMATION_PIPELINE.md)** | Wine commands, INI format, .set file format, report parsing, autonomous loop | Complete |
| **[CLAUDE.md](CLAUDE.md)** | AI development rules — critical technical constraints, coding rules, iteration workflow | Complete |
| **[CHANGELOG.md](CHANGELOG.md)** | What changed per version, with rationale | Ongoing |
| **[docs/BACKTEST_NOTES.md](docs/BACKTEST_NOTES.md)** | Analysis of each backtest run (created during Phase 3) | Not started |

---

## Project Summary

**What**: MT5 Expert Advisor trading the ICT Balanced Price Range (BPR) strategy — overlapping bullish and bearish Fair Value Gaps as entry zones, filtered by market structure and session.

**Where**: GTC Global Trade broker (`GTCGlobalTrade-Server`), macOS Apple Silicon, MT5 via Wine 10.0.

**Pairs**: XAUUSD (primary), BTCUSD (secondary). Per-pair configs.

**Goal**: Fully autonomous — AI handles code, backtesting, optimization, and iteration. Human only approves live deployment.

---

## Phase Overview

| Phase | Name | Status | Depends On |
|-------|------|--------|------------|
| 0 | Research & Planning | **COMPLETE** | — |
| 0.5 | Diagnostics & Wine Validation | **NEXT** | Phase 0 |
| 1 | Core EA Development | Not started | Phase 0.5 |
| 2 | Automation Scripts | Not started | Phase 1 |
| 3 | Iterative Backtesting & Optimization | Not started | Phase 2 |
| 4 | Live Deployment | Not started | Phase 3 + user approval |
| 5 | ML Enhancement | Future | Phase 4 stable |

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
| FVG filter | ATR-based, 4 tiers | Eliminates noise, adapts to volatility per pair | [RESEARCH_SUMMARY.md §1.8](RESEARCH_SUMMARY.md) |
| Time handling | `TimeCurrent() - GMT_offset * 3600` | `TimeGMT()` broken in tester | [MQL5_TECHNICAL_REFERENCE.md §7](docs/MQL5_TECHNICAL_REFERENCE.md) |
| Position sizing | MathFloor (not NormalizeDouble) | NormalizeDouble rounds UP → risks more than intended | [MQL5_TECHNICAL_REFERENCE.md §2.2](docs/MQL5_TECHNICAL_REFERENCE.md) |
| FVG arrays | Fixed-size (200) + aging | Old V2 unbounded arrays stopped working after 100 FVGs | [RESEARCH_SUMMARY.md §7.1 bug #1](RESEARCH_SUMMARY.md) |
| File encoding | UTF-16 LE with BOM | Confirmed from actual .set/.ini files on system | [AUTOMATION_PIPELINE.md §4](docs/AUTOMATION_PIPELINE.md) |
| Compilation check | .ex5 existence (not exit code) | MetaEditor exit code unreliable | [AUTOMATION_PIPELINE.md §2.2](docs/AUTOMATION_PIPELINE.md) |
| Bar indexing | Only bar 1+ for signals | Bar 0 is still forming — OHLC changes every tick | [MQL5_TECHNICAL_REFERENCE.md §1.1](docs/MQL5_TECHNICAL_REFERENCE.md) |
| ObjectFind check | `>= 0` means found | Old V2 used `!ObjectFind()` which is TRUE for main window | [MQL5_TECHNICAL_REFERENCE.md §6.1](docs/MQL5_TECHNICAL_REFERENCE.md) |

---

## Phase 0.5 — Diagnostics & Wine Validation [NEXT]

**Goal**: Confirm all broker unknowns and validate that Wine automation works.

### Tasks

- [ ] **0.5.1** Write `BPR_Diagnostic.mq5` script that prints:
  - Account margin mode (hedging/netting)
  - Server GMT offset (via `TimeCurrent() - TimeGMT()`)
  - All symbols containing "XAU" and "BTC" (exact naming)
  - `SYMBOL_FILLING_MODE`, `SYMBOL_TRADE_EXEMODE` per symbol
  - `SYMBOL_VOLUME_MIN/MAX/STEP`, `SYMBOL_TRADE_TICK_VALUE/SIZE` per symbol
  - `SYMBOL_TRADE_CONTRACT_SIZE`, `SYMBOL_TRADE_STOPS_LEVEL`, `SYMBOL_SPREAD` per symbol
  - `SYMBOL_SWAP_LONG/SHORT`, `SYMBOL_SWAP_ROLLOVER3DAYS` per symbol
  - Leverage, account currency

- [ ] **0.5.2** Test Wine compilation:
  - Copy diagnostic script to `MQL5/Scripts/`
  - Run `metaeditor64.exe /compile:...` via Wine from macOS terminal
  - Verify `.ex5` produced, parse `.log` for errors
  - Document exact working command

- [ ] **0.5.3** User runs diagnostic script:
  - Open MT5 → drag script onto XAUUSD chart → read Journal tab
  - Copy output back to Claude Code

- [ ] **0.5.4** Test Wine backtesting:
  - Use a built-in sample EA (e.g., ExpertMACD)
  - Generate INI file (UTF-16 LE with BOM)
  - Run `terminal64.exe /config:...` via Wine
  - Verify: does it run? Does it exit? Is report generated? Where?

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

### Tasks

- [ ] **1.1** Write EA skeleton: inputs, structs, globals, event handlers
  - All inputs from spec (see [RESEARCH_SUMMARY.md §9 Phase 1](RESEARCH_SUMMARY.md))
  - FVG, BPR, SwingPoint structs with `datetime` timestamps (not bar indices)
  - CTrade initialization with auto-fill detection

- [ ] **1.2** Implement market structure module:
  - `DetectSwingPoints(timeframe, lookback)` — multi-TF support
  - `ClassifyStructure()` — HH/HL/LH/LL → bullish/bearish/range
  - Minimum 3-4 swing points required for classification

- [ ] **1.3** Implement FVG detection:
  - Scan from bar 1 backward (NEVER bar 0)
  - ATR-based size filter (4 tiers, configurable)
  - Temporal continuity check (reject weekend gap FVGs)
  - Deduplication by candle 2's datetime
  - FVG lifecycle tracking (active → tested → mitigated → invalidated)
  - Aging cleanup (remove FVGs > lookback bars old)

- [ ] **1.4** Implement BPR detection:
  - Overlap calculation: `max(B_low, S_low)` to `min(B_high, S_high)`
  - Direction: last FVG's direction (NOT inverted like old V2)
  - Full bounds for SL: `min(both lows)` to `max(both highs)`
  - Minimum BPR width filter (ATR-based)
  - PATCH 1: `used` flag
  - PATCH 3: `formed_date` for daily expiry

- [ ] **1.5** Implement BPR validation:
  - Close-through invalidation (not wick-through)
  - Daily expiry check (PATCH 3)
  - Expire on new trading day start

- [ ] **1.6** Implement session filter:
  - `GetGMTTime()` with tester-aware broker offset + DST detection
  - Configurable block window (default: 22:00-07:00 UTC for XAUUSD)
  - Midnight wraparound handling

- [ ] **1.7** Implement entry logic:
  - Price in BPR zone (previous bar close)
  - Structure alignment (bullish structure + bullish BPR, or bearish + bearish)
  - BPR not used (PATCH 1)
  - Session not blocked
  - No existing position (unless AllowMultiple)

- [ ] **1.8** Implement position sizing:
  - Fresh `SYMBOL_TRADE_TICK_VALUE` per trade
  - `OrderCalcProfit()` fallback
  - `MathFloor` for lot normalization (NEVER NormalizeDouble alone)
  - Clamp to min/max/step, skip if below min

- [ ] **1.9** Implement trade execution:
  - `CTrade.Buy/Sell` with stops level validation
  - Retry logic for requote/price_changed
  - Mark BPR as used (PATCH 1)
  - Full retcode handling per [MQL5_TECHNICAL_REFERENCE.md §3](docs/MQL5_TECHNICAL_REFERENCE.md)

- [ ] **1.10** Implement visuals:
  - BPR boxes with sequential ID naming
  - Color coding: active (green/red), used (gray), expired (dotted)
  - Full cleanup in `OnDeinit`
  - Correct `ObjectFind` usage (`>= 0`, not `!`)

- [ ] **1.11** Implement OnTester metric:
  - `0.4 * ProfitFactor + 0.3 * Sharpe + 0.3 * RecoveryFactor`
  - Returns meaningful fitness for genetic optimizer

- [ ] **1.12** Self-test:
  - Mental trace through 5 scenarios (see [original prompt Phase 3.1](RESEARCH_SUMMARY.md))
  - Verify all 3 patches in code
  - Compile with zero warnings

**Deliverables:**
- `src/BPR_Bot.mq5` — single compile-ready file
- Default `.set` files for XAUUSD and BTCUSD
- Zero compilation warnings

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
- [ ] **3.2** Analyze results → document in [docs/BACKTEST_NOTES.md](docs/BACKTEST_NOTES.md)
- [ ] **3.3** Iterate: adjust parameters and/or code based on diagnosis
- [ ] **3.4** Target metrics:
  - Profit Factor > 1.5
  - Max Drawdown < 20%
  - Win Rate > 45%
  - Total Trades > 100 (statistical significance)
  - Sharpe Ratio > 1.0
- [ ] **3.5** Walk-forward validation: train 6 months, validate 2 months, roll forward
- [ ] **3.6** Save best XAUUSD params as `.set` file
- [ ] **3.7** Repeat for BTCUSD (with adjusted defaults: Very Defensive filter, lower leverage)
- [ ] **3.8** Multi-broker support: if second broker added, create separate configs

**Deliverables:**
- Optimized `.set` files per pair
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

**Deliverables:**
- ONNX model in `models/`
- Comparison backtest results
- Decision: keep or discard ML filter

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

---

*Last updated: 2026-02-25*

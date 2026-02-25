# BPR Bot - Changelog

## [1.0.0] - 2026-02-25 - Phase 1 Complete: EA Build + Optimization

### Phase 1 EA — BPR_Bot.mq5 (~1170 lines)
- Full BPR (Balanced Price Range / Double FVG) strategy implementation
- FVG detection with close-confirmation, ATR-based size filter (4 tiers)
- BPR overlap zone calculation with full_high/full_low for SL placement
- Market structure analysis on entry TF + higher TF (swing HH/HL/LH/LL)
- Session filter blocking Asia hours (00:00-09:00 UTC)
- Position sizing via equity fraction with tick-value lookup + OrderCalcProfit fallback
- Three non-negotiable patches: one-trade-per-BPR, SL at BPR extremes, daily expiry
- OnTester custom metric: `PF * 0.4 + Sharpe * 0.3 + RecoveryFactor * 0.3`

### Chart Visualization
- BPR boxes drawn as colored rectangles (green=bull, red=bear, gray=used)
- Trade entry arrows (green up-arrow for buy, red down-arrow for sell)
- SL lines (red dashed) and TP lines (blue dashed)
- BPR box extends to trade entry time when consumed

### Iterative Backtesting (15 iterations)
| Iter | Key Change | Trades | WR% | PF | DD% | Net$ |
|------|-----------|--------|------|------|------|------|
| 3 | Strict structure align, SwingN=5 | 26 | 30.8 | 0.80 | 17.7 | -729 |
| 4 | Relaxed entry TF + ATR min filters | 54 | 27.8 | 0.71 | 26.5 | -2,015 |
| 5 | Rejection candle filter, RR=2.5 | 14 | 28.6 | 0.92 | 8.1 | -154 |
| 6 | Zone-half filter, RR=3.0 | 40 | 17.5 | 0.58 | 28.8 | -2,522 |
| 7 | Wick-touch trigger model | 46 | 19.6 | 0.57 | 27.2 | -2,715 |
| **8** | **Close-in-zone + rejection + FVGTier=1** | **35** | **31.4** | **1.10** | **8.8** | **+493** |
| 9 | No Asia filter, Lookback=50 | 52 | 25.0 | 0.78 | 23.8 | -1,544 |
| 10 | RR=2.0, Asia 00-06, SwingN=3 | 36 | 30.6 | 0.83 | 18.4 | -835 |
| 11 | FVGTier=0 (same as iter 8) | 35 | 31.4 | 1.10 | 8.8 | +491 |
| 12 | M5 entry, M30 HTF | 95 | 28.4 | 0.93 | 33.3 | -962 |
| 13 | M5 entry, H1 HTF, FVGTier=2 | 102 | 27.5 | 0.86 | 36.0 | -1,823 |
| 14 | H1 entry, H4 HTF | 5 | 20.0 | 0.61 | 6.7 | -292 |
| 15 | Iter 8 at 5% risk | 35 | 31.4 | 1.05 | 20.9 | +569 |

### Key Findings
- **RR=2.5 is optimal** — RR=3.0 killed win rate, RR=2.0 reduced edge
- **Rejection candle + close-inside-zone** is the best entry filter combination
- **Asia session filter is essential** — removing it adds losing trades
- **M15 entry / H1 HTF** is the best timeframe combo for trade quality
- **ATR-based minimum BPR width (0.15x ATR)** prevents tiny-zone lot explosions

### Genetic Optimizer (Phase 3)
- Ran MT5 genetic optimizer with 5 parameters: RR, SLBuffer, Lookback, SwingN, FVGTier
- 165 passes completed, custom OnTester criterion
- **Best result (Pass 64):**
  - RR=2.5, SLBufferPoints=5, BPRLookbackBars=50, SwingLookback=4, FVGFilterTier=0
  - **PF=1.14, Sharpe=3.98, 40 trades, WR=32.5%, DD=15.8%, Net=+$794**
  - Improved over manual iteration 8: +5 trades, better Sharpe (3.98 vs 2.42)

### Bug Fixes
- Fixed trade comment using `g_bprIdCounter` instead of BPR's `box_name`
- Fixed tiny BPR overlap zones causing instant stops and 4.98 lot positions
- Added ATR-based minimum SL distance (0.2x ATR) safety check

## [0.3.0] - 2026-02-25 - Plan Alignment with Original Strategy Spec

### Discrepancies Fixed (PLAN.md vs Original Prompt)
- **FVG close-confirmation condition restored**: Original spec requires BOTH gap check AND `Close[candle2]` confirmation. Was missing from all docs — now in PLAN.md, RESEARCH_SUMMARY.md, and CLAUDE.md
- **Session filter default restored**: Original spec says 00:00-09:00 UTC. Research had changed to 22:00-07:00 UTC without noting the deviation. Now: original default kept, research recommendation noted for Phase 3 optimization
- **SwingLookback default restored**: Original spec says N=3. Research recommended N=5. Now: N=3 as default, N=5 noted as research recommendation
- **Risk default restored**: Original spec says 10% per trade. Docs had changed to risk profiles. Now: 10% kept as starting default, risk profiles documented for Phase 3/4 tuning
- **All 22 input parameters listed**: Exact names, types, and defaults from original prompt now in PLAN.md Strategy Specification section
- **Data structures listed**: Exact FVG, BPR struct fields and MARKET_STRUCTURE enum from original prompt
- **All 15 core functions listed**: Consolidated function table in PLAN.md
- **5 self-test scenarios listed**: Scenarios A-E with exact expected outcomes
- **Backtest analysis protocol added**: 4-step diagnostic checklist from original prompt
- **Code quality standards added**: Commenting, naming, logging rules from original prompt
- **Constraints & Rules section added**: 8 non-negotiable rules from original prompt
- **Final Deliverables section added**: Matches original Phase 4 deliverables exactly

### Added to PLAN.md
- Full "Strategy Specification (Authoritative)" section — the single source of truth for Phase 1
- Research notes where defaults differ from original spec (clearly marked as optimization candidates)
- Open questions #8 and #9 for session window and risk per trade optimization
- Phase 3 now lists specific parameters to optimize with ranges

### Updated
- `RESEARCH_SUMMARY.md` §1.2-1.3 — FVG formulas now include close-confirmation condition
- `CLAUDE.md` — FVG Detection section now includes both conditions with series indexing
- `CHANGELOG.md` — this entry

## [0.2.0] - 2026-02-25 - Phase 0: Deep Research Pass

### Research Depth
Every detail researched to the level that matters when real money is at stake.

### Strategy Precision Added
- FVG candle ordering: exact MQL5 bar index mapping (Candle 1 = `i+2`, Candle 3 = `i`)
- FVG zone boundaries: WICKS only (High/Low), never bodies — common algorithmic mistake documented
- FVG lifecycle states: Active → Tested → Partially Filled → Mitigated → Invalidated
- FVG invalidation: close-based (not wick-based) — wick-through + close-inside = confirmation
- Inversion FVGs (IFVGs): polarity flip rules documented for future phases
- Consequent Encroachment (CE): 50% level of FVG/BPR as optimal entry
- BPR direction: DEFINITIVELY confirmed — last FVG determines direction (cross-referenced 6+ sources)
- BPR overlap math: exact formula with full_high/full_low for PATCH 2 SL
- 8 common FVG detection mistakes documented with prevention methods
- ATR-based 4-tier FVG filter adopted from ICT_BPR indicator

### XAUUSD Deep Dive
- Price mechanics: $1.00/tick/lot (2-digit), 100 oz/lot, position sizing worked example
- Spread ranges: $0.15-$0.30 (London/NY) to $1.00-$5.00+ (news)
- Session behavior: Asia range-bound, London Judas swing, NY distribution
- Gold-specific FVG considerations: Defensive (0.3x ATR) filter, $2-$8 typical M15 FVG
- DXY correlation weakened in 2024-2026 — documented

### BTCUSD Deep Dive
- Flash crash risks: Oct 2025 ($19B liquidated), Dec 2025 (flash to $24K from $100K+)
- Leverage warning: 1:2000 on BTC = 0.05% move liquidates. Max recommended: 5x-10x
- Swap costs: ~$55/night at $100K BTC price. Triple Wednesday = ~$165
- Session behavior: Traditional model partially applies, maintenance windows
- Spread widening: order book depth can shrink >90% during stress

### MQL5 Technical Precision
- Created `docs/MQL5_TECHNICAL_REFERENCE.md` — exhaustive reference
- CopyRates: bar 0 is forming (NEVER use for patterns), failure modes, multi-TF in tester
- Position sizing: exact formula with MathFloor (not NormalizeDouble — rounds UP!)
- OrderCalcProfit fallback when tickValue=0
- CTrade: 30+ error codes documented with exact causes and fixes
- All SYMBOL properties listed with when each matters
- OnTick single-threaded model: ticks queued, intermediates lost
- New bar detection: iTime comparison (not Bars() — unreliable)
- ObjectFind: returns subwindow index (0+) or -1, NOT boolean
- TimeGMT broken in tester — documented workaround with DST handling
- Netting vs hedging: code differences, position enumeration patterns

### Automation Pipeline
- Created `docs/AUTOMATION_PIPELINE.md` — exact commands for this system
- MetaEditor CLI: works via Wine, headless, offline, but exit code unreliable
- terminal64.exe: works via Wine, window appears, ShutdownTerminal=1 exits cleanly
- All config files: UTF-16 LE with BOM (confirmed from actual files on system)
- .set file format: reverse-engineered from actual MACD Sample.set on system
- Report parsing: Python HTML parser with metric extraction
- Full autonomous loop documented step by step
- Performance estimates: 2-3x slower than native Windows
- Rosetta 2 longevity: confirmed through macOS 27 (~2-3 years)

### Updated
- `RESEARCH_SUMMARY.md` — complete rewrite with all precision details
- `CLAUDE.md` — every critical technical rule that can cost money
- `CHANGELOG.md` — this file

## [0.1.0] - 2026-02-24 - Phase 0: Initial Research & Planning

### Added
- Initial project structure and research
- Analysis of old MQ5-BPR repo (10 critical bugs)
- System discovery (MT5 paths, Wine config, broker connection)
- GitHub repository created at github.com/borghei/MT5-Bots

# BPR Bot - Changelog

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

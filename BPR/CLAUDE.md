# BPR Bot — AI Development Instructions

## Project Overview
MetaTrader 5 Expert Advisor implementing the **Balanced Price Range (BPR / Double FVG)** strategy from ICT/SMC methodology. The bot detects overlapping bullish and bearish Fair Value Gaps, enters when price retraces into the overlap zone aligned with market structure.

## Architecture
- **Single file EA**: `src/BPR_Bot.mq5` — must compile standalone in MetaEditor
- **Automation scripts**: `scripts/` — Python orchestrator for autonomous backtesting
- **Reports**: `reports/` — parsed backtest results per iteration
- **Models**: `models/` — future ONNX models per trading pair

## Non-Negotiable Patches
These 3 patches must ALWAYS be implemented correctly:

1. **PATCH 1 — One Trade Per BPR**: Each BPR can trigger at most one trade. Set `used=true` immediately on execution.
2. **PATCH 2 — SL at BPR Extremes**: Stop Loss placed beyond `full_high`/`full_low` of the ENTIRE BPR (both FVGs), NOT just the overlap zone.
3. **PATCH 3 — Daily Expiry**: BPRs expire at end of the trading day they were formed. No carryover.

## Key Technical Decisions
- Use `TimeCurrent() + GMT_offset` (not `TimeGMT()`) — broken in Strategy Tester
- FVG arrays must have aging/cleanup — prevent unbounded growth
- Store `datetime` timestamps, not bar indices (indices shift every bar)
- Read `SYMBOL_TRADE_TICK_VALUE` fresh per trade, not cached
- Use `CTrade::SetTypeFillingBySymbol()` for auto-fill detection
- BPR direction = last FVG's direction (standard ICT convention)

## Coding Standards
- Every function has a header comment
- Complex logic blocks have inline comments
- Meaningful variable names (no single letters except loop counters)
- Functions grouped by section with separators
- Log important events: trade execution, BPR creation/invalidation/expiry, structure changes
- Must compile without warnings in MetaEditor
- Must work in both Strategy Tester and live trading

## Iteration Workflow
1. Modify code → compile → backtest → parse results
2. Analyze metrics: profit factor, Sharpe, max DD, win rate, trade count
3. Diagnose issues: too many/few trades, bad SL placement, poor R:R, session problems
4. Propose specific changes with rationale
5. Implement → repeat

## File Structure
```
BPR/
├── src/BPR_Bot.mq5          # The EA
├── scripts/                  # Python automation
├── models/                   # ONNX models (future)
├── reports/                  # Backtest results
├── docs/BACKTEST_NOTES.md    # Analysis log
├── RESEARCH_SUMMARY.md
├── CHANGELOG.md
├── CLAUDE.md                 # This file
└── README.md
```

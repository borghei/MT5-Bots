# BPR Bot - Changelog

## [0.1.0] - 2026-02-24 - Phase 0: Research & Plan (Updated)

### Research Completed
- Deep-dive: FVG detection (3-candle wick gap), BPR formation (overlap of opposite FVGs), direction rules
- Deep-dive: Market structure (swing HH/HL/LH/LL), session filtering, MT5 EA architecture
- Analyzed old repo `github.com/borghei/MQ5-BPR` — identified 10 critical bugs in V2
- Analyzed `~/Desktop/All/BPR/V2/ICT_BPR.mq5` indicator — extracted ATR-based FVG filter design
- Researched GTC Global Trade broker — likely hedging, GMT+2/+3, standard symbol names
- Researched MT5 on macOS — Wine bundle works, no Parallels needed
- Researched autonomous pipeline — Wine CLI compilation + INI-based backtesting

### System Discovery
- Found MT5 installed at `/Applications/MetaTrader 5.app` (v5.0.5260, Wine 10.0)
- Mapped all paths: MQL5 root, Experts, Tester, Config directories
- Found broker connection: GTCGlobalTrade-Server, login 5935483
- Found existing reference code: V1 EA, V2 EA, ICT_BPR indicator

### Plan Created
- Multi-broker / multi-pair architecture with per-pair .set files
- Wine-native automation pipeline (compile + backtest from macOS shell)
- 6-phase execution plan: Diagnostics → EA → Automation → Optimization → Live → ML
- 3 risk profiles: Backtest (1%), Medium (2-3%), Aggressive (5-10%)
- XAUUSD as primary pair, BTCUSD as secondary

### Added
- `RESEARCH_SUMMARY.md` — comprehensive plan with 11 sections
- `CLAUDE.md` — AI development instructions with key paths and decisions
- Project structure: `src/`, `scripts/`, `configs/`, `presets/`, `models/`, `reports/`, `docs/`

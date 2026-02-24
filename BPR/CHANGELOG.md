# BPR Bot - Changelog

## [0.0.0] - 2026-02-24 - Phase 0: Research & Planning

### Added
- `RESEARCH_SUMMARY.md` — comprehensive strategy and technical research
- Project directory structure (`src/`, `scripts/`, `models/`, `reports/`, `docs/`)
- `CLAUDE.md` — AI development instructions
- Analysis of previous implementation (github.com/borghei/MQ5-BPR) — identified 10 critical bugs
- Autonomous operation pipeline design (Python orchestrator + MT5 + Claude API)

### Research Findings
- Confirmed FVG detection formula (3-candle wick gap, not body gap)
- Confirmed BPR direction = last FVG's direction (standard ICT convention)
- Identified `TimeGMT()` broken in Strategy Tester — using `TimeCurrent() + offset` instead
- Identified unbounded FVG array as root cause of old V2 stopping after ~100 FVGs
- Evaluated macOS options: Parallels (best), Docker/QEMU (headless), Wine (basic)
- Designed automation loop: Python → INI → MT5 backtest → parse report → AI analysis → iterate

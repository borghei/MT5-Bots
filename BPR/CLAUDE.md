# BPR Bot — AI Development Instructions

## Project Overview
MetaTrader 5 Expert Advisor implementing the **Balanced Price Range (BPR / Double FVG)** strategy from ICT/SMC methodology. Targets **XAUUSD** (primary) and **BTCUSD** (secondary) on GTC Global Trade broker.

## Key Paths (macOS + Wine)
```
WINE="/Applications/MetaTrader 5.app/Contents/SharedSupport/wine/bin/wine64"
WINEPREFIX="~/Library/Application Support/net.metaquotes.wine.metatrader5"
MT5_ROOT="$WINEPREFIX/drive_c/Program Files/MetaTrader 5"
MQL5_DIR="$MT5_ROOT/MQL5"
EXPERTS="$MQL5_DIR/Experts"
TESTER="$MT5_ROOT/Tester"
CONFIG="$MT5_ROOT/config"
```

## Broker: GTC Global Trade
- Server: `GTCGlobalTrade-Server`
- Login: `5935483`
- Leverage: up to 1:2000 (Standard/Pro) or 1:500 (ECN)
- GMT offset: **Unknown — likely +2/+3 (DST). Must confirm via diagnostic script.**
- Account mode: **Unknown — likely hedging. Must confirm.**
- Symbol names: **Unknown — likely XAUUSD, BTCUSD. Must confirm.**

## Architecture
- **Single file EA**: `src/BPR_Bot.mq5` — compiles standalone
- **Per-pair configs**: `configs/pairs/XAUUSD.json`, `BTCUSD.json`
- **Per-broker configs**: `configs/brokers/gtc_global.json`
- **Risk profiles**: `configs/profiles/backtest.json`, `aggressive.json`, `medium.json`
- **Generated presets**: `presets/BPR_XAUUSD_backtest.set` etc.
- **Automation scripts**: `scripts/` — compile, backtest, parse, deploy

## Non-Negotiable Patches
1. **PATCH 1 — One Trade Per BPR**: `used=true` immediately on execution.
2. **PATCH 2 — SL at BPR Extremes**: SL beyond `full_high`/`full_low` of ENTIRE BPR, NOT just overlap.
3. **PATCH 3 — Daily Expiry**: BPRs expire at end of trading day. No carryover.

## Key Technical Decisions
- `TimeCurrent() - GMT_offset * 3600` for UTC (not `TimeGMT()` — broken in Tester)
- FVG arrays: fixed-size (200) with aging/cleanup. Daily reset. Prevents V2 unbounded growth bug.
- Store `datetime` timestamps, not bar indices (indices shift every bar)
- Read `SYMBOL_TRADE_TICK_VALUE` fresh per trade (not cached)
- `CTrade::SetTypeFillingBySymbol()` for auto-fill detection
- BPR direction = last FVG's direction (standard ICT convention)
- ATR-based FVG filter (4 tiers from ICT_BPR indicator: 0.1x/0.2x/0.3x/0.5x ATR)
- Magic number per pair: 240001=XAUUSD, 240002=BTCUSD, etc.
- OnTester custom metric: 0.4×ProfitFactor + 0.3×Sharpe + 0.3×RecoveryFactor

## Reference Code
- `~/Desktop/All/BPR/V2/ICT_BPR.mq5` — indicator with clean FVG/BPR detection, ATR filter
- `github.com/borghei/MQ5-BPR/BPR_Bot_V2.mq5` — old EA with 10 critical bugs (see RESEARCH_SUMMARY.md §4)

## Automation Pipeline (Wine-native, no Parallels)
```
Compile:  WINEPREFIX="$WINEPREFIX" "$WINE" metaeditor64.exe /compile:path.mq5 /log
Backtest: WINEPREFIX="$WINEPREFIX" "$WINE" terminal64.exe /config:backtest.ini
```

## Execution Phases
0.5. Diagnostics — confirm broker params (account mode, GMT offset, symbols, filling)
1. Core EA — full BPR strategy with all 3 patches
2. Automation — compile/backtest/parse/analyze loop
3. Optimization — iterative backtesting, walk-forward, per-pair param tuning
4. Live deployment — medium then aggressive risk profiles
5. ML enhancement — ONNX model for trade filtering (future)

## Risk Profiles
| Profile | Risk/Trade | Use |
|---------|-----------|-----|
| Backtest | 1% | Optimization |
| Medium | 2-3% | Conservative live |
| Aggressive | 5-10% | High-risk live |

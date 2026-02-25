# BPR Bot — AI Development Instructions

## Project Overview
MetaTrader 5 Expert Advisor: **Balanced Price Range (BPR / Double FVG)** strategy from ICT/SMC.
Primary pair: **XAUUSD**, secondary: **BTCUSD**, on GTC Global Trade broker.

## Key Paths (macOS + Wine)
```bash
WINE="/Applications/MetaTrader 5.app/Contents/SharedSupport/wine/bin/wine64"
WINEPREFIX="~/Library/Application Support/net.metaquotes.wine.metatrader5"
MT5_ROOT="$WINEPREFIX/drive_c/Program Files/MetaTrader 5"
EXPERTS="$MT5_ROOT/MQL5/Experts"
TESTER_PRESETS="$MT5_ROOT/MQL5/Profiles/Tester"
TESTER="$MT5_ROOT/Tester"
CONFIG="$MT5_ROOT/config"
# Wine drive: C: → drive_c/, Z: → / (macOS root)
```

## Broker: GTC Global Trade
- Server: `GTCGlobalTrade-Server`, Login: `5935483`
- Leverage: up to 1:2000 (Standard/Pro), 1:500 (ECN)
- GMT offset: **Likely +2 winter / +3 summer (EET). Must confirm via diagnostic.**
- Account mode: **Likely hedging. Must confirm.**

## Reference Docs
- `RESEARCH_SUMMARY.md` — Strategy details, pair specifics, phase plan
- `docs/MQL5_TECHNICAL_REFERENCE.md` — Every MQL5 function/property/formula
- `docs/AUTOMATION_PIPELINE.md` — Wine commands, INI format, report parsing

## Non-Negotiable Patches
1. **PATCH 1 — One Trade Per BPR**: `bpr.used = true` on ExecuteTrade().
2. **PATCH 2 — SL at BPR Extremes**: SL beyond `full_high`/`full_low` of ENTIRE BPR.
3. **PATCH 3 — Daily Expiry**: BPRs expire at end of their formation day.

## Critical Technical Rules (Every One Can Cost Money)

### FVG Detection
- Boundaries = **wicks** (High/Low), NEVER bodies (Open/Close)
- Only scan from **bar 1** (last completed) backward — NEVER bar 0 (still forming)
- Check temporal continuity — reject FVGs spanning weekend/holiday gaps
- Deduplicate by candle 2's `datetime` — prevent counting same FVG twice
- ATR-based minimum size filter: Defensive (0.3x ATR) for XAUUSD, Very Defensive (0.5x ATR) for BTCUSD

### BPR Direction
- **Last FVG determines direction** (standard ICT convention)
- Bullish FVG came last → Bullish BPR → LONG
- Bearish FVG came last → Bearish BPR → SHORT
- Old V2 had this **INVERTED** — do not repeat

### Position Sizing
- Read `SYMBOL_TRADE_TICK_VALUE` **fresh per trade** (NEVER cache)
- If tickValue ≤ 0: use `OrderCalcProfit()` fallback
- **Always MathFloor** for lot sizes (never NormalizeDouble alone — it rounds UP)
- Clamp to SYMBOL_VOLUME_MIN/MAX/STEP

### Time Handling
- `TimeGMT()` is **BROKEN in Tester** — returns same as TimeCurrent()
- Use `TimeCurrent() - broker_gmt_offset * 3600` in tester
- Handle DST transitions (most brokers: GMT+2 winter, GMT+3 summer)

### CTrade
- `SetTypeFillingBySymbol(_Symbol)` — auto-detect filling mode
- Check `SYMBOL_TRADE_STOPS_LEVEL` before placing SL/TP
- Implement retry for: REQUOTE (10004), PRICE_CHANGED (10020)
- Do NOT retry: NO_MONEY (10019), INVALID_STOPS (10016), INVALID_VOLUME (10014)

### ObjectFind
- Returns subwindow index (0+) if found, **-1** if not found
- Correct: `ObjectFind(0, name) >= 0` means exists
- Old V2 bug: `!ObjectFind(0, name)` — this is TRUE when object is in main window!

### CopyRates
- `ArraySetAsSeries(rates, true)` → rates[0] = current bar, rates[1] = last completed
- Can return fewer bars than requested — always check `copied >= minimum_needed`
- In tester: multi-TF works (H1 from M15 EA) — tester constructs higher TF bars

### Arrays
- FVG arrays: fixed-size (200) with aging + daily cleanup — prevents V2 unbounded growth
- Store `datetime` timestamps, NOT bar indices (indices shift every bar)

## File Encoding
- All `.set` files: **UTF-16 LE with BOM**
- All `.ini` files: **UTF-16 LE with BOM**
- All `.log` files from MetaEditor/MT5: **UTF-16 encoded**
- Parse with: `iconv -f UTF-16LE -t UTF-8` or Python `codecs.open(f, 'r', 'utf-16-le')`

## OnTester Custom Metric
```mql5
double OnTester() {
    double pf = TesterStatistics(STAT_PROFIT_FACTOR);
    double sharpe = TesterStatistics(STAT_SHARPE_RATIO);
    double rf = TesterStatistics(STAT_RECOVERY_FACTOR);
    return pf * 0.4 + sharpe * 0.3 + rf * 0.3;
}
```

## Risk Profiles
| Profile | Risk/Trade | XAUUSD Leverage | BTCUSD Leverage |
|---------|-----------|-----------------|-----------------|
| Backtest | 1-2% | Any | 5x-10x effective |
| Medium | 2-3% | Any | 3x-5x effective |
| Aggressive | 5-10% | Any | 5x-10x effective |

**NEVER use full 1:2000 leverage on BTCUSD.** A 0.05% move at 2000:1 = instant liquidation.

## Iteration Workflow
1. Modify code/params → `compile.sh` → check .ex5 + .log
2. Generate .set (UTF-16 LE) → `MQL5/Profiles/Tester/`
3. Generate .ini (UTF-16 LE) → `config/`
4. Launch: `terminal64.exe /config:backtest.ini` via Wine
5. Wait for exit → kill wineserver
6. Parse report → analyze metrics
7. Diagnose → propose changes → git commit → repeat

# MQL5 Technical Reference — Every Detail That Can Cost Money

*This document contains exact specifications for every MQL5 operation in the BPR Bot. No approximations.*

---

## 1. CopyRates() — Exact Behavior

### 1.1 Bar Indexing

```mql5
MqlRates rates[];
ArraySetAsSeries(rates, true);  // MUST set before CopyRates
int copied = CopyRates(_Symbol, PERIOD_CURRENT, 0, 200, rates);
// rates[0] = current forming bar (INCOMPLETE — OHLC changes every tick)
// rates[1] = last completed bar (SAFE for pattern detection)
// rates[199] = oldest bar
```

**Rule: NEVER use `rates[0]` for FVG/BPR detection.** Bar 0 is still forming — its High/Low/Close change with every tick. Use `rates[1]` as the newest completed bar.

### 1.2 Return Values and Failures

| Return | Meaning | Action |
|--------|---------|--------|
| `N` (positive) | N bars copied (may be < requested) | Check `N >= minimum_needed` |
| `-1` | Complete failure | `GetLastError()`, retry on next tick |

**Failure conditions:**
- **Live, first call after startup**: History not synced yet. Check `SeriesInfoInteger(_Symbol, tf, SERIES_SYNCHRONIZED)`.
- **Live, secondary symbol/TF**: Data may not be loaded. Use `SymbolSelect(symbol, true)` first.
- **Tester, early bars**: Fewer bars available than requested (test just started).
- **Tester, multi-TF**: H1 from M15 EA works — tester constructs H1 from M15 data. But lower TF from higher (M5 from H1) may lack precision.

### 1.3 Weekend Gaps

No placeholder bars exist for market-closed periods. Friday 23:45 M15 bar is immediately followed by Sunday/Monday's first bar. Bar indices remain contiguous. Time difference between consecutive bars will show ~48 hours over weekends.

**Implication for FVG detection**: If candles 1-2-3 span a weekend gap, this is NOT a valid FVG. Check timestamp differences:

```mql5
int expectedSeconds = PeriodSeconds(PERIOD_CURRENT);
datetime timeDiff = rates[i].time - rates[i+1].time;
if(timeDiff > expectedSeconds * 3) // Allow some tolerance
    return; // Skip — gap between candles (weekend/holiday)
```

---

## 2. Position Sizing — Exact Formula

### 2.1 The Universal Formula

```mql5
// Step 1: Read fresh symbol properties (NEVER cache these across ticks)
double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

// Step 2: Fallback if tickValue is 0
if(tickValue <= 0.0)
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double profit = 0;
    if(OrderCalcProfit(ORDER_TYPE_BUY, _Symbol, 1.0, ask, ask + tickSize, profit))
        tickValue = MathAbs(profit);
    else
    {
        LogMessage("CRITICAL: Cannot determine tick value — skipping trade");
        return 0.0;
    }
}

// Step 3: Calculate risk amount
double equity = AccountInfoDouble(ACCOUNT_EQUITY);
double riskMoney = equity * riskFraction;

// Step 4: Calculate SL distance in price
double slDistancePrice = MathAbs(entryPrice - slPrice);

// Step 5: Calculate dollar value of SL per 1 lot
double slValuePerLot = slDistancePrice / tickSize * tickValue;

// Step 6: Calculate raw lot size
double rawLots = riskMoney / slValuePerLot;

// Step 7: Normalize (ALWAYS floor, never round)
double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

rawLots = MathFloor(rawLots / lotStep) * lotStep;

int stepDigits = (int)MathCeil(-MathLog10(lotStep));
rawLots = NormalizeDouble(rawLots, stepDigits); // Safe after MathFloor

if(rawLots < minLot)
{
    LogMessage("Calculated lots " + DoubleToString(rawLots, stepDigits) +
               " below minimum " + DoubleToString(minLot, stepDigits) + " — skipping trade");
    return 0.0;
}
if(rawLots > maxLot) rawLots = maxLot;

return rawLots;
```

### 2.2 Why MathFloor, Not NormalizeDouble

`NormalizeDouble(0.0156, 2)` returns **0.02** (rounds UP). This means you risk MORE than intended.
`MathFloor(0.0156 / 0.01) * 0.01` returns **0.01** (rounds DOWN). This risks LESS than intended — always safe.

**When money is at stake, always round DOWN on position sizes.**

### 2.3 XAUUSD Worked Example

```
Equity:        $10,000
Risk:          2% = $200
Entry:         2650.50
SL:            2645.50 (500 points below, $5.00)
Tick value:    $1.00 (per lot per 0.01 move)
Tick size:     0.01

slDistancePrice = |2650.50 - 2645.50| = 5.00
slValuePerLot   = 5.00 / 0.01 * $1.00 = $500.00
rawLots         = $200 / $500 = 0.40

Verify: 0.40 lots × 100 oz × $5.00/oz = $200 ✓
```

### 2.4 BTCUSD Worked Example (contract_size=1)

```
Equity:        $10,000
Risk:          1% = $100
Entry:         97,500.00
SL:            97,000.00 (50,000 points below, $500)
Tick value:    $0.01 (per lot per 0.01 move, if contract=1 BTC)
Tick size:     0.01

slDistancePrice = |97500.00 - 97000.00| = 500.00
slValuePerLot   = 500.00 / 0.01 * $0.01 = $500.00
rawLots         = $100 / $500 = 0.20

Verify: 0.20 lots × 1 BTC × $500/BTC = $100 ✓
```

---

## 3. CTrade — Error Handling That Prevents Losses

### 3.1 Initialization

```mql5
#include <Trade/Trade.mqh>
CTrade trade;

// In OnInit():
trade.SetExpertMagicNumber(magicNumber);
trade.SetDeviationInPoints(Inp_DeviationPoints);
trade.SetTypeFillingBySymbol(_Symbol); // Auto-detect filling mode
```

### 3.2 trade.Buy() / trade.Sell() — price=0 Behavior

```mql5
trade.Buy(volume, symbol, 0, sl, tp, comment);  // price=0 → uses current Ask
trade.Sell(volume, symbol, 0, sl, tp, comment); // price=0 → uses current Bid
```

When `price=0`, CTrade automatically fills in the current market price. This is the recommended approach for market orders — avoids stale prices.

### 3.3 Stops Level Validation (Error 10016 Prevention)

```mql5
long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
double stopsDistance = stopsLevel * SymbolInfoDouble(_Symbol, SYMBOL_POINT);

// For BUY:
//   SL must be < Bid - stopsDistance
//   TP must be > Ask + stopsDistance
// For SELL:
//   SL must be > Ask + stopsDistance
//   TP must be < Bid - stopsDistance

// If stopsLevel is 0, broker may still enforce spread as minimum
if(stopsLevel == 0)
    stopsDistance = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
```

### 3.4 Complete Error Handling Template

```mql5
bool ExecuteTradeWithRetry(bool isBuy, double volume, double sl, double tp,
                           string comment, int maxRetries = 3)
{
    for(int attempt = 0; attempt < maxRetries; attempt++)
    {
        ResetLastError();

        bool sent;
        if(isBuy)
            sent = trade.Buy(volume, _Symbol, 0, sl, tp, comment);
        else
            sent = trade.Sell(volume, _Symbol, 0, sl, tp, comment);

        uint retcode = trade.ResultRetcode();

        // SUCCESS
        if(retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_DONE_PARTIAL)
            return true;

        // RETRYABLE
        if(retcode == TRADE_RETCODE_REQUOTE || retcode == TRADE_RETCODE_PRICE_CHANGED ||
           retcode == TRADE_RETCODE_PRICE_OFF)
        {
            LogMessage("Retryable error " + IntegerToString(retcode) +
                       ", attempt " + IntegerToString(attempt + 1));
            Sleep(100); // Only works in scripts; in EA, just continue to next attempt
            continue;
        }

        // NON-RETRYABLE — stop immediately
        if(retcode == TRADE_RETCODE_NO_MONEY ||
           retcode == TRADE_RETCODE_INVALID_VOLUME ||
           retcode == TRADE_RETCODE_INVALID_STOPS ||
           retcode == TRADE_RETCODE_INVALID ||
           retcode == TRADE_RETCODE_MARKET_CLOSED ||
           retcode == TRADE_RETCODE_TRADE_DISABLED ||
           retcode == TRADE_RETCODE_INVALID_FILL ||
           retcode == TRADE_RETCODE_LIMIT_POSITIONS)
        {
            LogMessage("Non-retryable error " + IntegerToString(retcode) +
                       ": " + trade.ResultRetcodeDescription());
            return false;
        }

        // UNKNOWN — log and retry once
        LogMessage("Unknown retcode " + IntegerToString(retcode) +
                   ": " + trade.ResultRetcodeDescription());
    }
    return false;
}
```

### 3.5 Key Error Codes Reference

| Code | Name | Cause | Fix |
|------|------|-------|-----|
| 10009 | DONE | Success | — |
| 10010 | DONE_PARTIAL | Partial fill (IOC mode) | Check filled volume |
| 10004 | REQUOTE | Price moved (instant execution) | Refresh prices, retry |
| 10014 | INVALID_VOLUME | Below min, above max, wrong step | Use NormalizeLots() |
| 10015 | INVALID_PRICE | Wrong digits, zero for pending | NormalizeDouble to SYMBOL_DIGITS |
| 10016 | INVALID_STOPS | SL/TP too close to market price | Check SYMBOL_TRADE_STOPS_LEVEL |
| 10019 | NO_MONEY | Insufficient margin | Reduce volume or skip |
| 10030 | INVALID_FILL | Wrong filling type | SetTypeFillingBySymbol() |
| 10029 | FROZEN | Price within freeze level of SL/TP | Cannot modify — wait |
| 10024 | TOO_MANY_REQUESTS | Rate limited by broker | Add delay between requests |
| 10040 | LIMIT_POSITIONS | Max positions reached | Close existing first |

---

## 4. OnTick() / OnTimer() Execution Model

### 4.1 Threading: Single-Threaded

MQL5 is **single-threaded per EA**. `OnTick()` and `OnTimer()` NEVER execute simultaneously. Events are queued and processed sequentially.

### 4.2 Tick Queuing

While `OnTick()` executes, incoming ticks are accumulated. When `OnTick()` returns, **only the LATEST tick** fires the next `OnTick()`. Intermediate ticks are lost.

**Implication**: Keep `OnTick()` fast. Do heavy work only on new bars.

### 4.3 Strategy Tester Tick Generation

| Mode | OnTick Calls | Speed | Accuracy |
|------|-------------|-------|----------|
| Every tick (real) | Per real historical tick | Slowest | Best |
| Every tick (generated) | ~3-12 per bar | Slow | Good |
| OHLC 1 minute | 4 per M1 bar (O→H→L→C or O→L→H→C) | Medium | Moderate |
| Open prices only | 1 per bar on EA's TF | Fastest | Low |

### 4.4 New Bar Detection — The Reliable Method

```mql5
datetime g_lastBarTime = 0;

bool IsNewBar()
{
    datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
    if(currentBarTime == 0) return false; // Data not ready
    if(currentBarTime != g_lastBarTime)
    {
        g_lastBarTime = currentBarTime;
        return true;
    }
    return false;
}
```

**Why NOT `Bars()`**: Bar count can stay the same when old bars are pruned and new ones added simultaneously.

### 4.5 OnTimer Resolution

- `EventSetTimer(1)` → ~1 second (±16ms on Windows)
- `EventSetMillisecondTimer(100)` → ~100ms (±16ms)
- In Tester: fires based on simulated time, not real time

---

## 5. Netting vs Hedging — Code Differences

### 5.1 Detection

```mql5
ENUM_ACCOUNT_MARGIN_MODE mode =
    (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
bool isHedging = (mode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
```

### 5.2 Critical Differences

| Operation | Hedging | Netting |
|-----------|---------|---------|
| BUY + SELL same symbol | Two separate positions | Positions net out |
| Close specific position | `trade.PositionClose(ticket)` | N/A (one position per symbol) |
| Multiple EA same symbol | Works (filter by magic) | Dangerous (EAs interfere) |
| Position selection | `PositionSelectByTicket(ticket)` | `PositionSelect(symbol)` |
| Magic number relevance | Critical — each position tagged | Less useful — last EA overwrites |

### 5.3 Safe Position Enumeration (Hedging)

```mql5
bool HasOpenPosition(string symbol, long magic)
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0) continue;
        if(PositionGetString(POSITION_SYMBOL) != symbol) continue;
        if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
        return true;
    }
    return false;
}
```

---

## 6. Chart Objects — Correct Implementation

### 6.1 ObjectFind Return Value (BUG FIX)

```mql5
// CORRECT:
if(ObjectFind(0, name) >= 0) { /* object exists */ }
if(ObjectFind(0, name) < 0)  { /* object does NOT exist */ }

// WRONG (old V2 bug):
if(!ObjectFind(0, name))      // This is TRUE when object is in main window (returns 0)!
if(ObjectFind(0, name) == 0)  // This only matches main window, misses subwindows
```

`ObjectFind()` returns: subwindow index (0+) if found, **-1** if not found.

### 6.2 Drawing a BPR Rectangle

```mql5
void DrawBPRBox(string name, datetime time1, datetime time2,
                double price1, double price2, color clr, bool filled)
{
    if(ObjectFind(0, name) >= 0)
        ObjectDelete(0, name);

    if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, time1, price1, time2, price2))
    {
        LogMessage("Failed to create object: " + name + " error: " + IntegerToString(GetLastError()));
        return;
    }

    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, name, OBJPROP_FILL, filled);
    ObjectSetInteger(0, name, OBJPROP_BACK, true);      // Behind price
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);     // Hide from object list
    ObjectSetInteger(0, name, OBJPROP_ZORDER, 0);
}
```

### 6.3 Cleanup

```mql5
void OnDeinit(const int reason)
{
    ObjectsDeleteAll(0, "BPR_");  // Delete all objects with prefix
    ObjectsDeleteAll(0, "FVG_");
    ChartRedraw(0);
}
```

---

## 7. TimeGMT — Tester vs Live

| Function | Live Trading | Strategy Tester |
|----------|-------------|-----------------|
| `TimeGMT()` | True UTC from local PC clock | **SAME AS `TimeCurrent()`** (broken!) |
| `TimeCurrent()` | Last tick's server time | Simulated server time |
| `TimeTradeServer()` | Estimated current server time (interpolated) | Same as `TimeCurrent()` |
| `TimeLocal()` | Local PC time | **SAME AS `TimeCurrent()`** (broken!) |

### 7.1 Robust Session Filter (Works in Both)

```mql5
datetime GetGMTTime()
{
    if(MQLInfoInteger(MQL_TESTER))
        return TimeCurrent() - GetBrokerGMTOffset() * 3600;
    else
        return TimeGMT();
}

int GetBrokerGMTOffset()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    // US DST: second Sunday March → first Sunday November
    bool isDST = IsDSTActive(dt.year, dt.mon, dt.day);
    return isDST ? Inp_BrokerGMTOffsetSummer : Inp_BrokerGMTOffsetWinter;
}

bool IsBlockedSession(int blockStartHourUTC, int blockEndHourUTC)
{
    MqlDateTime gmtStruct;
    TimeToStruct(GetGMTTime(), gmtStruct);
    int h = gmtStruct.hour;

    if(blockStartHourUTC < blockEndHourUTC)
        return (h >= blockStartHourUTC && h < blockEndHourUTC);
    else // wraps midnight
        return (h >= blockStartHourUTC || h < blockEndHourUTC);
}
```

---

## 8. Symbol Properties — Complete Checklist

**Query ALL of these in OnInit and verify they are sane:**

```mql5
// PRICE
double _point   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
int    _digits  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

// TRADING
double _tickValue    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
double _tickSize     = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
double _contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);

// VOLUME
double _volMin   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
double _volMax   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
double _volStep  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
double _volLimit = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_LIMIT); // 0=unlimited

// STOPS
long _stopsLevel  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
long _freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);

// EXECUTION
long _fillingMode = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
ENUM_SYMBOL_TRADE_EXECUTION _execMode =
    (ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_EXEMODE);
ENUM_SYMBOL_TRADE_MODE _tradeMode =
    (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);

// SPREAD
int  _spread      = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
bool _spreadFloat = (bool)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD_FLOAT);

// SWAP
double _swapLong  = SymbolInfoDouble(_Symbol, SYMBOL_SWAP_LONG);
double _swapShort = SymbolInfoDouble(_Symbol, SYMBOL_SWAP_SHORT);
int    _swap3Day  = (int)SymbolInfoInteger(_Symbol, SYMBOL_SWAP_ROLLOVER3DAYS);

// ACCOUNT
ENUM_ACCOUNT_MARGIN_MODE _marginMode =
    (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
long _leverage = AccountInfoInteger(ACCOUNT_LEVERAGE);
```

**Validation in OnInit:**
```mql5
if(_point <= 0 || _tickValue <= 0 || _tickSize <= 0 || _volMin <= 0 || _volStep <= 0)
{
    Print("CRITICAL: Invalid symbol properties — cannot trade safely");
    return INIT_FAILED;
}
if(_tradeMode != SYMBOL_TRADE_MODE_FULL)
{
    Print("WARNING: Trading mode is not FULL — mode: ", EnumToString(_tradeMode));
}
```

---

## 9. Logging — Where Output Goes

| Function | Live: Journal Tab | Live: Log File | Tester: Journal | Tester: Log |
|----------|-------------------|----------------|-----------------|-------------|
| `Print()` | Yes | Yes (`MQL5/Logs/YYYYMMDD.log`) | Yes | Yes |
| `PrintFormat()` | Yes | Yes | Yes | Yes |
| `Comment()` | Chart overlay | No | Chart overlay (visual mode) | No |
| `Alert()` | Dialog box | Yes | **Ignored** | No |

Log files are **UTF-16 encoded** and located at:
- Terminal logs: `.../MetaTrader 5/logs/YYYYMMDD.log`
- EA logs: `.../MQL5/Logs/YYYYMMDD.log`
- Tester agent logs: `.../Tester/Agent-127.0.0.1-PORT/logs/`

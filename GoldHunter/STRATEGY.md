# GoldHunter v15 — Strategy & Configuration

**Instrument:** XAUUSD (Gold)
**Broker:** GTC Global Trade (`XAUUSD.ecn`)
**Timeframe:** M5 (primary), M15/H1/H4/D1 (multi-TF analysis)
**Backtest Period:** Jan 2025 - Jan 2026
**Result:** +$1,012 on $10,000 (+10.1%), 41 trades, 43.9% WR

---

## Overview

GoldHunter is a multi-strategy EA combining 4 ICT/SMC-based strategies, each trading in its own time window. The strategies are complementary — they cover different sessions and market conditions so they don't interfere with each other.

### Session Schedule (New York Time)

```
19:00-00:00  Asian session — build Asian range
21:00-01:00  Strategy 3: Asian Mean Reversion (fade BB extremes)
02:00-05:00  Strategy 1: London Judas Swing (sweep Asian range)
03:00-04:00  Strategy 2: London Silver Bullet
07:00-10:00  Strategy 1: NY Judas Swing (sweep London range)
09:00+       Strategy 4: BPR Bot (M15 FVG overlap zones)
10:00-11:00  Strategy 2: NY AM Silver Bullet (primary SB window)
```

---

## Strategy 1: Judas Swing

**Concept:** Institutions sweep the Asian/London range to grab liquidity, then reverse. We trade the reversal.

**How it works:**
1. Build the **Asian range** (19:00-00:00 NY): track the high and low
2. Build the **London range** (02:00-07:00 NY): track the high and low
3. During London KZ (02:00-05:00 NY), look for price sweeping the Asian range
4. During NY KZ (07:00-10:00 NY), look for price sweeping the London range
5. A **sweep** = wick goes beyond the range high/low, but closes back inside
6. After the sweep, wait for a **Market Structure Shift (MSS)**: a displacement candle (body >= 1.5x ATR, body >= 60% of candle range) that breaks a recent swing high/low
7. Confirm there's an **FVG** (Fair Value Gap) formed during the displacement
8. Enter at market in the reversal direction

**SL:** Below/above the sweep extreme + $2 buffer
**TP:** SL distance x 2.0 (fixed 1:2 RR)

**Filters:**
- Range must be 0.3x - 2.0x Daily ATR (skip abnormal days)
- H4 EMA(20) vs EMA(50) trend must not oppose the trade
- Max 1 trade per killzone (London + NY = max 2/day)

**Trade distribution:** ~7 trades/year (very selective)

---

## Strategy 2: Silver Bullet

**Concept:** During ICT's Silver Bullet time windows, look for a liquidity sweep followed by displacement + FVG. This is the primary trade generator.

**How it works:**
1. Identify **liquidity levels**: nearest swing high (BSL) and swing low (SSL) from last 60 M5 bars, plus Asian/London range highs/lows
2. During the SB window, scan the last 6 bars for a **sweep**:
   - Bullish: wick below SSL, close back above it, sweep depth >= 0.25x ATR
   - Bearish: wick above BSL, close back below it, sweep depth >= 0.25x ATR
3. After the sweep, find a **displacement candle** (body >= 1.3x ATR, body >= 60% of range, correct direction)
4. Confirm an **FVG** exists in the displacement (gap >= 0.4x ATR)
5. Enter at market

**SB Windows (NY time):**
- London SB: 03:00-04:00 (secondary)
- NY AM SB: 10:00-11:00 (primary — this is where most gold trades happen)

**SL:** Below/above the sweep candle extreme + 0.5x ATR buffer
**TP:** SL distance x 2.0 (fixed 1:2 RR)

**Filters:**
- H4 EMA bias must match (only long if EMA20 > EMA50, etc.)
- Spread must be < $4.00
- Min SL distance: $5.00
- Max 1 trade per SB window

**Trade distribution:** ~17 trades/year (largest contributor)

---

## Strategy 3: Asian Mean Reversion

**Concept:** During the quiet Asian session, gold mean-reverts within Bollinger Bands. Fade extremes, target the middle band.

**How it works:**
1. During 21:00-01:00 UTC, check if price closed below the lower BB or above the upper BB
2. Confirm with RSI: oversold (< 20) for longs, overbought (> 80) for shorts
3. Confirm market is ranging: ADX(14) < 22
4. Confirm BB width is "normal": absolute width >= $8, relative width between 0.8x-1.3x of 50-period average
5. Confirm volatility isn't extreme: current ATR(M5) < 2x its 100-period average
6. Enter at market

**SL:** max(3.0x ATR, $7.00) — wide SL to survive Asian noise
**TP:** Middle Bollinger Band (SMA 20) — dynamic target

**Filters:**
- Skip rollover period (00:00-00:15 UTC)
- Max 3 MR trades per day
- Min 12 bars (1 hour) cooldown between entries
- Spread < $3.00
- Min TP distance: $5.00
- All open MR positions force-closed at 06:00 UTC (before London volatility)

**Trade distribution:** ~13 trades/year

---

## Strategy 4: BPR (Balanced Price Range)

**Concept:** When a bullish FVG and a bearish FVG overlap, they form a BPR — a zone of institutional interest. Price returning to this zone is a high-probability entry.

**How it works:**
1. On M15, detect FVGs from the last 50 bars (min size: 0.1x ATR)
2. Find overlapping bullish + bearish FVGs — the overlap is the BPR
3. BPR must be >= 0.15x ATR wide
4. Direction = direction of the most recent FVG (momentum side)
5. Wait for price to close inside the BPR zone with a rejection candle (close in direction of BPR)
6. Confirm H1 and M15 market structure align (HH/HL for bullish, LH/LL for bearish)
7. Enter at market

**SL:** Beyond the full FVG range + 5 points buffer
**TP:** SL distance x 2.0

**Filters:**
- No trading during Asian session (00:00-09:00 UTC)
- H1 structure must not be RANGE
- M15 structure must not oppose the BPR direction
- Min SL distance: $5.00
- FVG array is compacted daily to prevent overflow

**Trade distribution:** ~4 trades/year (very rare, highest quality)

---

## Risk Management

| Rule | Value |
|------|-------|
| Risk per trade | **2.0%** of equity |
| Max concurrent positions | **5** across all strategies |
| Daily loss limit | **5.0%** of equity — no new trades if hit |
| Weekly DD limit | **7.0%** of equity — no new trades if hit |
| Min SL distance | **$5.00** on all strategies |
| Min TP distance | **$5.00** on MR; RR-based on others |

### Position Sizing
- Dynamic: `lots = (equity * risk%) / (SL_distance / tick_size * tick_value)`
- Automatically scales with equity (compound growth)
- Floor at broker minimum lot, cap at broker maximum lot

---

## Best Configuration (v15)

```ini
; === GENERAL ===
Inp_Symbol              = XAUUSD.ecn
Inp_MagicNumber         = 250001
Inp_RiskPercent         = 2.0
Inp_MaxConcurrentPos    = 5
Inp_DailyLossLimit      = 5.0
Inp_WeeklyLossLimit     = 7.0

; === BROKER TIME (GTC Global Trade) ===
Inp_GMTOffsetWinter     = 2
Inp_GMTOffsetSummer     = 3

; === STRATEGY ENABLES ===
Inp_EnableJudas         = true
Inp_EnableSilverBullet  = true
Inp_EnableAsianMR       = true
Inp_EnableBPR           = true

; === JUDAS SWING ===
Inp_JS_RR               = 2.0       ; 1:2 risk/reward
Inp_JS_SLBuffer         = 2.0       ; $2 buffer beyond sweep extreme
Inp_JS_SwingLookback    = 5         ; 5 bars each side for swing detection
Inp_JS_DisplacementATR  = 1.5       ; displacement body >= 1.5x ATR
Inp_JS_MinRangeATR      = 0.3       ; min range = 30% of daily ATR
Inp_JS_MaxRangeATR      = 2.0       ; max range = 200% of daily ATR
Inp_JS_DayFilter        = false     ; trade all weekdays

; === SILVER BULLET ===
Inp_SB_RR               = 2.0       ; 1:2 risk/reward
Inp_SB_MinFVGATR        = 0.4       ; FVG must be >= 40% of ATR
Inp_SB_DisplacementATR  = 1.3       ; displacement body >= 1.3x ATR
Inp_SB_MinSweepATR      = 0.25      ; sweep must penetrate >= 25% of ATR
Inp_SB_SwingLookback    = 10        ; 10 bars each side for liquidity
Inp_SB_MaxSpread        = 4.0       ; max $4 spread
Inp_SB_ScanBars         = 6         ; scan last 6 bars for sweep

; === ASIAN MEAN REVERSION ===
Inp_MR_BBPeriod         = 20        ; Bollinger Band period
Inp_MR_BBDeviation      = 2.0       ; Bollinger Band std deviation
Inp_MR_RSIPeriod        = 7         ; fast RSI for extremes
Inp_MR_RSIOverbought    = 80        ; RSI > 80 = overbought
Inp_MR_RSIOversold      = 20        ; RSI < 20 = oversold
Inp_MR_MinBBWidth       = 8.0       ; min $8 BB width (skip squeezes)
Inp_MR_MaxTradesPerDay  = 3         ; max 3 MR entries per day
Inp_MR_CooldownBars     = 12        ; 1 hour between entries
Inp_MR_ADXPeriod        = 14        ; ADX period
Inp_MR_ADXMax           = 22        ; ADX must be < 22 (ranging)
Inp_MR_SL_ATRMult       = 3.0       ; SL = 3x ATR (minimum $7)
Inp_MR_MaxSpread        = 3.0       ; max $3 spread

; === BPR ===
Inp_BPR_RR              = 2.0       ; 1:2 risk/reward
Inp_BPR_SLBuffer        = 5         ; 5 points SL buffer
Inp_BPR_Lookback        = 50        ; scan last 50 M15 bars for FVGs
Inp_BPR_SwingN          = 4         ; 4 bars each side for structure
Inp_BPR_FVGTier         = 0         ; most permissive FVG filter

; === VISUALS ===
Inp_DrawObjects         = false     ; disable for backtesting
```

---

## Backtest Results (v15 Final)

| Metric | Value |
|--------|-------|
| Period | Jan 2025 - Jan 2026 |
| Starting Balance | $10,000 |
| Final Balance | **$11,012.28** |
| Net Profit | **+$1,012.28 (+10.1%)** |
| Total Trades | 41 |
| Win Rate | 43.9% (18 TP / 23 SL) |
| Risk/Reward | 1:2.0 |
| Model | Open Prices Only (M5) |
| Leverage | 1:500 |

### Trade Distribution by Strategy

| Strategy | Trades | Percentage |
|----------|--------|------------|
| Silver Bullet | 17 | 41% |
| Asian Mean Rev | 13 | 32% |
| Judas Swing | 7 | 17% |
| BPR | 4 | 10% |

### Edge Calculation

```
Expected Value per trade = (WR x RR) - (1 - WR)
                        = (0.439 x 2.0) - (0.561 x 1.0)
                        = 0.878 - 0.561
                        = +0.317R per trade

At 2% risk: 0.317 x 2% = +0.63% equity per trade
Over 41 trades: 0.63% x 41 = +25.9% theoretical
Actual: +10.1% (spread/slippage costs ~60% of theoretical edge)
```

---

## Optimization History

| Version | P/L | Trades | WR | Key Change |
|---------|-----|--------|----|------------|
| v1 | -$4,734 | 157 | 28% | Original — overtrading, tight SLs |
| v3 | -$930 | ~100 | 29% | Fixed sweep detection, BB filter, FVG array |
| v5 | -$266 | 28 | 36% | Balanced filter thresholds |
| v10 | -$124 | 28 | 39% | RR 2.0 (was 2.5), disabled trailing stop |
| v12 | +$712 | 41 | 44% | Relaxed SB filters, 1.5% risk, 4 max pos |
| **v15** | **+$1,012** | **41** | **44%** | **2% risk, 5 max pos (sweet spot)** |

### What Didn't Work

- **NY PM Silver Bullet (14:00-15:00):** Added 11 SB trades but WR crashed from 44% to 35%. PM moves are exhaustion, not displacement.
- **RR 1.5:** Identical SL/TP counts as RR 2.0 — on Model=1, trades either reach full TP or SL. Lower RR just earns less per win.
- **RR 2.5-3.0:** Too far for gold — many trades reversed before reaching TP.
- **3% risk:** Hit daily loss limits faster, blocking potential winners later in the day.
- **Trailing stop:** On Model=1 (open prices only), trails don't see intrabar movement. Converted potential TP trades into breakeven stops.
- **SB scan 8 bars (was 6):** Found "sweeps" too far from current price — stale signals.

### What Worked

- **Sweep depth filter (0.25x ATR):** Eliminated shallow/false sweeps
- **BB width filter ($8 min):** Prevented MR trades during squeeze
- **MR cooldown (12 bars):** Stopped repeat entries into same losing setup
- **FVG array compaction:** Fixed BPR getting 0 trades (array was filling up)
- **Wide MR SL (3x ATR, min $7):** Stopped getting chopped out by Asian noise
- **2% risk with 5 max pos:** Amplified edge without hitting loss limits

---

## Notes

- **Model=1 limitation:** These results use "Open Prices Only" mode, which completes in ~1 second but misses intrabar price action. Model=2 (every tick) would give more realistic results and potentially enable trailing stops.
- **Spread impact:** At ~$40/trade average spread cost, spread eats ~60% of theoretical edge. Lower-spread brokers or ECN accounts would significantly improve results.
- **Broker-specific:** GMT offsets (2/3) are for GTC Global Trade. Other brokers will need different values — the killzone timing is critical.

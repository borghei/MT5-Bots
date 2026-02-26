# GoldHunter — Multi-Strategy XAUUSD EA Research

## Architecture: 4 Strategies in 1 EA

Each strategy trades in its own time window with independent logic.
Combined target: **8-15% monthly**, 15-25% max DD.

---

## Strategy 1: Judas Swing (London + NY Killzones)

### Concept
Price sweeps the Asian/London range to grab liquidity, then reverses.

### Time Windows (New York local time)
- **London KZ:** 02:00-05:00 EST → sweeps Asian range (19:00-00:00 EST)
- **NY KZ:** 07:00-10:00 EST → sweeps London range (02:00-07:00 EST)
- NY model is PRIMARY for gold (USD-driven)

### Entry Sequence
1. Record Asian range (19:00-00:00 EST): track high/low of all M15 candles
2. Record London range (02:00-07:00 EST): track high/low
3. During killzone, detect **sweep**: wick beyond range H/L, close back inside
4. Wait for **Market Structure Shift (MSS)**: break of recent swing H/L with displacement
5. Identify **FVG** formed during displacement
6. Enter limit order at FVG boundary

### Sweep Detection
```
Bullish sweep: Low < asian_low AND Close > asian_low
Bearish sweep: High > asian_high AND Close < asian_high
```

### Confirmation: MSS + Displacement
- Displacement candle: body > 1.5x ATR(14), body > 60% of candle range
- MSS: closes beyond most recent swing H/L in reversal direction

### SL/TP
- SL: beyond sweep extreme + $2 buffer
- TP1: opposite side of range (min 1:2 RR)
- TP2: PDH/PDL

### Filters
- Day filter: Tuesday-Thursday only (skip Monday, Friday)
- Asian range size: 50-150% of 20-day average (skip if abnormal)
- HTF bias: H4 EMA(20) > EMA(50) for longs, vice versa
- No high-impact news during killzone
- Max 1 trade per killzone, max 2 per day

### Expected: 2-4 trades/week, 55-65% WR, 1:2-1:3 RR

---

## Strategy 2: Silver Bullet (NY AM Session)

### Concept
Liquidity sweep + displacement + FVG entry within strict 1-hour windows.

### Time Windows (New York local time)
- **London SB:** 03:00-04:00 (secondary for gold)
- **NY AM SB:** 10:00-11:00 (PRIMARY for gold — London/NY overlap)
- **NY PM SB:** 14:00-15:00 (skip for gold — weak)

### Entry Sequence
1. Mark liquidity levels: swing H/L, equal H/L, session H/L, PDH/PDL
2. Within SB window, detect **sweep** of a liquidity level
3. Wait for **displacement** (2-3 impulsive candles, body > ATR)
4. Identify **FVG** from displacement leg
5. Enter limit at FVG top (long) or bottom (short)
6. Must align with **Draw on Liquidity (DOL)** direction on H4

### DOL Filter
- H4 dealing range: identify premium (above 50%) vs discount (below 50%)
- Only long in discount, only short in premium
- DOL target must provide >= 2R

### SL/TP
- SL: beyond sweep candle extreme + buffer (ATR * 0.3)
- TP: nearest DOL target (opposing liquidity pool)
- Min RR: 1:2, preferred 1:3

### Filters
- Spread < $0.40 (400 points)
- FVG size >= ATR(14) * 0.5
- No news within 15 min
- Max 1 trade per SB window

### Expected: 3-5 trades/week, 55-70% WR, 1:2-1:4 RR

---

## Strategy 3: Asian Mean Reversion

### Concept
During quiet Asian hours, price mean-reverts within Bollinger Bands.

### Time Window
- **Entry:** 21:00-01:00 UTC (the quietest period)
- **No new trades after:** 02:00 UTC
- **Force close by:** 06:00 UTC (before London)
- **Skip:** 00:00-00:15 UTC (rollover, spreads spike)

### Entry Signal
```
LONG: Close < Lower BB(20,2.0) AND RSI(7) < 25 AND ADX(14) < 25
SHORT: Close > Upper BB(20,2.0) AND RSI(7) > 75 AND ADX(14) < 25
```

### SL/TP
- SL: ATR(14) * 2.0 from entry
- TP: Middle Bollinger Band (SMA 20) — close 50%, trail rest
- Alternative: 1.5:1 fixed RR

### Critical Filters (prevent trend-day losses)
1. ADX(14) < 25 (must be ranging)
2. BB width between 0.8x-1.3x of 50-period average (no squeeze, no expansion)
3. Previous NY session range < 1.5x Daily ATR (no momentum carryover)
4. NY close ratio: if NY closed in top/bottom 15% of range, only trade WITH that direction
5. Spread < 35 points ($0.35)
6. Volatility: current ATR(14,M5) < 2x its 100-period average
7. No China/Japan/Australia high-impact news within 60 min

### Position Sizing
- 1% risk per trade (high WR but negative skew — protect against large losses)
- Max 2 concurrent positions

### Expected: 5-10 trades/week, 65-75% WR, 0.8:1-1.5:1 RR, PF 1.4-1.8

---

## Strategy 4: BPR (existing bot, enhanced)

### Keep Current Logic
- Close-inside-zone + rejection candle entry
- HTF (H1) structure alignment
- Asia session block (00:00-09:00 UTC)
- Best params from optimizer: RR=2.5, SLBuffer=5, Lookback=50, SwingN=4, FVGTier=0

### Enhancements
- Add Order Block confluence filter (BPR must overlap with an OB)
- Add DOL filter from Silver Bullet
- Add Breaker Block detection (failed OBs flip to resistance/support)

### Expected: ~40 trades/year, 32% WR, 1:2.5 RR, PF 1.14

---

## Risk Management (Global)

| Rule | Value |
|------|-------|
| Risk per trade | 1-2% of equity |
| Daily loss limit | 3% → shut down ALL strategies |
| Weekly DD limit | 7% → halve all position sizes |
| Monthly DD limit | 15% → EA stops, manual review |
| Max concurrent positions | 3 (across all strategies) |
| No strategy > 30% of capital | Enforced via position sizing |

## Combined Expected Performance

| Metric | Conservative | Optimistic |
|--------|-------------|-----------|
| Monthly return | 8% | 15% |
| Max DD | 15% | 25% |
| Trades/month | 40-60 | 80-100 |
| Sharpe ratio | 0.8 | 1.5 |
| Win rate (blended) | 50% | 60% |

## Session Schedule (UTC)

```
19:00-00:00  Record Asian range
21:00-01:00  Strategy 3: Asian Mean Reversion ACTIVE
02:00-05:00  Strategy 1: London Judas Swing (sweep Asian range)
03:00-04:00  Strategy 2: London Silver Bullet
07:00-10:00  Strategy 1: NY Judas Swing (sweep London range)
09:00-24:00  Strategy 4: BPR Bot ACTIVE
10:00-11:00  Strategy 2: NY AM Silver Bullet (PRIMARY)
```

No overlapping entries — each strategy has its own window.

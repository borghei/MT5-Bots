# BPR Bot - Research Summary & Master Plan (Phase 0)

*Updated: 2026-02-25 — Deep research pass: every detail that can cost money*

---

## 0. Environment & Broker Discovery

### 0.1 Local MT5 Installation

MT5 installed via **official MetaQuotes Wine 10.0 bundle** (Rosetta 2 on Apple Silicon):

| Component | macOS Path | Wine Path |
|-----------|-----------|-----------|
| App bundle | `/Applications/MetaTrader 5.app` (v5.0.5260) | — |
| Wine binary | `.../SharedSupport/wine/bin/wine64` | — |
| Wine prefix | `~/Library/Application Support/net.metaquotes.wine.metatrader5/` | — |
| terminal64.exe | `...drive_c/Program Files/MetaTrader 5/terminal64.exe` | `C:\Program Files\MetaTrader 5\terminal64.exe` |
| metaeditor64.exe | same parent | `C:\Program Files\MetaTrader 5\metaeditor64.exe` |
| MQL5 root | `.../MetaTrader 5/MQL5/` | `C:\...\MQL5\` |
| Experts | `.../MQL5/Experts/` | `C:\...\MQL5\Experts\` |
| Include | `.../MQL5/Include/` (has Trade/Trade.mqh) | `C:\...\MQL5\Include\` |
| Tester presets | `.../MQL5/Profiles/Tester/` | `C:\...\MQL5\Profiles\Tester\` |
| Tester dir | `.../MetaTrader 5/Tester/` (empty) | `C:\...\Tester\` |
| Config dir | `.../MetaTrader 5/config/` | `C:\...\config\` |
| Logs | `.../MetaTrader 5/logs/` | `C:\...\logs\` |
| Terminal data | `...drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/D0E8209F77C8CF37AD8BF550E51FF075/` | — |

Wine drive mapping: `C:` → `drive_c/`, `Z:` → `/` (macOS root). Use `winepath -w` / `winepath -u` to convert.

### 0.2 Broker: GTC Global Trade

| Detail | Value |
|--------|-------|
| Portal | mygtcportal.com / gtcfx.com |
| MT5 server | `GTCGlobalTrade-Server` |
| Login | `5935483` |
| Account types | Standard (1:2000), Pro (1:2000), ECN (1:500) |
| Likely account mode | **Hedging** (most retail forex; must confirm) |
| Likely GMT offset | **GMT+2 winter / GMT+3 summer** (EET/EEST standard; must confirm) |
| Regulation | FCA + ASIC (tier-1), VFSC + FSC (tier-3 offshore) |
| Caution | Mixed withdrawal reviews for large amounts |

### 0.3 Diagnostic Script Required (Phase 0.5)

A diagnostic MQL5 script must run once on the live server to get definitive values:

```
1. ACCOUNT_MARGIN_MODE             → hedging or netting?
2. TimeCurrent() - TimeGMT()       → server GMT offset (but see TimeGMT caveats below)
3. All symbols containing XAU/BTC  → exact naming (XAUUSD? XAUUSDm? GOLD?)
4. SYMBOL_FILLING_MODE per symbol  → FOK, IOC, or both?
5. SYMBOL_TRADE_EXEMODE            → instant, market, exchange, request?
6. SYMBOL_VOLUME_MIN/MAX/STEP      → lot constraints per symbol
7. SYMBOL_TRADE_TICK_VALUE/SIZE    → for position sizing formula
8. SYMBOL_POINT / SYMBOL_DIGITS   → price precision per symbol
9. SYMBOL_TRADE_CONTRACT_SIZE      → units per lot (100 oz for gold? 1 BTC?)
10. SYMBOL_TRADE_STOPS_LEVEL       → minimum SL/TP distance in points
11. SYMBOL_TRADE_FREEZE_LEVEL      → modification freeze zone
12. SYMBOL_SPREAD (current)        → typical spread
13. SYMBOL_SWAP_LONG/SHORT         → overnight costs
14. SYMBOL_SWAP_ROLLOVER3DAYS      → triple-swap day
```

---

## 1. Strategy: Fair Value Gaps (FVGs) — Precise Definitions

### 1.1 Candle Ordering (Source of Most Bugs)

**Chronological order (oldest → newest on chart): Candle 1 → Candle 2 → Candle 3**

In MQL5 with `ArraySetAsSeries(rates, true)` (bar 0 = current):
- Candle 1 (oldest) = `rates[i+2]` — highest bar index
- Candle 2 (middle, displacement) = `rates[i+1]`
- Candle 3 (newest) = `rates[i]` — lowest bar index

**This is the #1 source of off-by-one errors.** When scanning bar-by-bar, `i` is the newest candle, `i+2` is the oldest.

### 1.2 Bullish FVG — Exact Definition

```
Conditions: Low[candle3] > High[candle1]           — gap exists
            AND Close[candle2] > High[candle1]     — close confirms direction

Series:     Low[i] > High[i+2]  AND  Close[i+1] > High[i+2]
Non-series: Low[i] > High[i-2]  AND  Close[i-1] > High[i-2]

Zone:       Bottom = High[candle1] = High[i+2]
            Top    = Low[candle3]  = Low[i]

Meaning:    Price surged upward so fast that candles 1 and 3 wicks don't overlap.
            The gap between them is where price was never traded.
            The close-confirmation ensures the middle candle (displacement) confirms intent.
            Expected to act as SUPPORT on retracement.
```

### 1.3 Bearish FVG — Exact Definition

```
Conditions: High[candle3] < Low[candle1]           — gap exists
            AND Close[candle2] < Low[candle1]      — close confirms direction

Series:     High[i] < Low[i+2]  AND  Close[i+1] < Low[i+2]
Non-series: High[i] < Low[i-2]  AND  Close[i-1] < Low[i-2]

Zone:       Top    = Low[candle1]  = Low[i+2]
            Bottom = High[candle3] = High[i]

Meaning:    Price dropped so fast that candles 1 and 3 wicks don't overlap.
            The close-confirmation ensures the middle candle confirms intent.
            Expected to act as RESISTANCE on retracement.
```

### 1.4 Zone Boundaries Use WICKS, Not Bodies

The FVG zone is defined by the **High and Low** (wick extremes), NOT Open/Close (body edges). Using body prices is a common algorithmic mistake that produces incorrect zones.

### 1.5 Middle Candle (Candle 2) Requirements

The middle candle **does NOT define the zone boundaries** — those are strictly from candles 1 and 3. However, the middle candle's character determines FVG quality:

- **High quality**: Large body (displacement candle), strong directional intent
- **Low quality**: Small body, doji, or indecision — these FVGs are noise
- **ICT teaching**: The best FVGs come from displacement moves after liquidity sweeps
- **Algorithmic filter**: Use ATR-based minimum gap size to filter out weak FVGs (see §1.8)

### 1.6 FVG Lifecycle States

| State | Definition | Action |
|-------|-----------|--------|
| **Active** | Just formed, untouched by subsequent price | Valid zone, watching for retracement |
| **Tested** | Price wicks into the zone but closes outside | Zone CONFIRMED — wick = rejection |
| **Partially filled** | Price enters and retraces within the zone | Unfilled portion remains valid |
| **Fully mitigated** | Price traverses the entire zone | Zone exhausted |
| **Invalidated** | Price **closes** through the far side of the zone | Zone broken — can become IFVG |

**Critical distinction**: A wick through the zone that closes back inside = CONFIRMATION (tested). A candle body closing through = INVALIDATION. This matters for money.

### 1.7 Inversion FVGs (IFVGs)

When an FVG is invalidated (price closes through it with displacement), the zone can flip polarity:

- Violated **bullish FVG** → becomes **bearish IFVG** (was support, now resistance)
- Violated **bearish FVG** → becomes **bullish IFVG** (was resistance, now support)

**Requirements for valid IFVG:**
1. Original FVG must have been valid
2. Violation must be by a displacement candle (large body, strong intent)
3. The zone is traded from the opposite direction on retracement

**For our EA**: We do not trade IFVGs directly in Phase 1, but we should track FVG state to avoid using invalidated FVGs in BPR formation.

### 1.8 ATR-Based FVG Filter (from ICT_BPR Indicator)

The reference indicator uses a 4-tier filter based on ATR(14) of the trading timeframe:

| Tier | ATR Multiplier | Use Case |
|------|---------------|----------|
| Very Aggressive | 0.1x ATR | Maximum signals, most noise |
| Aggressive | 0.2x ATR | More signals, some noise |
| Defensive | 0.3x ATR | **Recommended for XAUUSD** |
| Very Defensive | 0.5x ATR | Minimum signals, least noise. **Recommended for BTCUSD** |

**Implementation**: `if(gap_size < ATR(14) * multiplier) → reject FVG`

### 1.9 Consequent Encroachment (CE) — The 50% Level

`CE = (FVG_high + FVG_low) / 2.0`

ICT teaches that the CE (midpoint) of an FVG is a higher-probability entry level than the zone edge because institutions often return to the midpoint to complete orders. This gives tighter stops and better R:R.

**For our EA**: The "better half" entry logic (enter in the half of the BPR closer to the entry direction) approximates CE. We can optionally add exact CE entry as a configurable option.

### 1.10 Common Algorithmic Mistakes in FVG Detection

| Mistake | Consequence | Prevention |
|---------|------------|------------|
| Off-by-one in bar indexing | Compares wrong candles → phantom/missed FVGs | Use clear variable names: `candle1_idx = i+2`, etc. |
| Using body prices instead of wick prices | Wrong zone boundaries → bad entries/SL | Always use `High[]`/`Low[]`, never `Open[]`/`Close[]` for zone bounds |
| Not filtering by minimum gap size | Hundreds of noise micro-FVGs | ATR-based filter (§1.8) |
| Including bar 0 (current forming bar) | Zone boundaries change tick-by-tick | Only scan from bar 1 (last completed) backward |
| Not checking temporal continuity | Weekend/holiday gaps create false FVGs | Verify candles 1-2-3 are consecutive sessions |
| Counting same FVG multiple times | Duplicate entries, array bloat | Track by candle 2's `datetime`, deduplicate |
| Unbounded FVG array growth | EA stops detecting after array fills | Fixed-size array with aging, daily cleanup |
| Not tracking FVG state | Trading against already-invalidated zones | Track: active → tested → mitigated → invalidated |

---

## 2. Strategy: Balanced Price Ranges (BPRs) — Precise Rules

### 2.1 BPR Formation — Exact Mathematics

Given:
- Bullish FVG zone: `[B_low, B_high]` where `B_low = High[candle1]`, `B_high = Low[candle3]`
- Bearish FVG zone: `[S_low, S_high]` where `S_low = High[candle3]`, `S_high = Low[candle1]`

**Overlap zone (BPR bounds):**
```
BPR_low  = max(B_low, S_low)
BPR_high = min(B_high, S_high)

BPR exists if and only if: BPR_high > BPR_low
```

**Full BPR bounds (for SL placement — PATCH 2):**
```
full_low  = min(B_low, S_low)     ← lowest point of either FVG
full_high = max(B_high, S_high)   ← highest point of either FVG
```

### 2.2 BPR Direction — Definitive Answer

**The SECOND (most recent) FVG determines direction.** Cross-referenced across FluxCharts, FXOpen, WritoFinance, SmartMoneyICT, and InnerCircleTrader.net:

- **Bullish BPR**: Bearish FVG forms first → price reverses → bullish FVG overlaps it → the bullish FVG (second/most recent) determines direction → **LONG entries**
- **Bearish BPR**: Bullish FVG forms first → price reverses → bearish FVG overlaps it → the bearish FVG (second/most recent) determines direction → **SHORT entries**

**Logic**: The most recent displacement represents where smart money is pushing price. The first FVG created the "problem" (imbalance), the second FVG creates the "response" (counter-imbalance). The overlap zone is where both forces balanced — and the most recent force wins.

**Note**: The old V2 code had this INVERTED (bearish FVG more recent = bullish BPR). This was wrong.

### 2.3 BPR Temporal Requirements

The two FVGs do NOT need to form on consecutive bars. However:

- **Closer in time = stronger BPR**. The concept requires "aggressive move then aggressive reversal."
- **No authoritative maximum bar gap** from ICT. This is a tunable parameter.
- **Defaults**: 30 bars lookback for M15 (~7.5 hours), 20 bars for M5 (~1.5 hours)
- Both FVGs must be on the **same timeframe** (standard definition)

### 2.4 BPR Minimum Overlap Size

No authoritative source specifies a minimum. Recommendations:

| Instrument | Minimum BPR Width |
|-----------|-------------------|
| XAUUSD | Max of: 1.0 point ($1.00) or 0.25x ATR(14) on M15 |
| BTCUSD | Max of: 50.0 points ($50) or 0.25x ATR(14) on M15 |
| EURUSD | Max of: 3 pips or 0.25x ATR(14) on M15 |

### 2.5 BPR Entry Mechanics

1. **Wait for retracement** — do NOT enter on the candle that creates the BPR
2. **Entry level**: Previous completed bar's close within the BPR zone
3. **Better entry**: CE level (50% of BPR zone) — `(BPR_high + BPR_low) / 2`
4. **Market order** (not limit) — for simplicity in Phase 1
5. **Direction must match market structure** (see §3)

### 2.6 BPR Invalidation

- **Close-based** (recommended): BPR invalidated when a candle **closes** beyond the zone in the opposing direction
- For bullish BPR: invalidated when close < BPR_low
- For bearish BPR: invalidated when close > BPR_high
- **Wick-through + close-inside = zone CONFIRMED** (not invalidated)
- Use previous bar's close (not current tick) for consistency with new-bar-only logic

### 2.7 The Three Non-Negotiable Patches

| Patch | Rule | Implementation |
|-------|------|----------------|
| **PATCH 1** | One trade per BPR | Set `bpr.used = true` immediately on `ExecuteTrade()`. Check `!bpr.used` in `CheckEntry()`. |
| **PATCH 2** | SL at BPR extremes | For LONG: `SL = full_low - buffer`. For SHORT: `SL = full_high + buffer`. `full_low`/`full_high` = extremes of BOTH FVGs, not just overlap. |
| **PATCH 3** | Daily expiry | Store `bpr.formed_date`. On each new bar, expire BPRs where `GetDayStart(current_time) > GetDayStart(formed_date)`. |

### 2.8 BPR with Confluence (Higher Probability Setups)

These increase probability but are optional for Phase 1:

- **BPR + Order Block overlap** → significantly stronger zone
- **BPR in correct premium/discount zone** → bullish BPR in discount (below 50% of range), bearish in premium
- **BPR + liquidity sweep** → best setups come after stop hunts
- **BPR formed by displacement candles** → both FVGs should come from strong moves, not weak doji candles

---

## 3. Market Structure — Precise Classification

### 3.1 Swing Detection Algorithm

```
isSwingHigh(bar_index, lookback_N):
    for j = 1 to N:
        if High[bar_index] <= High[bar_index - j]: return false  // left side
        if High[bar_index] <= High[bar_index + j]: return false  // right side
    return true

isSwingLow(bar_index, lookback_N):
    for j = 1 to N:
        if Low[bar_index] >= Low[bar_index - j]: return false
        if Low[bar_index] >= Low[bar_index + j]: return false
    return true
```

**Lookback N**: Bars on each side. `N=5` for reliable structure, `N=3` for responsive.

**Lag**: Swing points are only confirmed after N right-side bars form. With N=5, there's a 5-bar lag.

**Minimum data**: Need at least `2*N + 1` bars to detect one swing point. Need 3-4 swing points (2 highs + 2 lows) for reliable classification.

### 3.2 Structure Classification

| Pattern | Classification | Trading Direction |
|---------|---------------|-------------------|
| HH + HL (Higher High + Higher Low) | **Bullish** | Longs only |
| LH + LL (Lower High + Lower Low) | **Bearish** | Shorts only |
| Mixed (HH+LL or LH+HL) | **Range** | No trades (or range strategies) |

### 3.3 Multi-Timeframe Alignment

- **HTF** (default: H1) determines overall bias
- **Entry TF** (default: M15) for FVG/BPR detection and entry
- Ratio: ~4:1 between timeframes
- **Rule**: Only take entry-TF signals that align with HTF structure
- If HTF = Range → skip all trades

### 3.4 Break of Structure (BOS) and Change of Character (CHoCH)

| Event | Meaning | Implication |
|-------|---------|-------------|
| **BOS** (Break of Structure) | Price breaks last swing in trend direction (e.g., breaks swing high in uptrend) | Trend continuation — keep trading in trend direction |
| **CHoCH** (Change of Character) | Price breaks last swing AGAINST trend (e.g., breaks swing low in uptrend) | Potential reversal — stop opening new trades until new structure confirms |

---

## 4. Session Filtering — Precise Hours and Rules

### 4.1 Session Hours (UTC/GMT)

| Session | UTC Start | UTC End | Characteristic |
|---------|-----------|---------|----------------|
| Sydney | 21:00 | 06:00 | Low volume |
| Tokyo (Asia) | 23:00 | 08:00 | Accumulation, range-bound |
| London | 08:00 | 17:00 | Highest volume, manipulation |
| New York | 13:00 | 22:00 | Distribution, high volume |
| London+NY overlap | 13:00 | 17:00 | **Best for entries** — most volatile |

**ICT Kill Zones** (highest probability entry windows):
- London Kill Zone: **08:00-12:00 UTC**
- NY Kill Zone: **13:00-17:00 UTC**
- ICT Silver Bullet: **14:00-15:00 UTC** and **18:00-19:00 UTC**

### 4.2 Session Filter for XAUUSD (Gold)

Gold is HIGHLY session-dependent:
- **Asia (22:00-07:00 UTC)**: Range-bound, wider spreads, low-quality FVGs. **Block new entries.**
- **London open (07:00-08:00 UTC)**: Classic "Judas swing" — stop hunt of Asia range, then reversal. High-quality BPR formations after the manipulation.
- **London+NY overlap (13:00-17:00 UTC)**: Best period. Tightest spreads, highest volume. **Preferred entry window.**
- **NY PM (17:00-22:00 UTC)**: Declining volume. Some valid setups but lower probability.

### 4.3 Session Filter for BTCUSD (Crypto)

BTC trades 24/7 but institutional activity follows traditional hours:
- **London+NY overlap still most volatile** for BTC
- Asia filter is less critical — BTC can have valid moves in Asia
- **Consider**: Volume-based quiet period detection instead of pure time-based filter
- **Must account for**: Broker maintenance windows (typically Saturday morning, 30min-2hrs)
- **Weekend**: Lower liquidity, wider spreads, consider reducing position size or blocking entries

### 4.4 Time Handling — The Critical Detail

**`TimeGMT()` is BROKEN in Strategy Tester** — returns same value as `TimeCurrent()` (server time).

**Solution**: Use server time with configurable broker GMT offset:

```mql5
input int Inp_BrokerGMTOffsetWinter = 2;  // Most brokers: GMT+2 winter
input int Inp_BrokerGMTOffsetSummer = 3;  // Most brokers: GMT+3 summer (DST)

datetime GetGMTTime()
{
    if(MQLInfoInteger(MQL_TESTER))
        return TimeCurrent() - GetBrokerGMTOffset() * 3600;
    else
        return TimeGMT();  // From local PC clock in live
}
```

**DST transitions**: Most brokers follow EU DST (second Sunday of March → GMT+3, last Sunday of October → GMT+2). The EA must handle this automatically.

---

## 5. XAUUSD (Gold) — Critical Trading Details

### 5.1 Price Mechanics

| Property | Typical Value | Note |
|----------|---------------|------|
| Contract size | 100 troy ounces per lot | Confirm via `SYMBOL_TRADE_CONTRACT_SIZE` |
| Digits | 2 (some brokers: 3) | `SYMBOL_DIGITS` — changes all point calculations |
| Point | 0.01 (2-digit) or 0.001 (3-digit) | `SYMBOL_POINT` |
| Tick size | Usually = Point | `SYMBOL_TRADE_TICK_SIZE` |
| Tick value | $1.00 per lot per tick (2-digit) | `SYMBOL_TRADE_TICK_VALUE` |
| Volume min | 0.01 lots | `SYMBOL_VOLUME_MIN` |
| Volume step | 0.01 lots | `SYMBOL_VOLUME_STEP` |

**Position sizing example** (see full formula in MQL5_TECHNICAL_REFERENCE.md):
- Equity $10,000, Risk 2% ($200), SL distance = $5.00 (500 points on 2-digit)
- SL value per lot = 500 ticks × $1.00/tick = $500
- Lots = $200 / $500 = **0.40 lots**
- Verification: 0.40 lots × 100 oz × $5.00/oz = $200 loss ✓

### 5.2 Spread Ranges

| Condition | Typical Spread |
|-----------|---------------|
| London+NY overlap | $0.15-$0.30 (15-30 points) |
| Normal London/NY | $0.15-$0.30 |
| Asia session | $0.30-$0.80 (wider!) |
| FOMC/NFP/CPI | $1.00-$5.00+ (spikes!) |

### 5.3 Gold-Specific Risks

- **News volatility**: Gold can move $50-$100 in minutes after FOMC. FVGs during news may be valid but entries carry massive slippage risk.
- **London open manipulation**: Classic stop hunt of Asia range. FVGs formed during this manipulation are HIGH quality — but only after the manipulation completes.
- **Point value is high**: $1.00 per point per lot means a 100-point SL on 1 lot = $100 risk. Position sizing precision is critical.
- **DXY correlation weakened**: In 2024-2026, gold and DXY have shown simultaneous strength during risk-off events. Do NOT assume inverse correlation.

### 5.4 FVG Considerations for Gold

- **Typical M15 FVG size** (London/NY session): $2-$8 (200-800 points on 2-digit)
- **ATR(14) M15 typical**: ~$5-$15 depending on volatility regime
- **Recommended FVG filter**: Defensive (0.3x ATR) — filters noise without missing valid setups
- **FVGs > 2x ATR**: Likely news-driven — treat with caution, may not behave normally

---

## 6. BTCUSD (Bitcoin) — Critical Trading Details

### 6.1 Price Mechanics

| Property | Typical Value | Note |
|----------|---------------|------|
| Contract size | 1 BTC per lot (VARIES by broker!) | MUST confirm — some use 10 or 0.1 |
| Digits | 2 (usually) | |
| Point | 0.01 | |
| Tick value | $0.01 per lot per tick (if contract = 1 BTC) | VARIES by broker |
| Volume min | 0.01 lots | |
| Volume step | 0.01 lots | |

**WARNING**: BTCUSD contract specifications vary ENORMOUSLY between brokers. Never hardcode — always query dynamically.

### 6.2 BTC-Specific Risks

| Risk | Detail | Mitigation |
|------|--------|------------|
| **Flash crashes** | Oct 2025: $19B liquidated in hours. Dec 2025: flash crash to $24K from $100K+ on Binance. | Max drawdown limits, position size caps, circuit-breaker logic |
| **Spread widening** | Order book depth can shrink >90% during stress. Spreads from $5 to $200+. | Check spread before entry; reject if > 2x normal spread |
| **Leverage danger** | 1:2000 on BTC = 0.05% move liquidates. | Cap effective leverage at 5x-10x. 1:2000 is suicidal for BTC. |
| **Swap costs** | ~20% annual. At $100K BTC, 1 lot = ~$55/night. Triple Wednesday = ~$165. | Short-term trades only. Close before swap cutoff for overnight. |
| **24/7 market** | Maintenance windows exist. Lower weekend liquidity. | Detect maintenance (no ticks), reduce weekend position size |

### 6.3 Leverage Recommendation for BTCUSD

| Risk Profile | Effective Leverage | Risk Per Trade |
|-------------|-------------------|----------------|
| Backtest | 5x-10x | 0.5-1% |
| Medium (live) | 3x-5x | 1-2% |
| Aggressive (live) | 5x-10x | 2-3% |

**Never use full 1:2000 leverage on BTC.** A 2% adverse move at 2000:1 leverage = 40x account equity = instant liquidation.

---

## 7. Analysis of Previous Implementations

### 7.1 Old V2 (BPR_Bot_V2.mq5) — 10 Critical Bugs

| # | Bug | How It Costs Money |
|---|-----|-------------------|
| 1 | FVG arrays unbounded (cap at 100) | Stops detecting BPRs after ~100 FVGs → misses all trades |
| 2 | Default risk 10% per trade | Blows account on 3-4 consecutive losses |
| 3 | Session uses `TimeCurrent()` not UTC | Enters during wrong hours → low-quality trades in Asia |
| 4 | `ObjectFind` return value inverted | Visual debugging broken → can't diagnose issues |
| 5 | BPR direction inverted vs ICT convention | Enters LONG when should SHORT and vice versa |
| 6 | Tick value cached in OnInit | Stale for cross-currency → wrong position sizes |
| 7 | `Inp_CleanBPROnly` never implemented | Feature gap — no clean BPR filter |
| 8 | `OnTester()` always returns 100 | Genetic optimizer gets no useful fitness signal |
| 9 | JSON filename loses extension | Can't find log files → debugging blind |
| 10 | No OnDeinit cleanup | Ghost objects on chart → visual confusion |

### 7.2 ICT_BPR.mq5 Indicator — Valuable Reference

This indicator (at `~/Desktop/All/BPR/V2/ICT_BPR.mq5`, 630 lines) has the cleanest reference implementation:
- ✅ Correct FVG detection (`Low[i] > High[i-2]` for bullish, non-series arrays)
- ✅ ATR-based 4-tier filter
- ✅ FVG inversion detection
- ✅ Proper overlap check for BPR
- ✅ Validity period aging (configurable bars)
- ✅ Proximal/Distal zone naming
- ✅ Clean chart object management (`ObjectFind >= 0` — correct)

---

## 8. Autonomous Operation Pipeline

*Detailed in separate document: [AUTOMATION_PIPELINE.md](docs/AUTOMATION_PIPELINE.md)*

### 8.1 Summary

| Step | Tool | How |
|------|------|-----|
| Compile | MetaEditor CLI via Wine | Headless, no display needed, offline |
| Backtest | terminal64.exe via Wine with INI config | Window appears briefly, ShutdownTerminal=1 exits |
| Parse report | Python (HTML/XML parser) | Reports at configurable path |
| Analyze | Claude Code / Claude API | Read metrics, diagnose, propose changes |
| Iterate | Automated loop | Modify code/params → compile → backtest → parse → analyze → repeat |

### 8.2 Key Confirmed Facts

- MetaEditor CLI compilation **works via Wine** (confirmed by EA31337 project, mql-compile.nvim plugin)
- terminal64.exe `/config:` backtesting **works via Wine** (confirmed by multiple forum sources)
- **Terminal DOES show a window** (cannot be fully suppressed on macOS — not a blocker)
- `ShutdownTerminal=1` **exits cleanly** via Wine (confirmed in actual MT5 logs on this system)
- All `.set` and `.ini` files must be **UTF-16 LE with BOM** (confirmed from actual files on this system)
- MetaEditor CLI does NOT reliably return error exit codes — **check .ex5 file existence** instead
- `.log` files from compilation are **UTF-16 encoded**
- **MT5 does NOT auto-compile** when .mq5 files change on disk — only on startup
- **MT5 does NOT need to be running** for CLI compilation

---

## 9. Execution Plan (Phases)

### Phase 0.5 — Diagnostics & Wine Validation

1. Write `BPR_Diagnostic.mq5` script → prints all broker/symbol properties
2. Copy to `MQL5/Scripts/`, compile via Wine CLI
3. **Test Wine compilation** — verify .ex5 is produced, parse .log for errors
4. User runs diagnostic in MT5 → read Journal output
5. **Test Wine backtesting** — run a simple test with sample EA, verify report generated
6. Update broker config with confirmed values

### Phase 1 — Core EA Development

1. Write `BPR_Bot.mq5` with every function from architecture spec
2. FVG detection with ATR filter, lifecycle tracking
3. BPR detection with overlap math, all 3 patches
4. Market structure with multi-TF swing analysis
5. Position sizing with full `OrderCalcProfit` fallback
6. Session filter with DST-aware GMT offset
7. All CTrade error handling with retry logic
8. OnTester metric for optimizer fitness
9. Compile, verify zero warnings

### Phase 2 — Automation Scripts

1. `compile.sh` — Wine + MetaEditor wrapper with error detection
2. `backtest.sh` — Wine + terminal64 launcher with INI generation
3. `parse_report.py` — extract all metrics from HTML report
4. `generate_set.py` — JSON config → UTF-16 LE .set file
5. `deploy.sh` — copy EA + presets to MQL5 directory
6. End-to-end test of the full loop

### Phase 3 — Iterative Optimization

1. XAUUSD M15 backtest: 2024-2025 (2 years)
2. Analyze → diagnose → adjust → re-test
3. Target: Profit Factor > 1.5, Max DD < 20%, Win Rate > 45%
4. Walk-forward: train 6mo, validate 2mo, roll forward
5. Save best params as `.set` file
6. Repeat for BTCUSD

### Phase 4 — Live Deployment

1. Deploy with "medium" risk profile (2-3% per trade)
2. Monitor daily — read trade logs, analyze performance
3. After 2 weeks stable → option to switch to "aggressive" (5-10%)
4. Weekly parameter review, monthly re-optimization

### Phase 5 — ML Enhancement (Future)

1. Collect trade feature data (BPR width, TOD, structure strength, ATR, session)
2. Train classifier in Python → export ONNX
3. Embed in EA → filter low-probability setups
4. Compare with/without ML filter

---

## 10. Open Questions

| # | Question | Proposed Default | Impact |
|---|----------|-----------------|--------|
| 1 | **Wine CLI reliable?** | Must test in Phase 0.5 | Determines if loop is autonomous or semi-manual |
| 2 | **Same-bar opposing FVGs** | Skip — noise | Edge case for BPR direction |
| 3 | **BTCUSD session filter** | Same Asia block but with ATR override | May miss valid BTC setups |
| 4 | **DST handling** | Auto-detect from month/day | Could be wrong by 1 hour during transition weekend |
| 5 | **BPR max bar gap** | 30 bars (M15) | Too wide = stale matches, too narrow = missed BPRs |
| 6 | **FVG array size** | 200 per direction | Too small = missed FVGs, too large = slow scanning |
| 7 | **Spread filter** | Reject entry if spread > 2x average | May block valid entries during volatile periods |

---

*Phase 0 deep research complete. Ready for Phase 0.5 (Diagnostics & Wine Validation) upon approval.*

//+------------------------------------------------------------------+
//|                                                  GoldHunter.mq5  |
//|              Multi-Strategy XAUUSD EA — 4 Strategies in 1 Bot    |
//|         Judas Swing | Silver Bullet | Asian MR | BPR Enhanced    |
//+------------------------------------------------------------------+
#property copyright "GoldHunter"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

//--- General
input string               Inp_Symbol              = "XAUUSD.ecn";
input int                  Inp_MagicNumber         = 250001;
input double               Inp_RiskPercent         = 2.0;        // Risk per trade (% of equity)
input int                  Inp_MaxConcurrentPos    = 5;          // Max positions across all strategies
input double               Inp_DailyLossLimit      = 5.0;        // Daily loss limit (% of equity)
input double               Inp_WeeklyLossLimit     = 7.0;        // Weekly DD limit (%)

//--- Broker Time
input int                  Inp_GMTOffsetWinter     = 2;          // Broker GMT offset (winter)
input int                  Inp_GMTOffsetSummer     = 3;          // Broker GMT offset (summer DST)

//--- Strategy Enables
input bool                 Inp_EnableJudas         = true;       // Enable Judas Swing strategy
input bool                 Inp_EnableSilverBullet  = true;       // Enable Silver Bullet strategy
input bool                 Inp_EnableAsianMR       = true;       // Enable Asian Mean Reversion
input bool                 Inp_EnableBPR           = true;       // Enable BPR strategy

//--- Judas Swing Parameters
input double               Inp_JS_RR              = 2.0;         // Judas: Risk/Reward ratio
input double               Inp_JS_SLBuffer        = 2.0;         // Judas: SL buffer beyond sweep ($)
input int                  Inp_JS_SwingLookback    = 5;          // Judas: Bars each side for swing
input double               Inp_JS_DisplacementATR  = 1.5;        // Judas: Min displacement (x ATR)
input double               Inp_JS_MinRangeATR      = 0.3;        // Judas: Min range size (x Daily ATR)
input double               Inp_JS_MaxRangeATR      = 2.0;        // Judas: Max range size (x Daily ATR)
input bool                 Inp_JS_DayFilter        = false;       // Judas: Day filter (Tue-Thu only)

//--- Silver Bullet Parameters
input double               Inp_SB_RR              = 2.0;         // SB: Risk/Reward ratio
input double               Inp_SB_MinFVGATR       = 0.4;         // SB: Min FVG size (x ATR)
input double               Inp_SB_DisplacementATR = 1.3;         // SB: Min displacement (x ATR)
input double               Inp_SB_MinSweepATR     = 0.25;        // SB: Min sweep penetration (x ATR)
input int                  Inp_SB_SwingLookback   = 10;          // SB: Swing lookback for liquidity
input double               Inp_SB_MaxSpread       = 4.0;         // SB: Max spread ($)
input int                  Inp_SB_ScanBars        = 6;           // SB: Max bars to scan for sweep

//--- Asian Mean Reversion Parameters
input int                  Inp_MR_BBPeriod        = 20;          // MR: Bollinger Band period
input double               Inp_MR_BBDeviation     = 2.0;         // MR: Bollinger Band deviation
input int                  Inp_MR_RSIPeriod       = 7;           // MR: RSI period
input int                  Inp_MR_RSIOverbought   = 80;          // MR: RSI overbought level
input int                  Inp_MR_RSIOversold     = 20;          // MR: RSI oversold level
input double               Inp_MR_MinBBWidth      = 8.0;         // MR: Min BB width ($) to trade
input int                  Inp_MR_MaxTradesPerDay = 3;           // MR: Max MR trades per day
input int                  Inp_MR_CooldownBars    = 12;          // MR: Min bars between MR entries
input int                  Inp_MR_ADXPeriod       = 14;          // MR: ADX period
input int                  Inp_MR_ADXMax          = 22;          // MR: Max ADX (must be ranging)
input double               Inp_MR_SL_ATRMult      = 3.0;         // MR: SL as ATR multiplier
input double               Inp_MR_MaxSpread       = 3.0;         // MR: Max spread ($)

//--- BPR Parameters
input double               Inp_BPR_RR             = 2.0;         // BPR: Risk/Reward ratio
input int                  Inp_BPR_SLBuffer       = 5;           // BPR: SL buffer (points)
input int                  Inp_BPR_Lookback       = 50;          // BPR: FVG lookback bars
input int                  Inp_BPR_SwingN         = 4;           // BPR: Swing lookback
input int                  Inp_BPR_FVGTier        = 0;           // BPR: ATR filter tier

//--- Visuals
input bool                 Inp_DrawObjects        = true;        // Draw chart objects
input color                Inp_BullColor          = clrLime;
input color                Inp_BearColor          = clrOrangeRed;

//+------------------------------------------------------------------+
//| ENUMS & CONSTANTS                                                 |
//+------------------------------------------------------------------+
enum MARKET_STRUCTURE { STRUCT_BULLISH, STRUCT_BEARISH, STRUCT_RANGE };
#define DIR_BULL  1
#define DIR_BEAR -1

//+------------------------------------------------------------------+
//| STRUCTURES                                                        |
//+------------------------------------------------------------------+
struct SessionRange
{
   double   high;
   double   low;
   datetime start_time;
   datetime end_time;
   bool     valid;
};

struct FVG
{
   datetime time;
   double   high_bound;
   double   low_bound;
   int      direction;
   bool     active;
   bool     bpr_checked;
   datetime day_date;
};

struct BPR
{
   double   high_bound;
   double   low_bound;
   double   full_high;
   double   full_low;
   int      direction;
   bool     active;
   bool     used;
   datetime formed_date;
   datetime left_time;
   datetime right_time;
   string   box_name;
};

struct LiquidityLevel
{
   double   price;
   int      type;        // 1=swing high, -1=swing low, 2=equal highs, -2=equal lows, 3=session H, -3=session L
   datetime time;
   bool     swept;
};

struct SweepEvent
{
   double   level_price;
   double   sweep_extreme;  // the wick that went beyond
   int      direction;       // 1=bullish sweep (swept lows), -1=bearish sweep (swept highs)
   datetime time;
};

//+------------------------------------------------------------------+
//| GLOBAL STATE                                                      |
//+------------------------------------------------------------------+
CTrade         g_trade;

//--- Indicator handles
int            g_atrHandle_M5     = INVALID_HANDLE;
int            g_atrHandle_M15    = INVALID_HANDLE;
int            g_atrHandle_H1     = INVALID_HANDLE;
int            g_atrHandle_D1     = INVALID_HANDLE;
int            g_bbHandle_M5      = INVALID_HANDLE;
int            g_rsiHandle_M5     = INVALID_HANDLE;
int            g_adxHandle_M5     = INVALID_HANDLE;
int            g_emaFast_H4       = INVALID_HANDLE;
int            g_emaSlow_H4       = INVALID_HANDLE;

//--- Session ranges
SessionRange   g_asianRange;
SessionRange   g_londonRange;

//--- Strategy state
bool           g_judasTradedLondon = false;
bool           g_judasTradedNY     = false;
bool           g_sbTradedLondon    = false;
bool           g_sbTradedNYAM      = false;
int            g_mrTradestoday     = 0;          // MR daily trade counter
datetime       g_mrLastEntryBar    = 0;          // MR cooldown: last entry bar time
datetime       g_lastBarTime       = 0;
datetime       g_lastBarTime_M5    = 0;
datetime       g_dailyResetDate    = 0;

//--- Daily PnL tracking
double         g_dailyStartEquity  = 0;
double         g_weeklyStartEquity = 0;
datetime       g_weekStartDate     = 0;

//--- BPR arrays (from existing bot)
FVG            g_fvgs[];
int            g_fvgCount          = 0;
BPR            g_bprs[];
int            g_bprCount          = 0;
int            g_bprIdCounter      = 0;
double         g_currentATR_M15    = 0;
MARKET_STRUCTURE g_htfStructure    = STRUCT_RANGE;
MARKET_STRUCTURE g_entryStructure  = STRUCT_RANGE;

//--- Symbol info
double         g_symPoint          = 0;
int            g_symDigits         = 0;
double         g_stopsLevel        = 0;   // Minimum distance for SL/TP from price

//+------------------------------------------------------------------+
//| HELPER: Get current UTC time from broker time                     |
//+------------------------------------------------------------------+
datetime GetUTCTime()
{
   datetime brokerTime = TimeCurrent();
   // Determine if DST is active (rough: April-October)
   MqlDateTime dt;
   TimeToStruct(brokerTime, dt);
   int offset = (dt.mon >= 4 && dt.mon <= 10) ? Inp_GMTOffsetSummer : Inp_GMTOffsetWinter;
   return brokerTime - offset * 3600;
}

//+------------------------------------------------------------------+
//| HELPER: Get New York time from broker time                        |
//+------------------------------------------------------------------+
int GetNYHour()
{
   datetime utc = GetUTCTime();
   MqlDateTime dt;
   TimeToStruct(utc, dt);
   // NY = UTC-5 (EST) or UTC-4 (EDT, March-November)
   bool isDST = (dt.mon > 3 && dt.mon < 11) ||
                (dt.mon == 3 && dt.day >= 8) ||  // approximate 2nd Sunday
                (dt.mon == 11 && dt.day < 7);     // approximate 1st Sunday
   int nyOffset = isDST ? -4 : -5;
   int nyHour = dt.hour + nyOffset;
   if(nyHour < 0) nyHour += 24;
   if(nyHour >= 24) nyHour -= 24;
   return nyHour;
}

int GetNYMinute()
{
   datetime utc = GetUTCTime();
   MqlDateTime dt;
   TimeToStruct(utc, dt);
   return dt.min;
}

int GetUTCHour()
{
   datetime utc = GetUTCTime();
   MqlDateTime dt;
   TimeToStruct(utc, dt);
   return dt.hour;
}

int GetDayOfWeek()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return dt.day_of_week; // 0=Sun, 1=Mon, ..., 5=Fri
}

//+------------------------------------------------------------------+
//| HELPER: Count open positions for this EA                          |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == Inp_Symbol)
         if(PositionGetInteger(POSITION_MAGIC) == Inp_MagicNumber)
            count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| HELPER: Calculate lot size from risk                              |
//+------------------------------------------------------------------+
double CalcLots(double slDistance)
{
   if(slDistance <= 0) return 0;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * Inp_RiskPercent / 100.0;

   double tickValue = SymbolInfoDouble(Inp_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(Inp_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickValue <= 0 || tickSize <= 0)
   {
      // Fallback
      double profit = 0;
      if(OrderCalcProfit(ORDER_TYPE_BUY, Inp_Symbol, 1.0,
                         SymbolInfoDouble(Inp_Symbol, SYMBOL_ASK),
                         SymbolInfoDouble(Inp_Symbol, SYMBOL_ASK) + tickSize, profit))
      {
         if(profit > 0) tickValue = profit;
      }
      if(tickValue <= 0) return 0;
   }

   double slTicks = slDistance / tickSize;
   double costPerLot = slTicks * tickValue;
   if(costPerLot <= 0) return 0;

   double lots = riskMoney / costPerLot;

   double minLot  = SymbolInfoDouble(Inp_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(Inp_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(Inp_Symbol, SYMBOL_VOLUME_STEP);

   lots = MathFloor(lots / stepLot) * stepLot;
   if(lots < minLot) return 0;
   if(lots > maxLot) lots = maxLot;

   return lots;
}

//+------------------------------------------------------------------+
//| HELPER: Check daily/weekly loss limits                            |
//+------------------------------------------------------------------+
bool IsLossLimitHit()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   // Daily loss check
   if(g_dailyStartEquity > 0)
   {
      double dailyLoss = (g_dailyStartEquity - equity) / g_dailyStartEquity * 100.0;
      if(dailyLoss >= Inp_DailyLossLimit)
         return true;
   }

   // Weekly loss check
   if(g_weeklyStartEquity > 0)
   {
      double weeklyLoss = (g_weeklyStartEquity - equity) / g_weeklyStartEquity * 100.0;
      if(weeklyLoss >= Inp_WeeklyLossLimit)
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| HELPER: New bar detection                                         |
//+------------------------------------------------------------------+
bool IsNewBar(ENUM_TIMEFRAMES tf)
{
   datetime t = iTime(Inp_Symbol, tf, 0);
   if(tf == PERIOD_M15)
   {
      if(t != g_lastBarTime) { g_lastBarTime = t; return true; }
   }
   else if(tf == PERIOD_M5)
   {
      if(t != g_lastBarTime_M5) { g_lastBarTime_M5 = t; return true; }
   }
   return false;
}

//+------------------------------------------------------------------+
//| HELPER: Detect swing high/low                                     |
//+------------------------------------------------------------------+
bool IsSwingHigh(const MqlRates &rates[], int idx, int lookback)
{
   for(int j = 1; j <= lookback; j++)
   {
      if(idx + j >= ArraySize(rates)) return false;
      if(idx - j < 0) return false;
      if(rates[idx].high <= rates[idx+j].high) return false;
      if(rates[idx].high <= rates[idx-j].high) return false;
   }
   return true;
}

bool IsSwingLow(const MqlRates &rates[], int idx, int lookback)
{
   for(int j = 1; j <= lookback; j++)
   {
      if(idx + j >= ArraySize(rates)) return false;
      if(idx - j < 0) return false;
      if(rates[idx].low >= rates[idx+j].low) return false;
      if(rates[idx].low >= rates[idx-j].low) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| HELPER: Get ATR value                                             |
//+------------------------------------------------------------------+
double GetATR(int handle)
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(handle, 0, 1, 1, buf) < 1) return 0;
   return buf[0];
}

//+------------------------------------------------------------------+
//| HELPER: Get indicator value                                       |
//+------------------------------------------------------------------+
double GetIndicator(int handle, int bufIdx, int shift)
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(handle, bufIdx, shift, 1, buf) < 1) return 0;
   return buf[0];
}

//+------------------------------------------------------------------+
//| HELPER: Draw arrow on chart                                       |
//+------------------------------------------------------------------+
void DrawArrow(string name, datetime time, double price, bool isBuy, color clr, string tooltip)
{
   if(!Inp_DrawObjects) return;
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_ARROW, 0, time, price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, isBuy ? 233 : 234);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 3);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
}

//+------------------------------------------------------------------+
//| HELPER: Draw horizontal line segment                              |
//+------------------------------------------------------------------+
void DrawHLine(string name, datetime t1, datetime t2, double price, color clr, ENUM_LINE_STYLE style)
{
   if(!Inp_DrawObjects) return;
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
}

//+------------------------------------------------------------------+
//| HELPER: Log message                                               |
//+------------------------------------------------------------------+
void LogMsg(string msg)
{
   Print("[GoldHunter] ", msg);
}

//+------------------------------------------------------------------+
//| HELPER: Validate SL/TP distances meet broker minimums             |
//+------------------------------------------------------------------+
bool ValidateStops(double entry, double sl, double tp)
{
   double minDist = MathMax(g_stopsLevel, 2.0);  // At least $2 for gold
   if(MathAbs(entry - sl) < minDist) return false;
   if(MathAbs(entry - tp) < minDist) return false;
   return true;
}

//+------------------------------------------------------------------+
//| INIT                                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   g_symPoint  = SymbolInfoDouble(Inp_Symbol, SYMBOL_POINT);
   g_symDigits = (int)SymbolInfoInteger(Inp_Symbol, SYMBOL_DIGITS);
   g_stopsLevel = SymbolInfoInteger(Inp_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * g_symPoint;
   if(g_stopsLevel < 1.0) g_stopsLevel = 1.0;  // Minimum $1 for gold

   g_trade.SetExpertMagicNumber(Inp_MagicNumber);
   g_trade.SetDeviationInPoints(5);
   g_trade.SetTypeFillingBySymbol(Inp_Symbol);

   // Create indicator handles
   g_atrHandle_M5  = iATR(Inp_Symbol, PERIOD_M5, 14);
   g_atrHandle_M15 = iATR(Inp_Symbol, PERIOD_M15, 14);
   g_atrHandle_H1  = iATR(Inp_Symbol, PERIOD_H1, 14);
   g_atrHandle_D1  = iATR(Inp_Symbol, PERIOD_D1, 14);
   g_bbHandle_M5   = iBands(Inp_Symbol, PERIOD_M5, Inp_MR_BBPeriod, 0, Inp_MR_BBDeviation, PRICE_CLOSE);
   g_rsiHandle_M5  = iRSI(Inp_Symbol, PERIOD_M5, Inp_MR_RSIPeriod, PRICE_CLOSE);
   g_adxHandle_M5  = iADX(Inp_Symbol, PERIOD_M5, Inp_MR_ADXPeriod);
   g_emaFast_H4    = iMA(Inp_Symbol, PERIOD_H4, 20, 0, MODE_EMA, PRICE_CLOSE);
   g_emaSlow_H4    = iMA(Inp_Symbol, PERIOD_H4, 50, 0, MODE_EMA, PRICE_CLOSE);

   if(g_atrHandle_M5 == INVALID_HANDLE || g_atrHandle_M15 == INVALID_HANDLE ||
      g_atrHandle_H1 == INVALID_HANDLE || g_atrHandle_D1 == INVALID_HANDLE ||
      g_bbHandle_M5 == INVALID_HANDLE || g_rsiHandle_M5 == INVALID_HANDLE ||
      g_adxHandle_M5 == INVALID_HANDLE || g_emaFast_H4 == INVALID_HANDLE ||
      g_emaSlow_H4 == INVALID_HANDLE)
   {
      LogMsg("ERROR: Failed to create indicator handles");
      return INIT_FAILED;
   }

   // Init arrays
   ArrayResize(g_fvgs, 200);
   ArrayResize(g_bprs, 50);
   g_fvgCount = 0;
   g_bprCount = 0;

   // Init session ranges
   g_asianRange.valid  = false;
   g_londonRange.valid = false;

   // Init equity tracking
   g_dailyStartEquity  = AccountInfoDouble(ACCOUNT_EQUITY);
   g_weeklyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   LogMsg("GoldHunter initialized. Strategies: " +
          (Inp_EnableJudas ? "Judas " : "") +
          (Inp_EnableSilverBullet ? "SB " : "") +
          (Inp_EnableAsianMR ? "MeanRev " : "") +
          (Inp_EnableBPR ? "BPR " : ""));

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| DEINIT                                                            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(g_atrHandle_M5);
   IndicatorRelease(g_atrHandle_M15);
   IndicatorRelease(g_atrHandle_H1);
   IndicatorRelease(g_atrHandle_D1);
   IndicatorRelease(g_bbHandle_M5);
   IndicatorRelease(g_rsiHandle_M5);
   IndicatorRelease(g_adxHandle_M5);
   IndicatorRelease(g_emaFast_H4);
   IndicatorRelease(g_emaSlow_H4);
}

//+------------------------------------------------------------------+
//| DAILY RESET                                                       |
//+------------------------------------------------------------------+
void DailyReset()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime today = StringToTime(IntegerToString(dt.year) + "." +
                                 IntegerToString(dt.mon) + "." +
                                 IntegerToString(dt.day));

   if(today != g_dailyResetDate)
   {
      g_dailyResetDate = today;
      g_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);

      // Reset daily flags
      g_judasTradedLondon = false;
      g_judasTradedNY     = false;
      g_sbTradedLondon    = false;
      g_sbTradedNYAM      = false;
      g_mrTradestoday     = 0;

      // Reset session ranges
      g_asianRange.valid  = false;
      g_asianRange.high   = -999999;
      g_asianRange.low    = 999999;
      g_londonRange.valid = false;
      g_londonRange.high  = -999999;
      g_londonRange.low   = 999999;

      // Reset weekly equity on Monday
      if(dt.day_of_week == 1)
      {
         g_weeklyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
         g_weekStartDate = today;
      }

      // Expire old BPRs
      for(int i = 0; i < g_bprCount; i++)
      {
         if(g_bprs[i].active && g_bprs[i].formed_date < today)
            g_bprs[i].active = false;
      }

      // Compact FVG array: remove inactive entries to free slots
      int writeIdx = 0;
      for(int i = 0; i < g_fvgCount; i++)
      {
         if(g_fvgs[i].active)
         {
            if(writeIdx != i) g_fvgs[writeIdx] = g_fvgs[i];
            writeIdx++;
         }
      }
      g_fvgCount = writeIdx;

      // Compact BPR array
      writeIdx = 0;
      for(int i = 0; i < g_bprCount; i++)
      {
         if(g_bprs[i].active && !g_bprs[i].used)
         {
            if(writeIdx != i) g_bprs[writeIdx] = g_bprs[i];
            writeIdx++;
         }
      }
      g_bprCount = writeIdx;

      LogMsg("Daily reset. Equity: " + DoubleToString(g_dailyStartEquity, 2) +
             " FVGs: " + IntegerToString(g_fvgCount) + " BPRs: " + IntegerToString(g_bprCount));
   }
}

//+------------------------------------------------------------------+
//| UPDATE SESSION RANGES                                             |
//+------------------------------------------------------------------+
void UpdateSessionRanges()
{
   int nyHour = GetNYHour();

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(Inp_Symbol, PERIOD_M5, 0, 2, rates) < 2) return;

   double h = rates[1].high;
   double l = rates[1].low;

   // Asian range: 19:00-00:00 NY time
   if(nyHour >= 19 || nyHour < 0)  // 19:00-23:59 NY
   {
      if(h > g_asianRange.high) g_asianRange.high = h;
      if(l < g_asianRange.low)  g_asianRange.low  = l;
   }
   if(nyHour == 0 && !g_asianRange.valid && g_asianRange.high > 0)
   {
      g_asianRange.valid = true;
      LogMsg(StringFormat("Asian range set: %.2f - %.2f (%.2f width)",
             g_asianRange.low, g_asianRange.high,
             g_asianRange.high - g_asianRange.low));
   }

   // London range: 02:00-07:00 NY time
   if(nyHour >= 2 && nyHour < 7)
   {
      if(h > g_londonRange.high) g_londonRange.high = h;
      if(l < g_londonRange.low)  g_londonRange.low  = l;
   }
   if(nyHour == 7 && !g_londonRange.valid && g_londonRange.high > 0)
   {
      g_londonRange.valid = true;
      LogMsg(StringFormat("London range set: %.2f - %.2f (%.2f width)",
             g_londonRange.low, g_londonRange.high,
             g_londonRange.high - g_londonRange.low));
   }
}

//+------------------------------------------------------------------+
//| HTF BIAS: H4 EMA trend                                           |
//+------------------------------------------------------------------+
int GetHTFBias()
{
   double emaFast = GetIndicator(g_emaFast_H4, 0, 1);
   double emaSlow = GetIndicator(g_emaSlow_H4, 0, 1);
   if(emaFast > emaSlow) return DIR_BULL;
   if(emaFast < emaSlow) return DIR_BEAR;
   return 0;
}

//+------------------------------------------------------------------+
//| ===== STRATEGY 1: JUDAS SWING =====                               |
//+------------------------------------------------------------------+
void CheckJudasSwing()
{
   if(!Inp_EnableJudas) return;
   if(CountOpenPositions() >= Inp_MaxConcurrentPos) return;
   if(IsLossLimitHit()) return;

   int nyHour = GetNYHour();

   // Day filter: Tue-Thu only
   if(Inp_JS_DayFilter)
   {
      int dow = GetDayOfWeek();
      if(dow < 2 || dow > 4) return;  // Skip Mon, Fri, Sat, Sun
   }

   // Determine which killzone we're in
   bool inLondonKZ = (nyHour >= 2 && nyHour < 5);
   bool inNYKZ     = (nyHour >= 7 && nyHour < 10);

   if(!inLondonKZ && !inNYKZ) return;

   // Check if already traded this killzone
   if(inLondonKZ && g_judasTradedLondon) return;
   if(inNYKZ && g_judasTradedNY) return;

   // Select range to sweep
   SessionRange range;
   string kzName;
   if(inLondonKZ)
   {
      if(!g_asianRange.valid) return;
      range = g_asianRange;
      kzName = "London";
   }
   else
   {
      if(!g_londonRange.valid) return;
      range = g_londonRange;
      kzName = "NY";
   }

   // Validate range size
   double dailyATR = GetATR(g_atrHandle_D1);
   if(dailyATR <= 0) return;
   double rangeWidth = range.high - range.low;
   if(rangeWidth < dailyATR * Inp_JS_MinRangeATR) return;
   if(rangeWidth > dailyATR * Inp_JS_MaxRangeATR) return;

   // HTF bias filter
   int htfBias = GetHTFBias();

   // Get M5 rates for sweep + MSS detection
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(Inp_Symbol, PERIOD_M5, 0, 60, rates);
   if(copied < 30) return;

   double atr_m5 = GetATR(g_atrHandle_M5);
   if(atr_m5 <= 0) return;

   // Scan recent bars for sweep
   for(int i = 1; i <= 10; i++)
   {
      // Bullish sweep: wick below range low, close back above
      if(rates[i].low < range.low && rates[i].close > range.low)
      {
         if(htfBias == DIR_BEAR) continue;  // HTF must not be bearish for longs

         // Look for MSS (bullish): break above recent swing high with displacement
         for(int j = 1; j < i; j++)
         {
            // Find if any bar after sweep broke a swing high with displacement
            double body = MathAbs(rates[j].close - rates[j].open);
            double candleRange = rates[j].high - rates[j].low;
            if(candleRange <= 0) continue;

            bool isDisplacement = (body >= atr_m5 * Inp_JS_DisplacementATR) &&
                                  (body / candleRange >= 0.6) &&
                                  (rates[j].close > rates[j].open);  // bullish

            if(!isDisplacement) continue;

            // Check if this broke a recent swing high
            bool brokeSH = false;
            for(int k = j + 1; k < i + 10 && k < copied - Inp_JS_SwingLookback; k++)
            {
               if(IsSwingHigh(rates, k, Inp_JS_SwingLookback))
               {
                  if(rates[j].close > rates[k].high)
                  {
                     brokeSH = true;
                     break;
                  }
               }
            }
            if(!brokeSH) continue;

            // Look for FVG in the displacement move
            // Bullish FVG: gap between candle[j+1] high and candle[j-1] low
            if(j >= 1 && j + 1 < copied)
            {
               double fvg_top = rates[j-1].low;
               double fvg_bot = rates[j+1].high;
               if(fvg_top > fvg_bot && (fvg_top - fvg_bot) >= atr_m5 * 0.2)
               {
                  // We have sweep + MSS + FVG -> enter long
                  double entry = SymbolInfoDouble(Inp_Symbol, SYMBOL_ASK);
                  double sl = rates[i].low - Inp_JS_SLBuffer;
                  double slDist = entry - sl;
                  double tp = entry + slDist * Inp_JS_RR;

                  if(slDist <= 0 || slDist < 5.0 || slDist > dailyATR * 0.5) continue;
                  if(!ValidateStops(entry, sl, tp)) continue;

                  double lots = CalcLots(slDist);
                  if(lots <= 0) continue;

                  string comment = "JS_" + kzName + "_BUY";
                  if(g_trade.Buy(lots, Inp_Symbol, entry, sl, tp, comment))
                  {
                     LogMsg(StringFormat("JUDAS %s BUY: %.2f lots @ %.2f, SL=%.2f, TP=%.2f",
                            kzName, lots, entry, sl, tp));
                     if(inLondonKZ) g_judasTradedLondon = true;
                     else g_judasTradedNY = true;

                     DrawArrow(comment + TimeToString(TimeCurrent()),
                              TimeCurrent(), entry, true, Inp_BullColor,
                              StringFormat("Judas BUY %.2f @ %.2f", lots, entry));
                  }
                  return;
               }
            }
         }
      }

      // Bearish sweep: wick above range high, close back below
      if(rates[i].high > range.high && rates[i].close < range.high)
      {
         if(htfBias == DIR_BULL) continue;  // HTF must not be bullish for shorts

         // Look for MSS (bearish): break below recent swing low with displacement
         for(int j = 1; j < i; j++)
         {
            double body = MathAbs(rates[j].close - rates[j].open);
            double candleRange = rates[j].high - rates[j].low;
            if(candleRange <= 0) continue;

            bool isDisplacement = (body >= atr_m5 * Inp_JS_DisplacementATR) &&
                                  (body / candleRange >= 0.6) &&
                                  (rates[j].close < rates[j].open);  // bearish

            if(!isDisplacement) continue;

            bool brokeSL = false;
            for(int k = j + 1; k < i + 10 && k < copied - Inp_JS_SwingLookback; k++)
            {
               if(IsSwingLow(rates, k, Inp_JS_SwingLookback))
               {
                  if(rates[j].close < rates[k].low)
                  {
                     brokeSL = true;
                     break;
                  }
               }
            }
            if(!brokeSL) continue;

            // Look for bearish FVG
            if(j >= 1 && j + 1 < copied)
            {
               double fvg_top = rates[j+1].low;
               double fvg_bot = rates[j-1].high;
               if(fvg_top > fvg_bot && (fvg_top - fvg_bot) >= atr_m5 * 0.2)
               {
                  double entry = SymbolInfoDouble(Inp_Symbol, SYMBOL_BID);
                  double sl = rates[i].high + Inp_JS_SLBuffer;
                  double slDist = sl - entry;
                  double tp = entry - slDist * Inp_JS_RR;

                  if(slDist <= 0 || slDist < 5.0 || slDist > dailyATR * 0.5) continue;
                  if(!ValidateStops(entry, sl, tp)) continue;

                  double lots = CalcLots(slDist);
                  if(lots <= 0) continue;

                  string comment = "JS_" + kzName + "_SELL";
                  if(g_trade.Sell(lots, Inp_Symbol, entry, sl, tp, comment))
                  {
                     LogMsg(StringFormat("JUDAS %s SELL: %.2f lots @ %.2f, SL=%.2f, TP=%.2f",
                            kzName, lots, entry, sl, tp));
                     if(inLondonKZ) g_judasTradedLondon = true;
                     else g_judasTradedNY = true;

                     DrawArrow(comment + TimeToString(TimeCurrent()),
                              TimeCurrent(), entry, false, Inp_BearColor,
                              StringFormat("Judas SELL %.2f @ %.2f", lots, entry));
                  }
                  return;
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ===== STRATEGY 2: SILVER BULLET =====                             |
//+------------------------------------------------------------------+
void CheckSilverBullet()
{
   if(!Inp_EnableSilverBullet) return;
   if(CountOpenPositions() >= Inp_MaxConcurrentPos) return;
   if(IsLossLimitHit()) return;

   int nyHour = GetNYHour();

   // Check if we're in a Silver Bullet window
   bool inLondonSB = (nyHour == 3);                      // 03:00-04:00 NY
   bool inNYAMSB   = (nyHour == 10);                     // 10:00-11:00 NY (PRIMARY)

   if(!inLondonSB && !inNYAMSB) return;

   if(inLondonSB && g_sbTradedLondon) return;
   if(inNYAMSB && g_sbTradedNYAM) return;

   // Spread check
   double spread = SymbolInfoDouble(Inp_Symbol, SYMBOL_ASK) - SymbolInfoDouble(Inp_Symbol, SYMBOL_BID);
   if(spread > Inp_SB_MaxSpread) return;

   // HTF bias (DOL direction)
   int htfBias = GetHTFBias();
   if(htfBias == 0) return;  // No clear bias, skip

   // Get M5 rates
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(Inp_Symbol, PERIOD_M5, 0, 60, rates);
   if(copied < 30) return;

   double atr_m5 = GetATR(g_atrHandle_M5);
   if(atr_m5 <= 0) return;

   // Find liquidity levels (swing H/L from last 60 M5 bars)
   double nearestBSL = -1, nearestSSL = -1;
   double currentPrice = rates[0].close;

   for(int i = Inp_SB_SwingLookback; i < copied - Inp_SB_SwingLookback; i++)
   {
      if(IsSwingHigh(rates, i, Inp_SB_SwingLookback))
      {
         if(rates[i].high > currentPrice)
         {
            if(nearestBSL < 0 || rates[i].high < nearestBSL)
               nearestBSL = rates[i].high;
         }
      }
      if(IsSwingLow(rates, i, Inp_SB_SwingLookback))
      {
         if(rates[i].low < currentPrice)
         {
            if(nearestSSL < 0 || rates[i].low > nearestSSL)
               nearestSSL = rates[i].low;
         }
      }
   }

   // Also use session ranges as liquidity
   if(g_asianRange.valid)
   {
      if(g_asianRange.high > currentPrice && (nearestBSL < 0 || g_asianRange.high < nearestBSL))
         nearestBSL = g_asianRange.high;
      if(g_asianRange.low < currentPrice && (nearestSSL < 0 || g_asianRange.low > nearestSSL))
         nearestSSL = g_asianRange.low;
   }
   if(g_londonRange.valid)
   {
      if(g_londonRange.high > currentPrice && (nearestBSL < 0 || g_londonRange.high < nearestBSL))
         nearestBSL = g_londonRange.high;
      if(g_londonRange.low < currentPrice && (nearestSSL < 0 || g_londonRange.low > nearestSSL))
         nearestSSL = g_londonRange.low;
   }

   // Scan for sweep + displacement + FVG within the SB window
   for(int i = 1; i <= Inp_SB_ScanBars; i++)
   {
      // Bullish: sweep of SSL then displacement up
      if(htfBias == DIR_BULL && nearestSSL > 0)
      {
         // Require minimum penetration depth beyond the level
         double sweepDepth = nearestSSL - rates[i].low;
         if(rates[i].low < nearestSSL && rates[i].close > nearestSSL &&
            sweepDepth >= atr_m5 * Inp_SB_MinSweepATR)
         {
            // Look for bullish displacement + FVG
            for(int j = 1; j < i; j++)
            {
               double body = MathAbs(rates[j].close - rates[j].open);
               double cr = rates[j].high - rates[j].low;
               if(cr <= 0) continue;

               if(body >= atr_m5 * Inp_SB_DisplacementATR &&
                  body / cr >= 0.6 && rates[j].close > rates[j].open)
               {
                  // Check for bullish FVG
                  if(j >= 1 && j + 1 < copied)
                  {
                     double fvg_top = rates[j-1].low;
                     double fvg_bot = rates[j+1].high;
                     double fvg_size = fvg_top - fvg_bot;

                     if(fvg_size >= atr_m5 * Inp_SB_MinFVGATR)
                     {
                        double entry = SymbolInfoDouble(Inp_Symbol, SYMBOL_ASK);
                        double sl = rates[i].low - atr_m5 * 0.5;
                        double slDist = entry - sl;
                        double tp = entry + slDist * Inp_SB_RR;

                        if(slDist <= 0 || slDist < 5.0) continue;
                        if(!ValidateStops(entry, sl, tp)) continue;

                        double lots = CalcLots(slDist);
                        if(lots <= 0) continue;

                        string sbWindow = inLondonSB ? "LDN" : "NYAM";
                        string comment = "SB_" + sbWindow + "_BUY";
                        if(g_trade.Buy(lots, Inp_Symbol, entry, sl, tp, comment))
                        {
                           LogMsg(StringFormat("SILVER BULLET %s BUY: %.2f lots @ %.2f", sbWindow, lots, entry));
                           if(inLondonSB) g_sbTradedLondon = true;
                           else g_sbTradedNYAM = true;

                           DrawArrow(comment + TimeToString(TimeCurrent()),
                                    TimeCurrent(), entry, true, Inp_BullColor,
                                    StringFormat("SB BUY %.2f @ %.2f", lots, entry));
                        }
                        return;
                     }
                  }
               }
            }
         }
      }

      // Bearish: sweep of BSL then displacement down
      if(htfBias == DIR_BEAR && nearestBSL > 0)
      {
         double sweepDepth = rates[i].high - nearestBSL;
         if(rates[i].high > nearestBSL && rates[i].close < nearestBSL &&
            sweepDepth >= atr_m5 * Inp_SB_MinSweepATR)
         {
            for(int j = 1; j < i; j++)
            {
               double body = MathAbs(rates[j].close - rates[j].open);
               double cr = rates[j].high - rates[j].low;
               if(cr <= 0) continue;

               if(body >= atr_m5 * Inp_SB_DisplacementATR &&
                  body / cr >= 0.6 && rates[j].close < rates[j].open)
               {
                  if(j >= 1 && j + 1 < copied)
                  {
                     double fvg_top = rates[j+1].low;
                     double fvg_bot = rates[j-1].high;
                     double fvg_size = fvg_top - fvg_bot;

                     if(fvg_size >= atr_m5 * Inp_SB_MinFVGATR)
                     {
                        double entry = SymbolInfoDouble(Inp_Symbol, SYMBOL_BID);
                        double sl = rates[i].high + atr_m5 * 0.5;
                        double slDist = sl - entry;
                        double tp = entry - slDist * Inp_SB_RR;

                        if(slDist <= 0 || slDist < 5.0) continue;
                        if(!ValidateStops(entry, sl, tp)) continue;

                        double lots = CalcLots(slDist);
                        if(lots <= 0) continue;

                        string sbWindow = inLondonSB ? "LDN" : "NYAM";
                        string comment = "SB_" + sbWindow + "_SELL";
                        if(g_trade.Sell(lots, Inp_Symbol, entry, sl, tp, comment))
                        {
                           LogMsg(StringFormat("SILVER BULLET %s SELL: %.2f lots @ %.2f", sbWindow, lots, entry));
                           if(inLondonSB) g_sbTradedLondon = true;
                           else g_sbTradedNYAM = true;

                           DrawArrow(comment + TimeToString(TimeCurrent()),
                                    TimeCurrent(), entry, false, Inp_BearColor,
                                    StringFormat("SB SELL %.2f @ %.2f", lots, entry));
                        }
                        return;
                     }
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ===== STRATEGY 3: ASIAN MEAN REVERSION =====                      |
//+------------------------------------------------------------------+
void CheckAsianMeanReversion()
{
   if(!Inp_EnableAsianMR) return;
   if(CountOpenPositions() >= Inp_MaxConcurrentPos) return;
   if(IsLossLimitHit()) return;
   if(g_mrTradestoday >= Inp_MR_MaxTradesPerDay) return;

   int utcHour = GetUTCHour();

   // Only trade 21:00-01:00 UTC
   if(utcHour < 21 && utcHour > 1) return;

   // Skip rollover 00:00-00:15
   if(utcHour == 0 && GetNYMinute() < 15) return;

   // Cooldown: skip if last MR entry was too recent
   datetime currentBarTime = iTime(Inp_Symbol, PERIOD_M5, 0);
   if(g_mrLastEntryBar > 0 && currentBarTime - g_mrLastEntryBar < Inp_MR_CooldownBars * PeriodSeconds(PERIOD_M5))
      return;

   // Spread check
   double spread = SymbolInfoDouble(Inp_Symbol, SYMBOL_ASK) - SymbolInfoDouble(Inp_Symbol, SYMBOL_BID);
   if(spread > Inp_MR_MaxSpread) return;

   // Get indicator values (M5 bar[1] = last completed)
   double upperBB = GetIndicator(g_bbHandle_M5, 1, 1);   // Upper band
   double middleBB = GetIndicator(g_bbHandle_M5, 0, 1);   // Middle band
   double lowerBB = GetIndicator(g_bbHandle_M5, 2, 1);   // Lower band
   double rsi = GetIndicator(g_rsiHandle_M5, 0, 1);
   double adx = GetIndicator(g_adxHandle_M5, 0, 1);       // Main ADX line

   if(upperBB <= 0 || lowerBB <= 0 || middleBB <= 0) return;

   // Minimum BB absolute width check
   double bbAbsWidth = upperBB - lowerBB;
   if(bbAbsWidth < Inp_MR_MinBBWidth) return;

   // ADX filter: must be ranging
   if(adx > Inp_MR_ADXMax) return;

   // BB width filter: not in squeeze or expansion
   double bbWidth = bbAbsWidth / middleBB;
   // Get average BB width
   double avgWidth = 0;
   for(int i = 1; i <= 50; i++)
   {
      double ub = GetIndicator(g_bbHandle_M5, 1, i);
      double mb = GetIndicator(g_bbHandle_M5, 0, i);
      double lb = GetIndicator(g_bbHandle_M5, 2, i);
      if(mb > 0) avgWidth += (ub - lb) / mb;
   }
   avgWidth /= 50.0;

   if(bbWidth < avgWidth * 0.8 || bbWidth > avgWidth * 1.3) return;

   // Trend continuation filter: check if previous NY session was extreme
   double atr_h1 = GetATR(g_atrHandle_H1);
   double dailyATR = GetATR(g_atrHandle_D1);
   // Simple: if current ATR(M5) is > 2x average, skip
   double atr_m5 = GetATR(g_atrHandle_M5);
   double avgATR = 0;
   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(g_atrHandle_M5, 0, 1, 100, atrBuf) >= 100)
   {
      for(int i = 0; i < 100; i++) avgATR += atrBuf[i];
      avgATR /= 100.0;
      if(atr_m5 > avgATR * 2.0) return;  // Too volatile
   }

   // Get last completed M5 bar
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(Inp_Symbol, PERIOD_M5, 0, 3, rates) < 3) return;

   double closePrice = rates[1].close;

   // Minimum distances for gold — wider SL to avoid noise
   double minSLDist = MathMax(atr_m5 * 2.0, 7.0);  // At least $7 or 2x ATR

   // LONG: close below lower BB + RSI oversold
   if(closePrice < lowerBB && rsi < Inp_MR_RSIOversold)
   {
      double entry = SymbolInfoDouble(Inp_Symbol, SYMBOL_ASK);
      double slDist = MathMax(atr_m5 * Inp_MR_SL_ATRMult, minSLDist);
      double sl = entry - slDist;
      double tp = middleBB;  // Target: middle Bollinger Band

      // Ensure TP is far enough
      double tpDist = tp - entry;
      if(tpDist < 5.0) return;  // Need at least $5 profit target
      if(!ValidateStops(entry, sl, tp)) return;

      double lots = CalcLots(slDist);
      if(lots <= 0) return;

      string comment = "MR_BUY";
      if(g_trade.Buy(lots, Inp_Symbol, entry, sl, tp, comment))
      {
         g_mrTradestoday++;
         g_mrLastEntryBar = iTime(Inp_Symbol, PERIOD_M5, 0);
         LogMsg(StringFormat("ASIAN MR BUY: %.2f lots @ %.2f, SL=%.2f, TP=%.2f (BB mid)",
                lots, entry, sl, tp));
         DrawArrow(comment + TimeToString(TimeCurrent()),
                  TimeCurrent(), entry, true, clrDodgerBlue,
                  StringFormat("MR BUY %.2f RSI=%.0f", lots, rsi));
      }
      return;  // Only one entry per bar
   }

   // SHORT: close above upper BB + RSI overbought
   if(closePrice > upperBB && rsi > Inp_MR_RSIOverbought)
   {
      double entry = SymbolInfoDouble(Inp_Symbol, SYMBOL_BID);
      double slDist = MathMax(atr_m5 * Inp_MR_SL_ATRMult, minSLDist);
      double sl = entry + slDist;
      double tp = middleBB;  // Target: middle Bollinger Band

      double tpDist = entry - tp;
      if(tpDist < 5.0) return;  // Need at least $5 profit target
      if(!ValidateStops(entry, sl, tp)) return;

      double lots = CalcLots(slDist);
      if(lots <= 0) return;

      string comment = "MR_SELL";
      if(g_trade.Sell(lots, Inp_Symbol, entry, sl, tp, comment))
      {
         g_mrTradestoday++;
         g_mrLastEntryBar = iTime(Inp_Symbol, PERIOD_M5, 0);
         LogMsg(StringFormat("ASIAN MR SELL: %.2f lots @ %.2f, SL=%.2f, TP=%.2f (BB mid)",
                lots, entry, sl, tp));
         DrawArrow(comment + TimeToString(TimeCurrent()),
                  TimeCurrent(), entry, false, clrDodgerBlue,
                  StringFormat("MR SELL %.2f RSI=%.0f", lots, rsi));
      }
   }
}

//+------------------------------------------------------------------+
//| ===== STRATEGY 4: BPR (from existing bot) =====                   |
//+------------------------------------------------------------------+

//--- BPR: Detect Market Structure
MARKET_STRUCTURE DetectStructure(ENUM_TIMEFRAMES tf, int lookback)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int need = lookback * 3 + 10;
   if(CopyRates(Inp_Symbol, tf, 0, need, rates) < need)
      return STRUCT_RANGE;

   double lastSH = -1, prevSH = -1;
   double lastSL = -1, prevSL = -1;

   for(int i = lookback; i < need - lookback; i++)
   {
      if(IsSwingHigh(rates, i, lookback))
      {
         if(lastSH < 0) lastSH = rates[i].high;
         else if(prevSH < 0) { prevSH = lastSH; lastSH = rates[i].high; }
      }
      if(IsSwingLow(rates, i, lookback))
      {
         if(lastSL < 0) lastSL = rates[i].low;
         else if(prevSL < 0) { prevSL = lastSL; lastSL = rates[i].low; }
      }
      if(prevSH > 0 && prevSL > 0) break;
   }

   if(prevSH < 0 || prevSL < 0) return STRUCT_RANGE;

   bool higherHigh = (lastSH > prevSH);
   bool higherLow  = (lastSL > prevSL);
   bool lowerHigh  = (lastSH < prevSH);
   bool lowerLow   = (lastSL < prevSL);

   if(higherHigh && higherLow) return STRUCT_BULLISH;
   if(lowerHigh && lowerLow)   return STRUCT_BEARISH;
   return STRUCT_RANGE;
}

//--- BPR: Detect FVGs
void DetectFVGs_BPR()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int need = Inp_BPR_Lookback + 5;
   if(CopyRates(Inp_Symbol, PERIOD_M15, 0, need, rates) < need) return;

   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(g_atrHandle_M15, 0, 0, 3, atrBuf) < 1) return;
   double atr = atrBuf[0];
   if(atr <= 0) return;
   g_currentATR_M15 = atr;

   // ATR filter thresholds
   double minFVGSize = 0;
   switch(Inp_BPR_FVGTier)
   {
      case 0: minFVGSize = atr * 0.1; break;
      case 1: minFVGSize = atr * 0.2; break;
      case 2: minFVGSize = atr * 0.3; break;
      case 3: minFVGSize = atr * 0.5; break;
   }

   MqlDateTime today;
   TimeToStruct(TimeCurrent(), today);
   datetime todayDate = StringToTime(IntegerToString(today.year) + "." +
                                      IntegerToString(today.mon) + "." +
                                      IntegerToString(today.day));

   for(int i = 1; i < Inp_BPR_Lookback - 2; i++)
   {
      datetime fvgTime = rates[i+1].time;

      // Check duplicate
      bool dup = false;
      for(int d = 0; d < g_fvgCount; d++)
      {
         if(g_fvgs[d].time == fvgTime && g_fvgs[d].active)
         { dup = true; break; }
      }
      if(dup) continue;

      // Bullish FVG
      if(rates[i].low > rates[i+2].high &&
         rates[i+1].close > rates[i+2].high)
      {
         double size = rates[i].low - rates[i+2].high;
         if(size >= minFVGSize)
         {
            if(g_fvgCount < ArraySize(g_fvgs))
            {
               g_fvgs[g_fvgCount].time       = fvgTime;
               g_fvgs[g_fvgCount].high_bound  = rates[i].low;
               g_fvgs[g_fvgCount].low_bound   = rates[i+2].high;
               g_fvgs[g_fvgCount].direction    = DIR_BULL;
               g_fvgs[g_fvgCount].active       = true;
               g_fvgs[g_fvgCount].bpr_checked  = false;
               g_fvgs[g_fvgCount].day_date     = todayDate;
               g_fvgCount++;
            }
         }
      }

      // Bearish FVG
      if(rates[i].high < rates[i+2].low &&
         rates[i+1].close < rates[i+2].low)
      {
         double size = rates[i+2].low - rates[i].high;
         if(size >= minFVGSize)
         {
            if(g_fvgCount < ArraySize(g_fvgs))
            {
               g_fvgs[g_fvgCount].time       = fvgTime;
               g_fvgs[g_fvgCount].high_bound  = rates[i+2].low;
               g_fvgs[g_fvgCount].low_bound   = rates[i].high;
               g_fvgs[g_fvgCount].direction    = DIR_BEAR;
               g_fvgs[g_fvgCount].active       = true;
               g_fvgs[g_fvgCount].bpr_checked  = false;
               g_fvgs[g_fvgCount].day_date     = todayDate;
               g_fvgCount++;
            }
         }
      }
   }

   // Expire old FVGs
   for(int i = 0; i < g_fvgCount; i++)
   {
      if(g_fvgs[i].active && g_fvgs[i].day_date < todayDate)
         g_fvgs[i].active = false;
   }
}

//--- BPR: Detect BPRs from FVG pairs
void DetectBPRs()
{
   for(int i = 0; i < g_fvgCount; i++)
   {
      if(!g_fvgs[i].active || g_fvgs[i].bpr_checked) continue;

      for(int j = 0; j < g_fvgCount; j++)
      {
         if(i == j) continue;
         if(!g_fvgs[j].active || g_fvgs[j].bpr_checked) continue;
         if(g_fvgs[i].direction == g_fvgs[j].direction) continue;

         // Check overlap
         double ovlp_high = MathMin(g_fvgs[i].high_bound, g_fvgs[j].high_bound);
         double ovlp_low  = MathMax(g_fvgs[i].low_bound, g_fvgs[j].low_bound);

         if(ovlp_high <= ovlp_low) continue;

         double bprWidth = ovlp_high - ovlp_low;
         if(g_currentATR_M15 > 0 && bprWidth < g_currentATR_M15 * 0.15)
            continue;

         // Direction = last FVG formed
         int dir;
         if(g_fvgs[i].time > g_fvgs[j].time)
            dir = g_fvgs[i].direction;
         else
            dir = g_fvgs[j].direction;

         // Check if BPR already exists at this overlap
         bool exists = false;
         for(int k = 0; k < g_bprCount; k++)
         {
            if(g_bprs[k].active &&
               MathAbs(g_bprs[k].high_bound - ovlp_high) < g_symPoint &&
               MathAbs(g_bprs[k].low_bound - ovlp_low) < g_symPoint)
            { exists = true; break; }
         }
         if(exists) continue;

         if(g_bprCount < ArraySize(g_bprs))
         {
            g_bprIdCounter++;
            g_bprs[g_bprCount].high_bound  = ovlp_high;
            g_bprs[g_bprCount].low_bound   = ovlp_low;
            g_bprs[g_bprCount].full_high   = MathMax(g_fvgs[i].high_bound, g_fvgs[j].high_bound);
            g_bprs[g_bprCount].full_low    = MathMin(g_fvgs[i].low_bound, g_fvgs[j].low_bound);
            g_bprs[g_bprCount].direction   = dir;
            g_bprs[g_bprCount].active      = true;
            g_bprs[g_bprCount].used        = false;

            MqlDateTime dt;
            TimeToStruct(TimeCurrent(), dt);
            g_bprs[g_bprCount].formed_date = StringToTime(
               IntegerToString(dt.year) + "." + IntegerToString(dt.mon) + "." + IntegerToString(dt.day));

            g_bprs[g_bprCount].left_time  = MathMin(g_fvgs[i].time, g_fvgs[j].time);
            g_bprs[g_bprCount].right_time = MathMax(g_fvgs[i].time, g_fvgs[j].time);
            g_bprs[g_bprCount].box_name   = "BPR_" + IntegerToString(g_bprIdCounter);

            // Draw box
            if(Inp_DrawObjects)
            {
               string name = g_bprs[g_bprCount].box_name;
               ObjectCreate(0, name, OBJ_RECTANGLE, 0,
                           g_bprs[g_bprCount].left_time, ovlp_high,
                           g_bprs[g_bprCount].right_time + PeriodSeconds(PERIOD_M15) * 5, ovlp_low);
               ObjectSetInteger(0, name, OBJPROP_COLOR,
                               dir == DIR_BULL ? Inp_BullColor : Inp_BearColor);
               ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
               ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
               ObjectSetInteger(0, name, OBJPROP_FILL, true);
               ObjectSetInteger(0, name, OBJPROP_BACK, true);
            }

            g_bprCount++;
         }

         g_fvgs[i].bpr_checked = true;
         g_fvgs[j].bpr_checked = true;
      }
   }
}

//--- BPR: Check entry
void CheckBPREntry()
{
   if(!Inp_EnableBPR) return;
   if(CountOpenPositions() >= Inp_MaxConcurrentPos) return;
   if(IsLossLimitHit()) return;

   // Asia session block
   int utcHour = GetUTCHour();
   if(utcHour >= 0 && utcHour < 9) return;

   // HTF structure
   g_htfStructure = DetectStructure(PERIOD_H1, Inp_BPR_SwingN);
   g_entryStructure = DetectStructure(PERIOD_M15, Inp_BPR_SwingN);
   if(g_htfStructure == STRUCT_RANGE) return;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(Inp_Symbol, PERIOD_M15, 0, 3, rates) < 3) return;

   for(int i = 0; i < g_bprCount; i++)
   {
      if(!g_bprs[i].active || g_bprs[i].used) continue;

      // Close-inside-zone check (bar1 or bar2)
      bool bar1In = (rates[1].close >= g_bprs[i].low_bound &&
                     rates[1].close <= g_bprs[i].high_bound);
      bool bar2In = (rates[2].close >= g_bprs[i].low_bound &&
                     rates[2].close <= g_bprs[i].high_bound);
      if(!bar1In && !bar2In) continue;

      // Rejection candle
      if(g_bprs[i].direction == DIR_BULL && rates[1].close <= rates[1].open) continue;
      if(g_bprs[i].direction == DIR_BEAR && rates[1].close >= rates[1].open) continue;

      // Structure alignment
      if(g_bprs[i].direction == DIR_BULL)
      {
         if(g_htfStructure != STRUCT_BULLISH) continue;
         if(g_entryStructure == STRUCT_BEARISH) continue;
      }
      else
      {
         if(g_htfStructure != STRUCT_BEARISH) continue;
         if(g_entryStructure == STRUCT_BULLISH) continue;
      }

      // Execute trade
      double entry, sl, tp, slDist;
      if(g_bprs[i].direction == DIR_BULL)
      {
         entry = SymbolInfoDouble(Inp_Symbol, SYMBOL_ASK);
         sl = g_bprs[i].full_low - Inp_BPR_SLBuffer * g_symPoint;
         slDist = entry - sl;
         tp = entry + slDist * Inp_BPR_RR;
      }
      else
      {
         entry = SymbolInfoDouble(Inp_Symbol, SYMBOL_BID);
         sl = g_bprs[i].full_high + Inp_BPR_SLBuffer * g_symPoint;
         slDist = sl - entry;
         tp = entry - slDist * Inp_BPR_RR;
      }

      if(slDist <= 0 || slDist < 5.0) continue;
      if(g_currentATR_M15 > 0 && slDist < g_currentATR_M15 * 0.2) continue;
      if(!ValidateStops(entry, sl, tp)) continue;

      double lots = CalcLots(slDist);
      if(lots <= 0) continue;

      bool result;
      string comment = g_bprs[i].box_name;
      if(g_bprs[i].direction == DIR_BULL)
         result = g_trade.Buy(lots, Inp_Symbol, entry, sl, tp, comment);
      else
         result = g_trade.Sell(lots, Inp_Symbol, entry, sl, tp, comment);

      if(result)
      {
         g_bprs[i].used = true;
         LogMsg(StringFormat("BPR %s %s: %.2f lots @ %.2f, SL=%.2f, TP=%.2f",
                comment, g_bprs[i].direction == DIR_BULL ? "BUY" : "SELL",
                lots, entry, sl, tp));

         DrawArrow(comment + "_entry", TimeCurrent(), entry,
                  g_bprs[i].direction == DIR_BULL,
                  g_bprs[i].direction == DIR_BULL ? Inp_BullColor : Inp_BearColor,
                  StringFormat("BPR %s %.2f", g_bprs[i].direction == DIR_BULL ? "BUY" : "SELL", lots));
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| FORCE CLOSE ASIAN MR POSITIONS BEFORE LONDON                      |
//+------------------------------------------------------------------+
void CloseAsianMRPositions()
{
   int utcHour = GetUTCHour();
   if(utcHour != 6) return;  // Force close at 06:00 UTC

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != Inp_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Inp_MagicNumber) continue;

      string comment = PositionGetString(POSITION_COMMENT);
      if(StringFind(comment, "MR_") == 0)
      {
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         g_trade.PositionClose(ticket);
         LogMsg("Closed Asian MR position before London: ticket " + IntegerToString(ticket));
      }
   }
}

//+------------------------------------------------------------------+
//| OnTester — Custom optimization criterion                          |
//+------------------------------------------------------------------+
double OnTester()
{
   double pf     = TesterStatistics(STAT_PROFIT_FACTOR);
   double sharpe = TesterStatistics(STAT_SHARPE_RATIO);
   double rf     = TesterStatistics(STAT_RECOVERY_FACTOR);
   int    trades = (int)TesterStatistics(STAT_TRADES);

   // Penalize low trade count
   double tradePenalty = (trades < 20) ? 0.5 : 1.0;

   return (pf * 0.35 + sharpe * 0.30 + rf * 0.20 + MathMin(trades, 100) / 100.0 * 0.15) * tradePenalty;
}

//+------------------------------------------------------------------+
//| TRAILING STOP: Move SL to breakeven after 1R profit               |
//+------------------------------------------------------------------+
void ManageTrailingStops()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != Inp_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Inp_MagicNumber) continue;

      ulong ticket = PositionGetInteger(POSITION_TICKET);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      long posType = PositionGetInteger(POSITION_TYPE);

      // Calculate initial risk distance (entry to original SL)
      double riskDist = MathAbs(openPrice - currentSL);
      if(riskDist <= 0) continue;

      double bid = SymbolInfoDouble(Inp_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(Inp_Symbol, SYMBOL_ASK);

      if(posType == POSITION_TYPE_BUY)
      {
         double profit = bid - openPrice;
         // Once price has moved 1R in our favor, move SL to breakeven + small buffer
         if(profit >= riskDist && currentSL < openPrice)
         {
            double newSL = openPrice + 0.50;  // Breakeven + $0.50 buffer
            if(newSL > currentSL)
            {
               g_trade.PositionModify(ticket, newSL, currentTP);
            }
         }
         // Once price has moved 1.5R, trail SL at 1R behind
         else if(profit >= riskDist * 1.5 && currentSL >= openPrice)
         {
            double newSL = bid - riskDist;
            if(newSL > currentSL)
            {
               g_trade.PositionModify(ticket, newSL, currentTP);
            }
         }
      }
      else // SELL
      {
         double profit = openPrice - ask;
         if(profit >= riskDist && currentSL > openPrice)
         {
            double newSL = openPrice - 0.50;  // Breakeven - $0.50
            if(newSL < currentSL)
            {
               g_trade.PositionModify(ticket, newSL, currentTP);
            }
         }
         else if(profit >= riskDist * 1.5 && currentSL <= openPrice)
         {
            double newSL = ask + riskDist;
            if(newSL < currentSL)
            {
               g_trade.PositionModify(ticket, newSL, currentTP);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| OnTick — Main loop                                                |
//+------------------------------------------------------------------+
void OnTick()
{
   // Daily reset
   DailyReset();

   // Trailing stop disabled — interferes with TP at RR 2.0-2.5
   // ManageTrailingStops();

   // Update session ranges on every M5 bar
   if(IsNewBar(PERIOD_M5))
   {
      UpdateSessionRanges();

      // Strategy 1: Judas Swing (runs on M5 bars during killzones)
      CheckJudasSwing();

      // Strategy 2: Silver Bullet (runs on M5 bars during SB windows)
      CheckSilverBullet();

      // Strategy 3: Asian Mean Reversion (runs on M5 bars during Asian session)
      CheckAsianMeanReversion();

      // Force close MR positions before London
      CloseAsianMRPositions();
   }

   // Strategy 4: BPR (runs on M15 bars)
   if(IsNewBar(PERIOD_M15))
   {
      DetectFVGs_BPR();
      DetectBPRs();
      CheckBPREntry();
   }
}
//+------------------------------------------------------------------+

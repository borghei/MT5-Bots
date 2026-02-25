//+------------------------------------------------------------------+
//|                                                     BPR_Bot.mq5  |
//|                     Balanced Price Range (Double FVG) Strategy    |
//|                         ICT/SMC Methodology — Phase 1 Build      |
//+------------------------------------------------------------------+
#property copyright "BPR Bot"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

//--- Symbol & Timeframe
input string               Inp_Symbol              = "XAUUSD.ecn";    // Trading symbol
input ENUM_TIMEFRAMES      Inp_Timeframe           = PERIOD_M15;      // Entry timeframe

//--- Session filter (UTC hours)
input bool                 Inp_AsiaEnabled         = true;            // Enable session block
input string               Inp_AsiaStartUTC        = "00:00";         // Block start (UTC, inclusive)
input string               Inp_AsiaEndUTC          = "09:00";         // Block end (UTC, exclusive)

//--- Risk/Reward & Execution
input double               Inp_RR                  = 2.0;             // Risk:Reward ratio
input int                  Inp_SLBufferPoints      = 1;               // Buffer beyond BPR extreme (points)
input double               Inp_RiskFractionEquity  = 0.10;            // Risk per trade (fraction of equity)
input bool                 Inp_AllowMultiplePos    = false;           // Allow multiple positions
input int                  Inp_DeviationPoints     = 5;               // Max slippage (points)

//--- BPR / FVG Detection
input int                  Inp_BPRLookbackBars     = 30;              // Lookback for opposite FVGs
input int                  Inp_MaxActiveBPRs       = 10;              // Max simultaneous BPRs
input int                  Inp_BPRMinRangePoints   = 0;               // Min BPR width (points, 0=auto)
input bool                 Inp_CleanBPROnly        = false;           // Only untested FVGs form BPRs
input bool                 Inp_DeleteInvalidBPR    = true;            // Delete chart objects for invalid BPRs

//--- Market Structure
input int                  Inp_SwingLookback       = 3;               // Bars each side for swing detection
input int                  Inp_RangeThresholdPts   = 0;               // Range detection threshold (points)
input ENUM_TIMEFRAMES      Inp_HTF_Timeframe       = PERIOD_H1;       // Higher TF for structure bias

//--- Visuals
input bool                 Inp_DrawBPRBoxes        = true;            // Draw BPR rectangles
input color                Inp_BullBPRColor        = clrGreen;        // Bullish BPR color
input color                Inp_BearBPRColor        = clrRed;          // Bearish BPR color
input bool                 Inp_ShadeAsiaSession    = false;           // Draw Asia session rectangle

//--- Broker Time (TimeGMT broken in Tester)
input int                  Inp_GMTOffsetWinter     = 2;               // Broker GMT offset (winter)
input int                  Inp_GMTOffsetSummer     = 3;               // Broker GMT offset (summer DST)

//--- Trade Management
input int                  Inp_MagicNumber         = 240001;          // EA magic number
input int                  Inp_FVGFilterTier       = 2;               // ATR filter: 0=0.1x 1=0.2x 2=0.3x 3=0.5x

//+------------------------------------------------------------------+
//| ENUMS                                                             |
//+------------------------------------------------------------------+
enum MARKET_STRUCTURE
{
   STRUCT_BULLISH,
   STRUCT_BEARISH,
   STRUCT_RANGE
};

//+------------------------------------------------------------------+
//| DATA STRUCTURES                                                   |
//+------------------------------------------------------------------+

// Fair Value Gap
struct FVG
{
   datetime   time;            // candle 2 (middle) time — dedup key
   double     high_bound;      // upper edge (wick)
   double     low_bound;       // lower edge (wick)
   int        direction;       // +1 bullish, -1 bearish
   bool       active;          // still valid
   bool       bpr_checked;     // already scanned for BPR overlap
   datetime   day_date;        // trading day it belongs to
};

// Balanced Price Range
struct BPR
{
   double     high_bound;      // overlap zone upper
   double     low_bound;       // overlap zone lower
   double     full_high;       // highest point of entire BPR (PATCH 2 SL)
   double     full_low;        // lowest point of entire BPR (PATCH 2 SL)
   int        direction;       // +1 bullish, -1 bearish
   bool       active;
   bool       used;            // PATCH 1: consumed by trade
   datetime   formed_date;     // PATCH 3: daily lifecycle
   datetime   left_time;       // for visual box
   datetime   right_time;      // for visual box
   string     box_name;        // chart object name
};

// Swing Point
struct SwingPoint
{
   datetime   time;
   double     price;
   bool       is_high;         // true=swing high, false=swing low
};

//+------------------------------------------------------------------+
//| CONSTANTS                                                         |
//+------------------------------------------------------------------+
#define MAX_FVGS          200
#define MAX_BPRS          50
#define MAX_SWINGS        100
#define DIR_BULL          1
#define DIR_BEAR         -1

//+------------------------------------------------------------------+
//| GLOBALS                                                           |
//+------------------------------------------------------------------+
CTrade         g_trade;
datetime       g_lastBarTime      = 0;
int            g_atrHandle        = INVALID_HANDLE;
int            g_htfAtrHandle     = INVALID_HANDLE;

// FVG arrays
FVG            g_bullFVGs[];
FVG            g_bearFVGs[];
int            g_bullFVGCount     = 0;
int            g_bearFVGCount     = 0;

// BPR array
BPR            g_bprs[];
int            g_bprCount         = 0;
int            g_bprIdCounter     = 0;

// Swing points
SwingPoint     g_entrySwings[];
SwingPoint     g_htfSwings[];

// Structure
MARKET_STRUCTURE g_entryStructure = STRUCT_RANGE;
MARKET_STRUCTURE g_htfStructure   = STRUCT_RANGE;

// Session filter parsed
int            g_asiaStartHour    = 0;
int            g_asiaStartMin     = 0;
int            g_asiaEndHour      = 9;
int            g_asiaEndMin       = 0;

// Symbol cache (refreshed each trade)
double         g_symPoint         = 0;
int            g_symDigits        = 0;
double         g_currentATR       = 0;  // Updated each bar in DetectFVGs

//+------------------------------------------------------------------+
//| OnInit — Validate symbol, initialize CTrade, parse inputs         |
//+------------------------------------------------------------------+
int OnInit()
{
   // Validate symbol
   if(!SymbolInfoInteger(Inp_Symbol, SYMBOL_EXIST))
   {
      PrintFormat("ERROR: Symbol %s does not exist on this broker", Inp_Symbol);
      return INIT_FAILED;
   }

   // Cache basic symbol properties
   g_symPoint  = SymbolInfoDouble(Inp_Symbol, SYMBOL_POINT);
   g_symDigits = (int)SymbolInfoInteger(Inp_Symbol, SYMBOL_DIGITS);

   if(g_symPoint <= 0)
   {
      PrintFormat("ERROR: Invalid SYMBOL_POINT for %s: %f", Inp_Symbol, g_symPoint);
      return INIT_FAILED;
   }

   // Initialize CTrade
   g_trade.SetExpertMagicNumber(Inp_MagicNumber);
   g_trade.SetDeviationInPoints(Inp_DeviationPoints);
   g_trade.SetTypeFilling(ORDER_FILLING_FOK); // will be overridden below
   g_trade.SetTypeFillingBySymbol(Inp_Symbol);

   // ATR indicator for FVG filtering
   g_atrHandle = iATR(Inp_Symbol, Inp_Timeframe, 14);
   if(g_atrHandle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create ATR indicator for entry TF");
      return INIT_FAILED;
   }

   // Parse session times
   if(!ParseSessionTime(Inp_AsiaStartUTC, g_asiaStartHour, g_asiaStartMin) ||
      !ParseSessionTime(Inp_AsiaEndUTC, g_asiaEndHour, g_asiaEndMin))
   {
      Print("ERROR: Invalid session time format. Use HH:MM");
      return INIT_FAILED;
   }

   // Allocate arrays
   ArrayResize(g_bullFVGs, MAX_FVGS);
   ArrayResize(g_bearFVGs, MAX_FVGS);
   ArrayResize(g_bprs, MAX_BPRS);
   ArrayResize(g_entrySwings, MAX_SWINGS);
   ArrayResize(g_htfSwings, MAX_SWINGS);

   LogMessage("BPR Bot initialized. Symbol=" + Inp_Symbol +
              " TF=" + EnumToString(Inp_Timeframe) +
              " HTF=" + EnumToString(Inp_HTF_Timeframe) +
              " Magic=" + IntegerToString(Inp_MagicNumber));

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit — Cleanup chart objects                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Remove all BPR box objects
   for(int i = 0; i < g_bprCount; i++)
   {
      if(g_bprs[i].box_name != "" && ObjectFind(0, g_bprs[i].box_name) >= 0)
         ObjectDelete(0, g_bprs[i].box_name);
   }

   // Remove Asia session shading
   if(ObjectFind(0, "BPR_AsiaShade") >= 0)
      ObjectDelete(0, "BPR_AsiaShade");

   // Release indicators
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   if(g_htfAtrHandle != INVALID_HANDLE)
      IndicatorRelease(g_htfAtrHandle);

   LogMessage("BPR Bot deinitialized. Reason=" + IntegerToString(reason));
}

//+------------------------------------------------------------------+
//| OnTick — Main logic, runs on new bar only                        |
//+------------------------------------------------------------------+
void OnTick()
{
   // Only process on new bar (bar 0 still forming — never use it)
   if(!IsNewBar())
      return;

   // 1. Detect swing points on both timeframes
   DetectSwingPoints(Inp_Timeframe, Inp_SwingLookback, g_entrySwings);
   DetectSwingPoints(Inp_HTF_Timeframe, Inp_SwingLookback, g_htfSwings);

   // 2. Classify market structure
   g_entryStructure = ClassifyStructure(g_entrySwings);
   g_htfStructure   = ClassifyStructure(g_htfSwings);

   // 3. Detect new FVGs
   DetectFVGs();

   // 4. Detect new BPRs from FVG overlaps
   DetectBPRs();

   // 5. Validate existing BPRs (invalidate breached, expire old — PATCH 3)
   ValidateBPRs();

   // 6. Check for entry signals
   CheckEntry();
}

//+------------------------------------------------------------------+
//| IsNewBar — Detect new bar formation                               |
//|                                                                   |
//| Uses iTime comparison (not Bars() which is unreliable).           |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(Inp_Symbol, Inp_Timeframe, 0);
   if(currentBarTime == 0)
      return false;

   if(currentBarTime != g_lastBarTime)
   {
      g_lastBarTime = currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| DetectSwingPoints — Find swing highs/lows on given timeframe      |
//|                                                                   |
//| A bar is a swing high if its High is the maximum over N bars      |
//| on each side. Uses completed bars only (starts from bar 1).       |
//+------------------------------------------------------------------+
void DetectSwingPoints(ENUM_TIMEFRAMES tf, int lookback, SwingPoint &swings[])
{
   int barsNeeded = lookback * 2 + 50; // extra bars for sufficient data
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   int copied = CopyRates(Inp_Symbol, tf, 0, barsNeeded, rates);
   if(copied < lookback * 2 + 1)
      return;

   int swingCount = 0;

   // Scan from bar (lookback+1) to leave room for right-side confirmation
   // bar 0 is forming — start from bar (lookback) which is the earliest confirmed
   for(int i = lookback; i < copied - lookback && swingCount < MAX_SWINGS; i++)
   {
      // Check swing high
      bool isSwingHigh = true;
      for(int j = 1; j <= lookback; j++)
      {
         if(rates[i].high <= rates[i - j].high || rates[i].high <= rates[i + j].high)
         {
            isSwingHigh = false;
            break;
         }
      }
      if(isSwingHigh)
      {
         swings[swingCount].time     = rates[i].time;
         swings[swingCount].price    = rates[i].high;
         swings[swingCount].is_high  = true;
         swingCount++;
      }

      // Check swing low
      bool isSwingLow = true;
      for(int j = 1; j <= lookback; j++)
      {
         if(rates[i].low >= rates[i - j].low || rates[i].low >= rates[i + j].low)
         {
            isSwingLow = false;
            break;
         }
      }
      if(isSwingLow && swingCount < MAX_SWINGS)
      {
         swings[swingCount].time     = rates[i].time;
         swings[swingCount].price    = rates[i].low;
         swings[swingCount].is_high  = false;
         swingCount++;
      }
   }

   // Store count in first unused slot (using time=0 as sentinel)
   if(swingCount < MAX_SWINGS)
      swings[swingCount].time = 0; // sentinel
}

//+------------------------------------------------------------------+
//| ClassifyStructure — HH/HL/LH/LL from recent swing points         |
//|                                                                   |
//| Needs at least 2 swing highs and 2 swing lows for classification.|
//| Returns: STRUCT_BULLISH, STRUCT_BEARISH, or STRUCT_RANGE          |
//+------------------------------------------------------------------+
MARKET_STRUCTURE ClassifyStructure(const SwingPoint &swings[])
{
   // Collect recent highs and lows (sorted by time, newest first)
   double recentHighs[];
   double recentLows[];
   ArrayResize(recentHighs, 0);
   ArrayResize(recentLows, 0);

   for(int i = 0; i < MAX_SWINGS && swings[i].time != 0; i++)
   {
      if(swings[i].is_high)
      {
         int sz = ArraySize(recentHighs);
         if(sz < 4)
         {
            ArrayResize(recentHighs, sz + 1);
            recentHighs[sz] = swings[i].price;
         }
      }
      else
      {
         int sz = ArraySize(recentLows);
         if(sz < 4)
         {
            ArrayResize(recentLows, sz + 1);
            recentLows[sz] = swings[i].price;
         }
      }
      if(ArraySize(recentHighs) >= 2 && ArraySize(recentLows) >= 2)
         break;
   }

   // Need minimum 2 highs and 2 lows
   if(ArraySize(recentHighs) < 2 || ArraySize(recentLows) < 2)
      return STRUCT_RANGE;

   // recentHighs[0] = most recent high, recentHighs[1] = previous high
   bool higherHigh = recentHighs[0] > recentHighs[1];
   bool higherLow  = recentLows[0]  > recentLows[1];
   bool lowerHigh  = recentHighs[0] < recentHighs[1];
   bool lowerLow   = recentLows[0]  < recentLows[1];

   if(higherHigh && higherLow)
      return STRUCT_BULLISH;
   if(lowerHigh && lowerLow)
      return STRUCT_BEARISH;

   return STRUCT_RANGE;
}

//+------------------------------------------------------------------+
//| DetectFVGs — Scan for new Fair Value Gaps                         |
//|                                                                   |
//| Scans from bar 1 backward. Bar 0 is forming — NEVER use.         |
//| FVG = gap between candle 1 and candle 3 wicks, with candle 2     |
//| close confirmation.                                               |
//| Series indexing: candle3=rates[i], candle2=rates[i+1],            |
//|                  candle1=rates[i+2]                                |
//+------------------------------------------------------------------+
void DetectFVGs()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   int barsToScan = Inp_BPRLookbackBars + 5;
   int copied = CopyRates(Inp_Symbol, Inp_Timeframe, 0, barsToScan, rates);
   if(copied < 5)
      return;

   // Get ATR for filter
   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(g_atrHandle, 0, 0, 3, atrBuf) < 1)
      return;

   double atr = atrBuf[1]; // ATR of last completed bar
   if(atr <= 0)
      return;

   g_currentATR = atr; // Store globally for DetectBPRs / ExecuteTrade

   // ATR multiplier by filter tier
   double atrMultipliers[] = {0.1, 0.2, 0.3, 0.5};
   int tier = MathMax(0, MathMin(3, Inp_FVGFilterTier));
   double minGapSize = atr * atrMultipliers[tier];

   // Scan from bar 1 (last completed) backward
   // Need i+2 to exist, so max i = copied - 3
   for(int i = 1; i <= MathMin(Inp_BPRLookbackBars, copied - 3); i++)
   {
      datetime candle2Time = rates[i + 1].time;

      // Skip if candles not temporally consecutive (weekend/holiday gap)
      if(!IsTemporallyConsecutive(rates[i].time, rates[i + 1].time, rates[i + 2].time))
         continue;

      // --- Bullish FVG ---
      // Condition: Low[candle3] > High[candle1] AND Close[candle2] > High[candle1]
      double c3Low  = rates[i].low;        // candle 3 (newest)
      double c1High = rates[i + 2].high;   // candle 1 (oldest)
      double c2Close = rates[i + 1].close; // candle 2 (middle)

      if(c3Low > c1High && c2Close > c1High)
      {
         double gapSize = c3Low - c1High;
         if(gapSize >= minGapSize)
         {
            // Check dedup — is this FVG already stored?
            if(!FVGExists(g_bullFVGs, g_bullFVGCount, candle2Time))
            {
               if(g_bullFVGCount >= MAX_FVGS)
                  AgeFVGs(g_bullFVGs, g_bullFVGCount);

               if(g_bullFVGCount < MAX_FVGS)
               {
                  g_bullFVGs[g_bullFVGCount].time        = candle2Time;
                  g_bullFVGs[g_bullFVGCount].high_bound   = c3Low;    // top of gap
                  g_bullFVGs[g_bullFVGCount].low_bound    = c1High;   // bottom of gap
                  g_bullFVGs[g_bullFVGCount].direction     = DIR_BULL;
                  g_bullFVGs[g_bullFVGCount].active        = true;
                  g_bullFVGs[g_bullFVGCount].bpr_checked   = false;
                  g_bullFVGs[g_bullFVGCount].day_date      = GetDayStart(candle2Time);
                  g_bullFVGCount++;
               }
            }
         }
      }

      // --- Bearish FVG ---
      // Condition: High[candle3] < Low[candle1] AND Close[candle2] < Low[candle1]
      double c3High = rates[i].high;       // candle 3 (newest)
      double c1Low  = rates[i + 2].low;    // candle 1 (oldest)

      if(c3High < c1Low && c2Close < c1Low)
      {
         double gapSize = c1Low - c3High;
         if(gapSize >= minGapSize)
         {
            if(!FVGExists(g_bearFVGs, g_bearFVGCount, candle2Time))
            {
               if(g_bearFVGCount >= MAX_FVGS)
                  AgeFVGs(g_bearFVGs, g_bearFVGCount);

               if(g_bearFVGCount < MAX_FVGS)
               {
                  g_bearFVGs[g_bearFVGCount].time        = candle2Time;
                  g_bearFVGs[g_bearFVGCount].high_bound   = c1Low;    // top of gap
                  g_bearFVGs[g_bearFVGCount].low_bound    = c3High;   // bottom of gap
                  g_bearFVGs[g_bearFVGCount].direction     = DIR_BEAR;
                  g_bearFVGs[g_bearFVGCount].active        = true;
                  g_bearFVGs[g_bearFVGCount].bpr_checked   = false;
                  g_bearFVGs[g_bearFVGCount].day_date      = GetDayStart(candle2Time);
                  g_bearFVGCount++;
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| DetectBPRs — Match overlapping opposite FVGs into BPRs            |
//|                                                                   |
//| On each new FVG, scan backward for opposite-direction FVGs        |
//| within lookback. BPR direction = last (most recent) FVG.          |
//+------------------------------------------------------------------+
void DetectBPRs()
{
   // Only check NEW (unchecked) FVGs against existing opposites
   // This prevents O(N^2) re-scanning every bar
   for(int b = 0; b < g_bullFVGCount; b++)
   {
      if(!g_bullFVGs[b].active) continue;
      bool bullIsNew = !g_bullFVGs[b].bpr_checked;
      g_bullFVGs[b].bpr_checked = true;

      for(int s = 0; s < g_bearFVGCount; s++)
      {
         if(!g_bearFVGs[s].active) continue;
         bool bearIsNew = !g_bearFVGs[s].bpr_checked;

         // Only check if at least one FVG is new (unchecked)
         if(!bullIsNew && !bearIsNew) continue;

         // Check overlap
         double bpr_low  = MathMax(g_bullFVGs[b].low_bound, g_bearFVGs[s].low_bound);
         double bpr_high = MathMin(g_bullFVGs[b].high_bound, g_bearFVGs[s].high_bound);

         if(bpr_high <= bpr_low)
            continue; // no overlap

         // Check minimum BPR width (overlap zone)
         double bprWidth = bpr_high - bpr_low;
         if(Inp_BPRMinRangePoints > 0)
         {
            if(bprWidth < Inp_BPRMinRangePoints * g_symPoint)
               continue;
         }
         else if(g_currentATR > 0)
         {
            // Auto mode: minimum overlap = 0.15x ATR
            if(bprWidth < g_currentATR * 0.15)
               continue;
         }

         // Check if within lookback (time-based)
         datetime newerTime = MathMax(g_bullFVGs[b].time, g_bearFVGs[s].time);
         datetime olderTime = MathMin(g_bullFVGs[b].time, g_bearFVGs[s].time);
         int barsBetween = Bars(Inp_Symbol, Inp_Timeframe, olderTime, newerTime);
         if(barsBetween > Inp_BPRLookbackBars)
            continue;

         // Check CleanBPROnly — both FVGs must be untested
         if(Inp_CleanBPROnly)
         {
            // For now, active = untested (lifecycle tracking can be expanded)
            if(!g_bullFVGs[b].active || !g_bearFVGs[s].active)
               continue;
         }

         // Check if this BPR already exists (by matching FVG times)
         if(BPRExistsForFVGs(g_bullFVGs[b].time, g_bearFVGs[s].time))
            continue;

         // Determine direction: last (most recent) FVG determines
         int direction;
         if(g_bullFVGs[b].time > g_bearFVGs[s].time)
            direction = DIR_BULL;  // bullish FVG came last → bullish BPR → LONG
         else
            direction = DIR_BEAR;  // bearish FVG came last → bearish BPR → SHORT

         // Full BPR bounds (PATCH 2 — SL at extreme of entire BPR)
         double full_low  = MathMin(g_bullFVGs[b].low_bound, g_bearFVGs[s].low_bound);
         double full_high = MathMax(g_bullFVGs[b].high_bound, g_bearFVGs[s].high_bound);

         // Check max active BPRs
         if(CountActiveBPRs() >= Inp_MaxActiveBPRs)
            continue;

         // Create BPR
         if(g_bprCount >= MAX_BPRS)
         {
            // Remove oldest inactive BPR to make room
            RemoveOldestInactiveBPR();
         }
         if(g_bprCount < MAX_BPRS)
         {
            g_bprIdCounter++;
            g_bprs[g_bprCount].high_bound   = bpr_high;
            g_bprs[g_bprCount].low_bound    = bpr_low;
            g_bprs[g_bprCount].full_high    = full_high;
            g_bprs[g_bprCount].full_low     = full_low;
            g_bprs[g_bprCount].direction    = direction;
            g_bprs[g_bprCount].active       = true;
            g_bprs[g_bprCount].used         = false;  // PATCH 1
            g_bprs[g_bprCount].formed_date  = GetDayStart(newerTime); // PATCH 3
            g_bprs[g_bprCount].left_time    = olderTime;
            g_bprs[g_bprCount].right_time   = newerTime;
            g_bprs[g_bprCount].box_name     = "BPR_" + IntegerToString(g_bprIdCounter);

            LogMessage(StringFormat("BPR created: %s dir=%s zone=[%.5f - %.5f] full=[%.5f - %.5f]",
                       g_bprs[g_bprCount].box_name,
                       (direction == DIR_BULL ? "BULL" : "BEAR"),
                       bpr_low, bpr_high, full_low, full_high));

            if(Inp_DrawBPRBoxes)
               DrawBPRBox(g_bprCount);

            g_bprCount++;
         }
      }
   }

   // Mark all bear FVGs as checked
   for(int s = 0; s < g_bearFVGCount; s++)
      g_bearFVGs[s].bpr_checked = true;
}

//+------------------------------------------------------------------+
//| ValidateBPRs — Invalidate breached, expire end-of-day (PATCH 3)  |
//|                                                                   |
//| Close-through invalidation: wick-through + close-inside = OK.     |
//| Daily expiry: BPR formed on a different trading day → expired.    |
//+------------------------------------------------------------------+
void ValidateBPRs()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(Inp_Symbol, Inp_Timeframe, 0, 2, rates) < 2)
      return;

   double prevClose = rates[1].close; // last completed bar close
   datetime currentTime = rates[1].time;
   datetime currentDay  = GetDayStart(currentTime);

   for(int i = 0; i < g_bprCount; i++)
   {
      if(!g_bprs[i].active) continue;

      // PATCH 3: Daily expiry — BPR formed on different trading day
      if(currentDay > g_bprs[i].formed_date)
      {
         g_bprs[i].active = false;
         LogMessage(StringFormat("BPR expired (daily): %s", g_bprs[i].box_name));

         if(Inp_DeleteInvalidBPR)
            DeleteBPRBox(i);
         else
            UpdateBPRBoxStyle(i); // change to dotted/gray

         continue;
      }

      // Close-through invalidation
      if(g_bprs[i].direction == DIR_BULL && prevClose < g_bprs[i].low_bound)
      {
         g_bprs[i].active = false;
         LogMessage(StringFormat("BPR invalidated (close below): %s", g_bprs[i].box_name));

         if(Inp_DeleteInvalidBPR)
            DeleteBPRBox(i);
         else
            UpdateBPRBoxStyle(i);
      }
      else if(g_bprs[i].direction == DIR_BEAR && prevClose > g_bprs[i].high_bound)
      {
         g_bprs[i].active = false;
         LogMessage(StringFormat("BPR invalidated (close above): %s", g_bprs[i].box_name));

         if(Inp_DeleteInvalidBPR)
            DeleteBPRBox(i);
         else
            UpdateBPRBoxStyle(i);
      }
   }
}

//+------------------------------------------------------------------+
//| CheckEntry — Price in BPR + structure + session + not used        |
//|                                                                   |
//| Entry conditions:                                                 |
//| 1. Previous bar close is within BPR zone                          |
//| 2. Market structure aligns (bull struct + bull BPR or vice versa) |
//| 3. HTF structure is not Range                                     |
//| 4. BPR is not used (PATCH 1)                                     |
//| 5. Session is not blocked                                         |
//| 6. No existing position (unless AllowMultiple)                    |
//+------------------------------------------------------------------+
void CheckEntry()
{
   // Session check
   if(Inp_AsiaEnabled && IsAsiaSession())
      return;

   // HTF structure check — if Range, skip all trades
   if(g_htfStructure == STRUCT_RANGE)
      return;

   // Position check
   if(!Inp_AllowMultiplePos && HasOpenPosition())
      return;

   // Get last 3 bars for setup-trigger pattern
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(Inp_Symbol, Inp_Timeframe, 0, 3, rates) < 3)
      return;

   // Scan BPRs for entry signals
   for(int i = 0; i < g_bprCount; i++)
   {
      if(!g_bprs[i].active) continue;
      if(g_bprs[i].used)    continue; // PATCH 1

      // Setup: bar[1] or bar[2] CLOSE was inside BPR zone
      bool bar1InZone = (rates[1].close >= g_bprs[i].low_bound &&
                         rates[1].close <= g_bprs[i].high_bound);
      bool bar2InZone = (rates[2].close >= g_bprs[i].low_bound &&
                         rates[2].close <= g_bprs[i].high_bound);
      if(!bar1InZone && !bar2InZone)
         continue;

      // Trigger: bar[1] must show reversal direction (rejection candle)
      if(g_bprs[i].direction == DIR_BULL && rates[1].close <= rates[1].open)
         continue;
      if(g_bprs[i].direction == DIR_BEAR && rates[1].close >= rates[1].open)
         continue;

      // If setup was bar[2], bar[1] close must be near zone (within 1x zone width)
      if(!bar1InZone)
      {
         double zoneWidth = g_bprs[i].high_bound - g_bprs[i].low_bound;
         if(g_bprs[i].direction == DIR_BULL && rates[1].close > g_bprs[i].high_bound + zoneWidth)
            continue;
         if(g_bprs[i].direction == DIR_BEAR && rates[1].close < g_bprs[i].low_bound - zoneWidth)
            continue;
      }

      // Structure alignment — HTF must match, entry TF must not contradict
      if(g_bprs[i].direction == DIR_BULL)
      {
         if(g_htfStructure != STRUCT_BULLISH)
            continue;
         if(g_entryStructure == STRUCT_BEARISH)
            continue;
      }
      else
      {
         if(g_htfStructure != STRUCT_BEARISH)
            continue;
         if(g_entryStructure == STRUCT_BULLISH)
            continue;
      }

      // All conditions met — execute trade
      ExecuteTrade(i);

      // Only one trade per tick cycle
      if(!Inp_AllowMultiplePos)
         return;
   }
}

//+------------------------------------------------------------------+
//| CalculatePositionSize — Risk-based lot sizing                     |
//|                                                                   |
//| Fresh SYMBOL_TRADE_TICK_VALUE per trade (NEVER cache).            |
//| MathFloor for lots (NEVER NormalizeDouble alone).                 |
//| OrderCalcProfit fallback if tickValue <= 0.                       |
//+------------------------------------------------------------------+
double CalculatePositionSize(double slDistancePrice)
{
   if(slDistancePrice <= 0)
      return 0;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * Inp_RiskFractionEquity;

   // Fresh tick value
   double tickValue = SymbolInfoDouble(Inp_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(Inp_Symbol, SYMBOL_TRADE_TICK_SIZE);

   // Fallback if tickValue invalid
   if(tickValue <= 0 || tickSize <= 0)
   {
      // Use OrderCalcProfit as fallback
      double profit = 0;
      double price = SymbolInfoDouble(Inp_Symbol, SYMBOL_ASK);
      if(OrderCalcProfit(ORDER_TYPE_BUY, Inp_Symbol, 1.0, price, price + tickSize, profit))
      {
         tickValue = MathAbs(profit);
      }
      else
      {
         LogMessage("ERROR: Cannot determine tick value. Skipping trade.");
         return 0;
      }
   }

   // SL value per lot
   double slValuePerLot = (slDistancePrice / tickSize) * tickValue;
   if(slValuePerLot <= 0)
      return 0;

   double rawLots = riskMoney / slValuePerLot;

   // Clamp to symbol constraints
   double lotMin  = SymbolInfoDouble(Inp_Symbol, SYMBOL_VOLUME_MIN);
   double lotMax  = SymbolInfoDouble(Inp_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(Inp_Symbol, SYMBOL_VOLUME_STEP);

   if(lotStep <= 0)
      lotStep = 0.01;

   // MathFloor — NEVER round up (NormalizeDouble can round up)
   rawLots = MathFloor(rawLots / lotStep) * lotStep;

   // Clamp
   if(rawLots < lotMin)
   {
      LogMessage(StringFormat("Position size %.4f below minimum %.4f. Skipping trade.", rawLots, lotMin));
      return 0;
   }
   if(rawLots > lotMax)
      rawLots = lotMax;

   return rawLots;
}

//+------------------------------------------------------------------+
//| ExecuteTrade — Place order, mark BPR used, handle retcodes        |
//|                                                                   |
//| SL at BPR full extremes (PATCH 2).                                |
//| Mark BPR used immediately (PATCH 1).                              |
//+------------------------------------------------------------------+
void ExecuteTrade(int bprIdx)
{
   double buffer = Inp_SLBufferPoints * g_symPoint;
   double sl, tp, entry;
   double slDistance;

   if(g_bprs[bprIdx].direction == DIR_BULL)
   {
      // LONG
      entry = SymbolInfoDouble(Inp_Symbol, SYMBOL_ASK);
      sl = g_bprs[bprIdx].full_low - buffer; // PATCH 2: full extent
      slDistance = entry - sl;
      tp = entry + slDistance * Inp_RR;
   }
   else
   {
      // SHORT
      entry = SymbolInfoDouble(Inp_Symbol, SYMBOL_BID);
      sl = g_bprs[bprIdx].full_high + buffer; // PATCH 2: full extent
      slDistance = sl - entry;
      tp = entry - slDistance * Inp_RR;
   }

   if(slDistance <= 0)
   {
      LogMessage("ERROR: Invalid SL distance. Skipping trade.");
      return;
   }

   // Minimum SL distance: at least 0.2x ATR to prevent tiny-SL/huge-lot trades
   if(g_currentATR > 0 && slDistance < g_currentATR * 0.2)
   {
      LogMessage(StringFormat("SL distance %.5f too small (min %.5f = 0.2x ATR). Skipping.", slDistance, g_currentATR * 0.2));
      return;
   }

   // Check SYMBOL_TRADE_STOPS_LEVEL
   int stopsLevel = (int)SymbolInfoInteger(Inp_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minStopDist = stopsLevel * g_symPoint;
   if(slDistance < minStopDist)
   {
      LogMessage(StringFormat("SL distance %.5f below stops level %.5f. Skipping.", slDistance, minStopDist));
      return;
   }

   // Calculate position size
   double lots = CalculatePositionSize(slDistance);
   if(lots <= 0)
      return;

   // Normalize prices
   sl = NormalizeDouble(sl, g_symDigits);
   tp = NormalizeDouble(tp, g_symDigits);

   // Execute with retry for requote/price_changed
   bool success = false;
   int maxRetries = 3;

   for(int attempt = 0; attempt < maxRetries; attempt++)
   {
      bool result;
      if(g_bprs[bprIdx].direction == DIR_BULL)
      {
         entry = SymbolInfoDouble(Inp_Symbol, SYMBOL_ASK);
         result = g_trade.Buy(lots, Inp_Symbol, entry, sl, tp,
                              g_bprs[bprIdx].box_name);
      }
      else
      {
         entry = SymbolInfoDouble(Inp_Symbol, SYMBOL_BID);
         result = g_trade.Sell(lots, Inp_Symbol, entry, sl, tp,
                               g_bprs[bprIdx].box_name);
      }

      uint retcode = g_trade.ResultRetcode();

      if(retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_PLACED)
      {
         success = true;
         break;
      }

      // Retry-able errors
      if(retcode == TRADE_RETCODE_REQUOTE || retcode == TRADE_RETCODE_PRICE_CHANGED)
      {
         LogMessage(StringFormat("Retcode %d on attempt %d. Retrying...", retcode, attempt + 1));
         Sleep(100);
         continue;
      }

      // Non-retryable errors
      LogMessage(StringFormat("Trade failed. Retcode=%d: %s", retcode, g_trade.ResultRetcodeDescription()));
      break;
   }

   if(success)
   {
      // PATCH 1: Mark BPR as used immediately
      g_bprs[bprIdx].used = true;

      // Update visual
      if(Inp_DrawBPRBoxes)
      {
         UpdateBPRBoxStyle(bprIdx);
         DrawTradeMarkers(bprIdx, entry, sl, tp, lots);
      }

      LogMessage(StringFormat("TRADE EXECUTED: %s %s %.4f lots @ %.5f SL=%.5f TP=%.5f BPR=%s",
                 (g_bprs[bprIdx].direction == DIR_BULL ? "BUY" : "SELL"),
                 Inp_Symbol, lots, entry, sl, tp, g_bprs[bprIdx].box_name));
   }
}

//+------------------------------------------------------------------+
//| IsAsiaSession — UTC session check with midnight wraparound        |
//|                                                                   |
//| Converts server time to GMT using broker offset.                  |
//| Handles cases where start > end (midnight crossing).              |
//+------------------------------------------------------------------+
bool IsAsiaSession()
{
   datetime gmtTime = GetGMTTime();
   MqlDateTime dt;
   TimeToStruct(gmtTime, dt);

   int currentMinutes = dt.hour * 60 + dt.min;
   int startMinutes   = g_asiaStartHour * 60 + g_asiaStartMin;
   int endMinutes     = g_asiaEndHour * 60 + g_asiaEndMin;

   if(startMinutes <= endMinutes)
   {
      // Normal range: e.g., 00:00-09:00
      return (currentMinutes >= startMinutes && currentMinutes < endMinutes);
   }
   else
   {
      // Midnight wraparound: e.g., 22:00-07:00
      return (currentMinutes >= startMinutes || currentMinutes < endMinutes);
   }
}

//+------------------------------------------------------------------+
//| GetGMTTime — Tester-aware GMT time                                |
//|                                                                   |
//| TimeGMT() is BROKEN in Strategy Tester (returns TimeCurrent).     |
//| Use broker offset workaround in tester mode.                      |
//+------------------------------------------------------------------+
datetime GetGMTTime()
{
   if(MQLInfoInteger(MQL_TESTER))
   {
      int offset = GetBrokerGMTOffset();
      return TimeCurrent() - offset * 3600;
   }
   return TimeGMT();
}

//+------------------------------------------------------------------+
//| GetBrokerGMTOffset — DST-aware broker offset                      |
//|                                                                   |
//| Most brokers follow EU DST: last Sunday of March → summer,        |
//| last Sunday of October → winter.                                  |
//+------------------------------------------------------------------+
int GetBrokerGMTOffset()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   // Simple DST detection: March-October = summer
   if(dt.mon >= 4 && dt.mon <= 9)
      return Inp_GMTOffsetSummer;

   // March: after last Sunday = summer
   if(dt.mon == 3)
   {
      int lastSunday = 31 - ((5 + 31 - 1) % 7); // approximate
      if(dt.day >= lastSunday)
         return Inp_GMTOffsetSummer;
   }

   // October: before last Sunday = summer
   if(dt.mon == 10)
   {
      int lastSunday = 31 - ((5 + 31 - 1) % 7); // approximate
      if(dt.day < lastSunday)
         return Inp_GMTOffsetSummer;
   }

   return Inp_GMTOffsetWinter;
}

//+------------------------------------------------------------------+
//| GetDayStart — Trading day boundary for PATCH 3                    |
//|                                                                   |
//| Returns midnight (00:00:00) of the date portion.                  |
//+------------------------------------------------------------------+
datetime GetDayStart(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   return StructToTime(dt);
}

//+------------------------------------------------------------------+
//| DrawBPRBox — Create visual rectangle for BPR                      |
//+------------------------------------------------------------------+
void DrawBPRBox(int bprIdx)
{
   string name = g_bprs[bprIdx].box_name;
   color clr = (g_bprs[bprIdx].direction == DIR_BULL) ? Inp_BullBPRColor : Inp_BearBPRColor;

   datetime rightEdge = TimeCurrent() + PeriodSeconds(Inp_Timeframe) * 10; // extend right

   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);

   ObjectCreate(0, name, OBJ_RECTANGLE, 0,
                g_bprs[bprIdx].left_time, g_bprs[bprIdx].high_bound,
                rightEdge, g_bprs[bprIdx].low_bound);

   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetString(0, name, OBJPROP_TOOLTIP,
                   StringFormat("BPR %s [%.5f - %.5f]",
                               (g_bprs[bprIdx].direction == DIR_BULL ? "BULL" : "BEAR"),
                               g_bprs[bprIdx].low_bound, g_bprs[bprIdx].high_bound));
}

//+------------------------------------------------------------------+
//| DeleteBPRBox — Remove visual rectangle                            |
//+------------------------------------------------------------------+
void DeleteBPRBox(int bprIdx)
{
   string name = g_bprs[bprIdx].box_name;
   if(name != "" && ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);
}

//+------------------------------------------------------------------+
//| UpdateBPRBoxStyle — Change appearance for used/expired BPRs       |
//+------------------------------------------------------------------+
void UpdateBPRBoxStyle(int bprIdx)
{
   string name = g_bprs[bprIdx].box_name;
   if(name == "" || ObjectFind(0, name) < 0)
      return;

   if(g_bprs[bprIdx].used)
   {
      // Extend box right edge to current time (trade entry point)
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, TimeCurrent());
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrGray);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   }
   else if(!g_bprs[bprIdx].active)
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrDarkGray);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_FILL, false);
   }
}

//+------------------------------------------------------------------+
//| DrawTradeMarkers — Entry arrow + SL/TP lines on chart             |
//|                                                                   |
//| Creates: arrow at entry, dashed lines at SL and TP                |
//| Colors: green arrow for buy, red for sell                         |
//| SL line = red dashed, TP line = blue dashed                       |
//+------------------------------------------------------------------+
void DrawTradeMarkers(int bprIdx, double entryPrice, double sl, double tp, double lots)
{
   string prefix = g_bprs[bprIdx].box_name + "_";
   datetime now = TimeCurrent();
   bool isBuy = (g_bprs[bprIdx].direction == DIR_BULL);

   // Entry arrow
   string arrowName = prefix + "Entry";
   if(ObjectFind(0, arrowName) >= 0) ObjectDelete(0, arrowName);
   ObjectCreate(0, arrowName, OBJ_ARROW, 0, now, entryPrice);
   ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, isBuy ? 233 : 234); // up/down arrow
   ObjectSetInteger(0, arrowName, OBJPROP_COLOR, isBuy ? clrLime : clrOrangeRed);
   ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 3);
   ObjectSetString(0, arrowName, OBJPROP_TOOLTIP,
                   StringFormat("%s %.4f lots @ %.2f", isBuy ? "BUY" : "SELL", lots, entryPrice));

   // SL line
   string slName = prefix + "SL";
   datetime slRight = now + PeriodSeconds(Inp_Timeframe) * 20;
   if(ObjectFind(0, slName) >= 0) ObjectDelete(0, slName);
   ObjectCreate(0, slName, OBJ_TREND, 0, now, sl, slRight, sl);
   ObjectSetInteger(0, slName, OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, slName, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, slName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, slName, OBJPROP_RAY_RIGHT, false);
   ObjectSetString(0, slName, OBJPROP_TOOLTIP, StringFormat("SL %.2f", sl));

   // TP line
   string tpName = prefix + "TP";
   if(ObjectFind(0, tpName) >= 0) ObjectDelete(0, tpName);
   ObjectCreate(0, tpName, OBJ_TREND, 0, now, tp, slRight, tp);
   ObjectSetInteger(0, tpName, OBJPROP_COLOR, clrDodgerBlue);
   ObjectSetInteger(0, tpName, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, tpName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, tpName, OBJPROP_RAY_RIGHT, false);
   ObjectSetString(0, tpName, OBJPROP_TOOLTIP, StringFormat("TP %.2f", tp));
}

//+------------------------------------------------------------------+
//| LogMessage — Structured logging                                   |
//+------------------------------------------------------------------+
void LogMessage(string msg)
{
   PrintFormat("[BPR %s] %s", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), msg);
}

//+------------------------------------------------------------------+
//| ParseSessionTime — Parse "HH:MM" string to hour and minute        |
//+------------------------------------------------------------------+
bool ParseSessionTime(string timeStr, int &hour, int &minute)
{
   int colonPos = StringFind(timeStr, ":");
   if(colonPos < 0)
      return false;

   hour   = (int)StringToInteger(StringSubstr(timeStr, 0, colonPos));
   minute = (int)StringToInteger(StringSubstr(timeStr, colonPos + 1));

   return (hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59);
}

//+------------------------------------------------------------------+
//| HasOpenPosition — Check if we have an open position               |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) > 0)
      {
         if(PositionGetInteger(POSITION_MAGIC) == Inp_MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == Inp_Symbol)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| FVGExists — Check if an FVG with this candle2 time already exists |
//+------------------------------------------------------------------+
bool FVGExists(const FVG &fvgs[], int count, datetime candle2Time)
{
   for(int i = 0; i < count; i++)
   {
      if(fvgs[i].time == candle2Time && fvgs[i].active)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| AgeFVGs — Remove oldest FVGs when array is full                   |
//+------------------------------------------------------------------+
void AgeFVGs(FVG &fvgs[], int &count)
{
   if(count <= 0)
      return;

   // Find oldest (inactive first, then oldest active)
   int removeIdx = -1;
   datetime oldestTime = TimeCurrent();

   // First try to remove inactive FVGs
   for(int i = 0; i < count; i++)
   {
      if(!fvgs[i].active && fvgs[i].time < oldestTime)
      {
         oldestTime = fvgs[i].time;
         removeIdx = i;
      }
   }

   // If all active, remove oldest active
   if(removeIdx < 0)
   {
      for(int i = 0; i < count; i++)
      {
         if(fvgs[i].time < oldestTime)
         {
            oldestTime = fvgs[i].time;
            removeIdx = i;
         }
      }
   }

   if(removeIdx >= 0 && removeIdx < count - 1)
   {
      // Shift remaining elements
      for(int i = removeIdx; i < count - 1; i++)
         fvgs[i] = fvgs[i + 1];
   }
   count--;
}

//+------------------------------------------------------------------+
//| BPRExistsForFVGs — Check if BPR already created from these FVGs   |
//+------------------------------------------------------------------+
bool BPRExistsForFVGs(datetime bullTime, datetime bearTime)
{
   // Use left_time and right_time to match
   datetime earlier = MathMin(bullTime, bearTime);
   datetime later   = MathMax(bullTime, bearTime);

   for(int i = 0; i < g_bprCount; i++)
   {
      if(g_bprs[i].left_time == earlier && g_bprs[i].right_time == later)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| CountActiveBPRs — Count active (not expired, not used) BPRs       |
//+------------------------------------------------------------------+
int CountActiveBPRs()
{
   int count = 0;
   for(int i = 0; i < g_bprCount; i++)
   {
      if(g_bprs[i].active && !g_bprs[i].used)
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| RemoveOldestInactiveBPR — Free a slot in the BPR array            |
//+------------------------------------------------------------------+
void RemoveOldestInactiveBPR()
{
   int removeIdx = -1;
   datetime oldestTime = TimeCurrent();

   for(int i = 0; i < g_bprCount; i++)
   {
      if(!g_bprs[i].active && g_bprs[i].formed_date < oldestTime)
      {
         oldestTime = g_bprs[i].formed_date;
         removeIdx = i;
      }
   }

   if(removeIdx < 0)
   {
      // All active — remove oldest used
      for(int i = 0; i < g_bprCount; i++)
      {
         if(g_bprs[i].used && g_bprs[i].formed_date < oldestTime)
         {
            oldestTime = g_bprs[i].formed_date;
            removeIdx = i;
         }
      }
   }

   if(removeIdx >= 0)
   {
      DeleteBPRBox(removeIdx);
      if(removeIdx < g_bprCount - 1)
      {
         for(int i = removeIdx; i < g_bprCount - 1; i++)
            g_bprs[i] = g_bprs[i + 1];
      }
      g_bprCount--;
   }
}

//+------------------------------------------------------------------+
//| IsTemporallyConsecutive — Check candles aren't across weekend gap  |
//+------------------------------------------------------------------+
bool IsTemporallyConsecutive(datetime t1, datetime t2, datetime t3)
{
   int period = PeriodSeconds(Inp_Timeframe);
   if(period <= 0)
      return true;

   // Allow up to 3x the expected interval (accounts for weekends, holidays)
   // A weekend gap would be ~48 hours for daily, ~2880x for M1
   // For M15 (900s), 3x = 2700s (45 min) — rejects weekend gaps
   int maxGap = period * 3;

   if(MathAbs((int)(t1 - t2)) > maxGap)
      return false;
   if(MathAbs((int)(t2 - t3)) > maxGap)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| OnTester — Custom optimization metric                             |
//|                                                                   |
//| 0.4 * ProfitFactor + 0.3 * Sharpe + 0.3 * RecoveryFactor         |
//+------------------------------------------------------------------+
double OnTester()
{
   double pf     = TesterStatistics(STAT_PROFIT_FACTOR);
   double sharpe = TesterStatistics(STAT_SHARPE_RATIO);
   double rf     = TesterStatistics(STAT_RECOVERY_FACTOR);

   // Clamp negative values to avoid pulling the metric down
   if(pf < 0)     pf = 0;
   if(sharpe < 0)  sharpe = 0;
   if(rf < 0)      rf = 0;

   return pf * 0.4 + sharpe * 0.3 + rf * 0.3;
}
//+------------------------------------------------------------------+

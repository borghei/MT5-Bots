//+------------------------------------------------------------------+
//|                                              BPR_Diagnostic.mq5  |
//|                        BPR Bot — Phase 0.5 Diagnostic Script     |
//|                                                                  |
//| PURPOSE: Print all broker/symbol properties needed for EA config |
//|          Run once on live chart, read output from Journal tab.   |
//|                                                                  |
//| USAGE: Drag this script onto any chart in MT5.                   |
//|        Output appears in Experts tab (Tools → Experts).          |
//+------------------------------------------------------------------+
#property copyright "BPR Bot"
#property version   "1.00"
#property script_show_inputs

//--- Symbols to inspect
input string Inp_Symbols = "XAUUSD.ecn,BTCUSD,BTCUSD.ecn,XAUUSD,GOLD,XAUUSDm,BTCUSDm"; // Comma-separated symbol names to check

//+------------------------------------------------------------------+
//| Script program start function                                     |
//+------------------------------------------------------------------+
void OnStart()
{
   Print("=============================================================");
   Print("  BPR DIAGNOSTIC SCRIPT — Phase 0.5");
   Print("  Time: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
   Print("=============================================================");

   //--- Account Info
   PrintAccountInfo();

   //--- Time Info
   PrintTimeInfo();

   //--- Search for symbols containing XAU and BTC
   PrintSymbolSearch();

   //--- Specific symbol properties
   string symbols[];
   int count = StringSplit(Inp_Symbols, ',', symbols);
   for(int i = 0; i < count; i++)
   {
      string sym = symbols[i];
      StringTrimLeft(sym);
      StringTrimRight(sym);
      if(SymbolInfoInteger(sym, SYMBOL_EXIST))
         PrintSymbolProperties(sym);
      else
         Print("--- Symbol '", sym, "' does NOT exist on this broker ---");
   }

   //--- Also check chart symbol
   if(Symbol() != "")
   {
      Print("");
      Print("--- Chart Symbol: ", Symbol(), " ---");
      PrintSymbolProperties(Symbol());
   }

   Print("=============================================================");
   Print("  DIAGNOSTIC COMPLETE");
   Print("=============================================================");
}

//+------------------------------------------------------------------+
//| Print Account Information                                         |
//+------------------------------------------------------------------+
void PrintAccountInfo()
{
   Print("");
   Print("==================== ACCOUNT INFO ==========================");
   Print("  Login:            ", AccountInfoInteger(ACCOUNT_LOGIN));
   Print("  Server:           ", AccountInfoString(ACCOUNT_SERVER));
   Print("  Company:          ", AccountInfoString(ACCOUNT_COMPANY));
   Print("  Name:             ", AccountInfoString(ACCOUNT_NAME));
   Print("  Currency:         ", AccountInfoString(ACCOUNT_CURRENCY));
   Print("  Balance:          ", AccountInfoDouble(ACCOUNT_BALANCE));
   Print("  Equity:           ", AccountInfoDouble(ACCOUNT_EQUITY));
   Print("  Leverage:         1:", AccountInfoInteger(ACCOUNT_LEVERAGE));

   ENUM_ACCOUNT_MARGIN_MODE marginMode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   string modeStr = "UNKNOWN";
   if(marginMode == ACCOUNT_MARGIN_MODE_RETAIL_NETTING)
      modeStr = "NETTING";
   else if(marginMode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      modeStr = "HEDGING";
   else if(marginMode == ACCOUNT_MARGIN_MODE_EXCHANGE)
      modeStr = "EXCHANGE";
   Print("  Margin Mode:      ", modeStr, " (", (int)marginMode, ")");

   ENUM_ACCOUNT_TRADE_MODE tradeMode = (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   string tradeModeStr = "UNKNOWN";
   if(tradeMode == ACCOUNT_TRADE_MODE_DEMO)
      tradeModeStr = "DEMO";
   else if(tradeMode == ACCOUNT_TRADE_MODE_REAL)
      tradeModeStr = "REAL";
   else if(tradeMode == ACCOUNT_TRADE_MODE_CONTEST)
      tradeModeStr = "CONTEST";
   Print("  Trade Mode:       ", tradeModeStr, " (", (int)tradeMode, ")");

   Print("  Trade Allowed:    ", AccountInfoInteger(ACCOUNT_TRADE_ALLOWED));
   Print("  EA Trade Allowed: ", AccountInfoInteger(ACCOUNT_TRADE_EXPERT));
   Print("  Limit Orders:     ", AccountInfoInteger(ACCOUNT_LIMIT_ORDERS));
   Print("  Margin SO Mode:   ", AccountInfoInteger(ACCOUNT_MARGIN_SO_MODE));
   Print("  Margin SO Call:   ", AccountInfoDouble(ACCOUNT_MARGIN_SO_CALL), "%");
   Print("  Margin SO StopOut:", AccountInfoDouble(ACCOUNT_MARGIN_SO_SO), "%");
}

//+------------------------------------------------------------------+
//| Print Time Information                                            |
//+------------------------------------------------------------------+
void PrintTimeInfo()
{
   Print("");
   Print("==================== TIME INFO =============================");

   datetime serverTime = TimeCurrent();
   datetime gmtTime    = TimeGMT();
   datetime localTime  = TimeLocal();

   Print("  TimeCurrent():    ", TimeToString(serverTime, TIME_DATE|TIME_SECONDS));
   Print("  TimeGMT():        ", TimeToString(gmtTime, TIME_DATE|TIME_SECONDS));
   Print("  TimeLocal():      ", TimeToString(localTime, TIME_DATE|TIME_SECONDS));

   int serverGmtOffset = (int)(serverTime - gmtTime);
   Print("  Server-GMT Offset:", serverGmtOffset, " seconds = ", serverGmtOffset / 3600, " hours");

   int serverLocalOffset = (int)(serverTime - localTime);
   Print("  Server-Local Offset: ", serverLocalOffset, " seconds = ", serverLocalOffset / 3600, " hours");

   Print("  NOTE: If running in Tester, TimeGMT() returns same as TimeCurrent()");
   Print("  NOTE: Current offset tells us broker GMT offset (check DST season)");

   MqlDateTime dt;
   TimeToStruct(serverTime, dt);
   Print("  Current month:    ", dt.mon, " (Mar-Oct is typically DST/summer)");

   // Determine if likely DST
   if(dt.mon >= 3 && dt.mon <= 10)
      Print("  Season:           Likely SUMMER (DST) — expect GMT+3 for EET brokers");
   else
      Print("  Season:           Likely WINTER — expect GMT+2 for EET brokers");
}

//+------------------------------------------------------------------+
//| Search for XAU and BTC symbols                                    |
//+------------------------------------------------------------------+
void PrintSymbolSearch()
{
   Print("");
   Print("==================== SYMBOL SEARCH =========================");

   int total = SymbolsTotal(false);  // false = all symbols, not just Market Watch
   Print("  Total symbols on broker: ", total);

   Print("");
   Print("  --- Symbols containing 'XAU' ---");
   int xauCount = 0;
   for(int i = 0; i < total; i++)
   {
      string name = SymbolName(i, false);
      if(StringFind(name, "XAU") >= 0 || StringFind(name, "xau") >= 0 ||
         StringFind(name, "GOLD") >= 0 || StringFind(name, "gold") >= 0)
      {
         Print("    ", name);
         xauCount++;
      }
   }
   if(xauCount == 0)
      Print("    (none found)");

   Print("");
   Print("  --- Symbols containing 'BTC' ---");
   int btcCount = 0;
   for(int i = 0; i < total; i++)
   {
      string name = SymbolName(i, false);
      if(StringFind(name, "BTC") >= 0 || StringFind(name, "btc") >= 0)
      {
         Print("    ", name);
         btcCount++;
      }
   }
   if(btcCount == 0)
      Print("    (none found)");
}

//+------------------------------------------------------------------+
//| Print detailed properties for a specific symbol                   |
//+------------------------------------------------------------------+
void PrintSymbolProperties(string sym)
{
   Print("");
   Print("==================== ", sym, " PROPERTIES ====================");

   // Basic info
   Print("  Description:      ", SymbolInfoString(sym, SYMBOL_DESCRIPTION));
   Print("  Path:             ", SymbolInfoString(sym, SYMBOL_PATH));
   Print("  Base Currency:    ", SymbolInfoString(sym, SYMBOL_CURRENCY_BASE));
   Print("  Profit Currency:  ", SymbolInfoString(sym, SYMBOL_CURRENCY_PROFIT));
   Print("  Margin Currency:  ", SymbolInfoString(sym, SYMBOL_CURRENCY_MARGIN));

   // Price info
   Print("  Digits:           ", SymbolInfoInteger(sym, SYMBOL_DIGITS));
   Print("  Point:            ", DoubleToString(SymbolInfoDouble(sym, SYMBOL_POINT), 10));
   Print("  Bid:              ", SymbolInfoDouble(sym, SYMBOL_BID));
   Print("  Ask:              ", SymbolInfoDouble(sym, SYMBOL_ASK));
   Print("  Spread (current): ", SymbolInfoInteger(sym, SYMBOL_SPREAD), " points");
   Print("  Spread Float:     ", SymbolInfoInteger(sym, SYMBOL_SPREAD_FLOAT));

   // Contract specs
   Print("  Contract Size:    ", SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE));
   Print("  Tick Size:        ", DoubleToString(SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE), 10));
   Print("  Tick Value:       ", DoubleToString(SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE), 10));
   Print("  Tick Value Profit:", DoubleToString(SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE_PROFIT), 10));
   Print("  Tick Value Loss:  ", DoubleToString(SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE_LOSS), 10));

   // Volume constraints
   Print("  Volume Min:       ", SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN));
   Print("  Volume Max:       ", SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX));
   Print("  Volume Step:      ", SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP));
   Print("  Volume Limit:     ", SymbolInfoDouble(sym, SYMBOL_VOLUME_LIMIT));

   // Trading modes
   ENUM_SYMBOL_TRADE_EXECUTION execMode = (ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(sym, SYMBOL_TRADE_EXEMODE);
   string execStr = "UNKNOWN";
   if(execMode == SYMBOL_TRADE_EXECUTION_REQUEST)    execStr = "REQUEST";
   else if(execMode == SYMBOL_TRADE_EXECUTION_INSTANT)    execStr = "INSTANT";
   else if(execMode == SYMBOL_TRADE_EXECUTION_MARKET)     execStr = "MARKET";
   else if(execMode == SYMBOL_TRADE_EXECUTION_EXCHANGE)   execStr = "EXCHANGE";
   Print("  Execution Mode:   ", execStr, " (", (int)execMode, ")");

   // Filling modes
   long fillFlags = SymbolInfoInteger(sym, SYMBOL_FILLING_MODE);
   string fillStr = "";
   if((fillFlags & SYMBOL_FILLING_FOK) != 0)   fillStr += "FOK ";
   if((fillFlags & SYMBOL_FILLING_IOC) != 0)   fillStr += "IOC ";
   if(fillStr == "") fillStr = "RETURN_ONLY";
   Print("  Filling Mode:     ", fillStr, " (flags=", fillFlags, ")");

   // Order modes
   long orderFlags = SymbolInfoInteger(sym, SYMBOL_ORDER_MODE);
   string orderStr = "";
   if((orderFlags & SYMBOL_ORDER_MARKET) != 0)          orderStr += "MARKET ";
   if((orderFlags & SYMBOL_ORDER_LIMIT) != 0)           orderStr += "LIMIT ";
   if((orderFlags & SYMBOL_ORDER_STOP) != 0)            orderStr += "STOP ";
   if((orderFlags & SYMBOL_ORDER_STOP_LIMIT) != 0)      orderStr += "STOP_LIMIT ";
   if((orderFlags & SYMBOL_ORDER_SL) != 0)              orderStr += "SL ";
   if((orderFlags & SYMBOL_ORDER_TP) != 0)              orderStr += "TP ";
   if((orderFlags & SYMBOL_ORDER_CLOSEBY) != 0)         orderStr += "CLOSEBY ";
   Print("  Order Modes:      ", orderStr, " (flags=", orderFlags, ")");

   // Stops
   Print("  Stops Level:      ", SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL), " points");
   Print("  Freeze Level:     ", SymbolInfoInteger(sym, SYMBOL_TRADE_FREEZE_LEVEL), " points");

   // Swaps
   ENUM_SYMBOL_SWAP_MODE swapMode = (ENUM_SYMBOL_SWAP_MODE)SymbolInfoInteger(sym, SYMBOL_SWAP_MODE);
   Print("  Swap Mode:        ", EnumToString(swapMode));
   Print("  Swap Long:        ", SymbolInfoDouble(sym, SYMBOL_SWAP_LONG));
   Print("  Swap Short:       ", SymbolInfoDouble(sym, SYMBOL_SWAP_SHORT));
   Print("  Swap Rollover3Day:", SymbolInfoInteger(sym, SYMBOL_SWAP_ROLLOVER3DAYS));

   // Session info
   Print("  Trade Mode:       ", EnumToString((ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(sym, SYMBOL_TRADE_MODE)));

   // Margin
   double marginInit = 0, marginMaint = 0;
   Print("  Initial Margin:   ", SymbolInfoDouble(sym, SYMBOL_MARGIN_INITIAL));
   Print("  Maint. Margin:    ", SymbolInfoDouble(sym, SYMBOL_MARGIN_MAINTENANCE));

   // Calc mode
   ENUM_SYMBOL_CALC_MODE calcMode = (ENUM_SYMBOL_CALC_MODE)SymbolInfoInteger(sym, SYMBOL_TRADE_CALC_MODE);
   Print("  Calc Mode:        ", EnumToString(calcMode));
}
//+------------------------------------------------------------------+

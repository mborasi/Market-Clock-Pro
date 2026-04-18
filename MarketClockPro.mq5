//+------------------------------------------------------------------+
//|                                               MarketClockPro.mq5 |
//|                                    Copyright (c) 2026, M. Borasi |
//|                                                https://jyxos.com |
//|                   Licensed under the Apache License, Version 2.0 |
//|                       http://www.apache.org/licenses/LICENSE-2.0 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Marcelo Borasi - JYXOS"
#property link      "https://jyxos.com"
#property version   "1.00"
#property description "Candle countdown HUD with session detection,"
#property description "spread monitor, daily range vs ADR, and"
#property description "global holidays calendar."

#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//+------------------------------------------------------------------+
//| ENUMS                                                            |
//+------------------------------------------------------------------+
enum ENUM_HUD_CORNER
  {
   HUD_TOP_RIGHT    = 0,  // Top Right
   HUD_TOP_LEFT     = 1,  // Top Left
   HUD_BOTTOM_RIGHT = 2,  // Bottom Right
   HUD_BOTTOM_LEFT  = 3   // Bottom Left
  };

enum ENUM_HUD_THEME
  {
   THEME_DARK    = 0,  // Dark Panel
   THEME_LIGHT   = 1,  // Light Panel
   THEME_STEALTH = 2   // No Panel (text only)
  };

enum ENUM_HOLIDAY_MARKET
  {
   MARKET_AUTO  = 0,  // Auto-detect from symbol
   MARKET_NYSE  = 1,  // US equities / futures (Nasdaq, S&P, Dow)
   MARKET_LSE   = 2,  // UK (FTSE)
   MARKET_XETRA = 3,  // Germany / Eurozone (DAX, STOXX)
   MARKET_TSE   = 4,  // Japan (Nikkei)
   MARKET_HKEX  = 5,  // Hong Kong (Hang Seng)
   MARKET_ASX   = 6,  // Australia (ASX200)
   MARKET_SSE   = 7,  // China (CSI, A50)
   MARKET_NONE  = 8   // Disable holiday check for this chart
  };

//+------------------------------------------------------------------+
//| INPUTS - DISPLAY                                                 |
//+------------------------------------------------------------------+
input group "====== DISPLAY ======"
input ENUM_HUD_CORNER  InpCorner             = HUD_TOP_RIGHT;   // HUD Position
input ENUM_HUD_THEME   InpTheme              = THEME_DARK;      // HUD Theme
input int              InpPrimaryFontSize    = 20;              // Primary Font Size (countdown)
input int              InpSecondaryFontSize  = 11;              // Secondary Font Size (all other lines)
input color            InpSecondaryColor     = clrDarkGray;     // Secondary Color (all other lines)

//+------------------------------------------------------------------+
//| INPUTS - MODULES                                                 |
//+------------------------------------------------------------------+
input group "====== MODULES ======"
input bool   InpShowTimeframe    = true;    // Show Timeframe Label
input bool   InpShowSession      = true;    // Show Trading Session
input bool   InpShowSpread       = true;    // Show Live Spread
input bool   InpShowADR          = true;    // Show Daily Range vs ADR

//+------------------------------------------------------------------+
//| INPUTS - BEHAVIOR                                                |
//+------------------------------------------------------------------+
input group "====== BEHAVIOR ======"
input int    InpADRPeriod           = 14;      // ADR Lookback (days)
input bool   InpMarketClosedAlert   = true;    // Detect symbol market closed
input bool   InpShowTimeToOpen      = false;   // Show countdown to next market open

//+------------------------------------------------------------------+
//| INPUTS - HOLIDAYS                                                |
//+------------------------------------------------------------------+
input group "====== HOLIDAYS ======"
input bool              InpHolidaysEnabled = false;   // Enable holidays.txt (otherwise use broker sessions only)
input string            InpHolidaysFile    = "MarketClockPro\\holidays.txt"; // Path under MQL5\\Files
input ENUM_HOLIDAY_MARKET InpHolidayMarket = MARKET_AUTO;   // Market for holiday lookup
input string            InpHolidayMarketOverride = "";  // Override when AUTO fails (NYSE/LSE/XETRA/TSE/HKEX/ASX/SSE)

//+------------------------------------------------------------------+
//| INPUTS - ALERT                                                   |
//+------------------------------------------------------------------+
input group "====== ALERT ======"
input bool   InpAlertEnabled    = false;    // Alert before candle close
input int    InpAlertSeconds    = 5;        // Seconds before close (1-60)

//+------------------------------------------------------------------+
//| HARDCODED CONSTANTS                                              |
//+------------------------------------------------------------------+
#define PREFIX                "SCT3_"
#define HUD_FONT              "Consolas"
#define HUD_X_OFFSET          12
#define HUD_Y_OFFSET          25
#define HUD_LINE_SPACING      4
#define SPREAD_HISTORY_SIZE   60
#define SPREAD_ANOMALY_MULT   2.0
#define OFFSET_REFRESH_SEC    3600
#define ALERT_SOUND           "alert.wav"

// Session hours (UTC) - ICE/CME standard
#define TOK_OPEN   0
#define TOK_CLOSE  9
#define LDN_OPEN   7
#define LDN_CLOSE  16
#define NY_OPEN    13
#define NY_CLOSE   22
#define SYD_OPEN   21
#define SYD_CLOSE  6

// Holiday file constants
#define HOL_MAX_ENTRIES       400        // 2 years x ~200 days max
#define HOL_MAGIC             "SCT_HOLIDAYS"
#define HOL_BANNER_DURATION   30          // seconds to show status banner after init

// Holiday status codes
#define HOL_STATUS_DISABLED   0
#define HOL_STATUS_OK         1
#define HOL_STATUS_MISSING    2
#define HOL_STATUS_CORRUPT    3
#define HOL_STATUS_OUTDATED   4

//+------------------------------------------------------------------+
//| GLOBAL STATE                                                     |
//+------------------------------------------------------------------+
long     g_chartID         = 0;
long     g_periodSec       = 0;
int      g_cornerCode      = 0;
int      g_anchor          = 0;
int      g_xBase           = 0;
int      g_yBase           = 0;
bool     g_initialized     = false;
bool     g_timerCreated    = false;

long     g_lastSecsLeft    = -999;
datetime g_lastBarTime     = 0;
bool     g_alertPlayed     = false;

int      g_alertSecs       = 5;

// Colors
color    g_accentColor     = clrLime;
color    g_clrPanel        = C'15,15,20';
color    g_clrBorder       = C'45,45,60';
color    g_clrWarn         = C'239,83,80';
color    g_clrCaution      = C'255,167,38';
color    g_clrMarketClosed = C'239,83,80';

// ADR cache
double   g_adrValue        = 0;
datetime g_adrLastCalc     = 0;

// Session cache
int      g_sessLastMinute  = -1;
int      g_sessLastHour    = -1;
string   g_sessCache       = "CLOSED";
string   g_sessSubCache    = "";          // secondary line (e.g. "Opens in 2h15m")
bool     g_marketOpen      = true;

// Broker UTC offset
int      g_brokerOffsetSec = 0;
datetime g_lastOffsetCheck = 0;

// D1 data availability
bool     g_d1DataReady     = false;

// Module flags
bool     g_objTF           = false;
bool     g_objSess         = false;
bool     g_objSpr          = false;
bool     g_objADR          = false;

// Object names
string   g_panelBgName;
string   g_panelBorderName;

// Dedup state
string   g_lastTimerText   = "";
color    g_lastTimerColor  = 0;
string   g_lastSessText    = "";
color    g_lastSessColor   = 0;
string   g_lastSessSubText = "";
color    g_lastSessSubColor = 0;
long     g_lastSpread      = -1;
string   g_lastSpreadText  = "";
color    g_lastSpreadColor = 0;
string   g_lastADRText     = "";
string   g_lastStatusText  = "";
string   g_lastStatusSubText = "";

// Spread rolling window
long     g_spreadHistory[SPREAD_HISTORY_SIZE];
int      g_spreadHistIdx   = 0;
int      g_spreadHistCount = 0;

// Holidays database (in-memory after parse)
int       g_holStatus      = HOL_STATUS_DISABLED;
datetime  g_holDates[HOL_MAX_ENTRIES];
string    g_holMarkets[HOL_MAX_ENTRIES];
int       g_holCount       = 0;
datetime  g_holCoverageFrom = 0;
datetime  g_holCoverageTo   = 0;
string    g_holStatusMsg   = "";
datetime  g_holStatusShownUntil = 0;
string    g_symbolMarket   = "";  // auto-detected market for current symbol

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   IndicatorSetString(INDICATOR_SHORTNAME, "Market Clock Pro v1.0");

   g_chartID   = ChartID();
   g_periodSec = PeriodSeconds();

//--- validate period
   if(g_periodSec <= 0)
     {
      Print("MarketClockPro: invalid period, aborting init.");
      return INIT_FAILED;
     }

//--- reset banner state (avoid stale state on reinit)
   g_holStatusMsg        = "";
   g_holStatusShownUntil = 0;

//--- clamp alert seconds
   g_alertSecs = InpAlertSeconds;
   if(g_alertSecs < 1)
      g_alertSecs = 1;
   if(g_alertSecs > 60)
      g_alertSecs = 60;

//--- init spread rolling window
   ArrayInitialize(g_spreadHistory, 0);
   g_spreadHistIdx   = 0;
   g_spreadHistCount = 0;

//--- compute broker-UTC offset
   ComputeBrokerOffset();
   g_lastOffsetCheck = TimeTradeServer();

//--- prepare HUD geometry and colors
   CleanupObjects();
   ComputeCorner();
   ComputeAccentColor();
   ComputePanelColors();

//--- resolve market for holiday lookups
   g_symbolMarket = ResolveHolidayMarket();

//--- load holidays file if enabled
   g_holCount  = 0;
   g_holStatus = HOL_STATUS_DISABLED;
   if(InpHolidaysEnabled && InpHolidayMarket != MARKET_NONE)
     {
      LoadHolidaysFile();
     }

//--- reset runtime state before BuildHUD (labels seed dedup from here)
   g_lastBarTime      = 0;
   g_lastSecsLeft     = -999;
   g_alertPlayed      = false;
   g_adrLastCalc      = 0;
   g_adrValue         = 0;
   g_sessLastHour     = -1;
   g_sessLastMinute   = -1;
   g_sessCache        = "CLOSED";
   g_sessSubCache     = "";
   g_d1DataReady      = false;
   g_marketOpen       = true;
   g_lastTimerText    = "";
   g_lastTimerColor   = 0;
   g_lastSessText     = "";
   g_lastSessColor    = 0;
   g_lastSessSubText  = "";
   g_lastSessSubColor = 0;
   g_lastSpread       = -1;
   g_lastSpreadText   = "";
   g_lastSpreadColor  = 0;
   g_lastADRText      = "";
   g_lastStatusText   = "";
   g_lastStatusSubText = "";

//--- build HUD objects
   if(!BuildHUD())
      return INIT_FAILED;

//--- cache module flags
   g_objTF   = InpShowTimeframe;
   g_objSess = InpShowSession;
   g_objSpr  = InpShowSpread;
   g_objADR  = InpShowADR;

//--- start render timer
   StartTimer();

//--- warn only for index-like tickers (skip FX/crypto/metals)
   if(InpHolidaysEnabled &&
      InpHolidayMarket == MARKET_AUTO &&
      StringLen(g_symbolMarket) == 0 &&
      IsSymbolEligibleForHolidays(Symbol()))
     {
      g_holStatusMsg = "HOLIDAYS|symbol not mapped";
      Print("MarketClockPro: symbol '", Symbol(),
            "' not auto-mapped. Set InpHolidayMarket or InpHolidayMarketOverride.");
     }

   if(StringLen(g_holStatusMsg) > 0)
      g_holStatusShownUntil = TimeCurrent() + HOL_BANNER_DURATION;

//--- initial render
   g_initialized = true;
   RefreshHUD();

//--- log startup summary
   string marketLabel = (StringLen(g_symbolMarket) > 0) ? g_symbolMarket : "none";
   string marketSource = "";
   if(InpHolidayMarket == MARKET_AUTO)
      marketSource = (StringLen(g_symbolMarket) > 0) ? "auto" : "unresolved";
   else
      if(InpHolidayMarket == MARKET_NONE)
         marketSource = "disabled";
      else
         marketSource = "manual";

   Print("Market Clock Pro v1.0 | ", Symbol(), " ", EnumToString(Period()),
         " | BrokerUTC: ", g_brokerOffsetSec / 3600, "h",
         " | Market: ", marketLabel, " (", marketSource, ")",
         " | Holidays: ", HolidayStatusText());

   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| ComputeBrokerOffset                                              |
//+------------------------------------------------------------------+
void ComputeBrokerOffset()
  {
   datetime serverTime = TimeTradeServer();
   datetime gmtTime    = TimeGMT();

   g_brokerOffsetSec = (int)((long)serverTime - (long)gmtTime);

   if(g_brokerOffsetSec < -43200)
      g_brokerOffsetSec = 0;
   if(g_brokerOffsetSec > 50400)
      g_brokerOffsetSec = 0;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
datetime GetCurrentUTCTime()
  {
   return TimeTradeServer() - g_brokerOffsetSec;
  }

//+------------------------------------------------------------------+
//| MarketCodeToString - Convert enum to market string used in file  |
//+------------------------------------------------------------------+
string MarketCodeToString(ENUM_HOLIDAY_MARKET m)
  {
   switch(m)
     {
      case MARKET_NYSE:
         return "NYSE";
      case MARKET_LSE:
         return "LSE";
      case MARKET_XETRA:
         return "XETRA";
      case MARKET_TSE:
         return "TSE";
      case MARKET_HKEX:
         return "HKEX";
      case MARKET_ASX:
         return "ASX";
      case MARKET_SSE:
         return "SSE";
     }
   return "";
  }

//+------------------------------------------------------------------+
//| NormalizeMarketString - Uppercase and validate against known set |
//| Returns "" if not a valid market code.                           |
//+------------------------------------------------------------------+
string NormalizeMarketString(const string raw)
  {
   string s = raw;
   StringToUpper(s);
// Trim spaces
   StringTrimLeft(s);
   StringTrimRight(s);

   if(s == "NYSE" || s == "LSE"  || s == "XETRA" ||
      s == "TSE"  || s == "HKEX" || s == "ASX"   || s == "SSE")
      return s;

   return "";
  }

//+------------------------------------------------------------------+
//| ResolveHolidayMarket                                              |
//| Priority: explicit enum > AUTO ticker detect > override string.   |
//+------------------------------------------------------------------+
string ResolveHolidayMarket()
  {
   if(InpHolidayMarket == MARKET_NONE)
      return "";

   if(InpHolidayMarket != MARKET_AUTO)
      return MarketCodeToString(InpHolidayMarket);

   string autoDet = DetectMarketForSymbol(Symbol());
   if(StringLen(autoDet) > 0)
      return autoDet;

   if(StringLen(InpHolidayMarketOverride) > 0)
     {
      string ovrStr = NormalizeMarketString(InpHolidayMarketOverride);
      if(StringLen(ovrStr) > 0)
         return ovrStr;

      Print("MarketClockPro: InpHolidayMarketOverride='", InpHolidayMarketOverride,
            "' invalid. Expected NYSE/LSE/XETRA/TSE/HKEX/ASX/SSE.");
     }

   return "";
  }

//+------------------------------------------------------------------+
//| IsSymbolEligibleForHolidays                                       |
//| True for index/equity tickers. False for FX, crypto, metals,      |
//| commodities. Used to gate the "symbol not mapped" warning.        |
//+------------------------------------------------------------------+
bool IsSymbolEligibleForHolidays(const string sym)
  {
   string s = sym;
   StringToUpper(s);

// Crypto
   if(StringFind(s, "BTC")   >= 0)
      return false;
   if(StringFind(s, "ETH")   >= 0)
      return false;
   if(StringFind(s, "LTC")   >= 0)
      return false;
   if(StringFind(s, "XRP")   >= 0)
      return false;
   if(StringFind(s, "BCH")   >= 0)
      return false;
   if(StringFind(s, "ADA")   >= 0)
      return false;
   if(StringFind(s, "DOT")   >= 0)
      return false;
   if(StringFind(s, "SOL")   >= 0)
      return false;
   if(StringFind(s, "DOGE")  >= 0)
      return false;
   if(StringFind(s, "MATIC") >= 0)
      return false;
   if(StringFind(s, "AVAX")  >= 0)
      return false;
   if(StringFind(s, "LINK")  >= 0)
      return false;
   if(StringFind(s, "UNI")   >= 0)
      return false;
   if(StringFind(s, "ATOM")  >= 0)
      return false;
   if(StringFind(s, "USDT")  >= 0)
      return false;
   if(StringFind(s, "USDC")  >= 0)
      return false;
   if(StringFind(s, "CRYPTO") >= 0)
      return false;

// Metals
   if(StringFind(s, "XAU") >= 0)
      return false;
   if(StringFind(s, "XAG") >= 0)
      return false;
   if(StringFind(s, "XPT") >= 0)
      return false;
   if(StringFind(s, "XPD") >= 0)
      return false;
   if(StringFind(s, "GOLD")   >= 0)
      return false;
   if(StringFind(s, "SILVER") >= 0)
      return false;

// Energies
   if(StringFind(s, "WTI")     >= 0)
      return false;
   if(StringFind(s, "BRENT")   >= 0)
      return false;
   if(StringFind(s, "USOIL")   >= 0)
      return false;
   if(StringFind(s, "UKOIL")   >= 0)
      return false;
   if(StringFind(s, "NATGAS")  >= 0)
      return false;
   if(StringFind(s, "NGAS")    >= 0)
      return false;
   if(StringFind(s, "CRUDE")   >= 0)
      return false;

// Softs
   if(StringFind(s, "COCOA")  >= 0)
      return false;
   if(StringFind(s, "COFFEE") >= 0)
      return false;
   if(StringFind(s, "SUGAR")  >= 0)
      return false;
   if(StringFind(s, "COTTON") >= 0)
      return false;
   if(StringFind(s, "WHEAT")  >= 0)
      return false;
   if(StringFind(s, "CORN")   >= 0)
      return false;

// FX: two currency codes = pair
   string ccys[] = {"USD", "EUR", "GBP", "JPY", "CHF", "AUD", "NZD", "CAD",
                    "CNH", "CNY", "HKD", "SGD", "SEK", "NOK", "DKK", "PLN",
                    "MXN", "TRY", "ZAR", "RUB", "ILS", "HUF", "CZK"
                   };
   int nc = ArraySize(ccys);
   int found = 0;
   for(int i = 0; i < nc; i++)
     {
      if(StringFind(s, ccys[i]) >= 0)
         found++;
      if(found >= 2)
         return false;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| DetectMarketForSymbol - ticker pattern -> market code            |
//+------------------------------------------------------------------+
string DetectMarketForSymbol(const string sym)
  {
   string s = sym;
   StringToUpper(s);

// US
   if(StringFind(s, "US100")    >= 0)
      return "NYSE";
   if(StringFind(s, "US500")    >= 0)
      return "NYSE";
   if(StringFind(s, "US30")     >= 0)
      return "NYSE";
   if(StringFind(s, "US2000")   >= 0)
      return "NYSE";
   if(StringFind(s, "NAS100")   >= 0)
      return "NYSE";
   if(StringFind(s, "NASDAQ")   >= 0)
      return "NYSE";
   if(StringFind(s, "NDX")      >= 0)
      return "NYSE";
   if(StringFind(s, "SPX")      >= 0)
      return "NYSE";
   if(StringFind(s, "SP500")    >= 0)
      return "NYSE";
   if(StringFind(s, "SP400")    >= 0)
      return "NYSE";
   if(StringFind(s, "DJI")      >= 0)
      return "NYSE";
   if(StringFind(s, "DJ30")     >= 0)
      return "NYSE";
   if(StringFind(s, "RUT")      >= 0)
      return "NYSE";
   if(StringFind(s, "RUSS2000") >= 0)
      return "NYSE";
   if(StringFind(s, "TECH100")  >= 0)
      return "NYSE";

// UK
   if(StringFind(s, "UK100")    >= 0)
      return "LSE";
   if(StringFind(s, "FTSE")     >= 0)
      return "LSE";

// Eurozone
   if(StringFind(s, "DE40")     >= 0)
      return "XETRA";
   if(StringFind(s, "DE30")     >= 0)
      return "XETRA";
   if(StringFind(s, "DAX")      >= 0)
      return "XETRA";
   if(StringFind(s, "GER40")    >= 0)
      return "XETRA";
   if(StringFind(s, "GER30")    >= 0)
      return "XETRA";
   if(StringFind(s, "EU50")     >= 0)
      return "XETRA";
   if(StringFind(s, "STOXX")    >= 0)
      return "XETRA";
   if(StringFind(s, "FRA40")    >= 0)
      return "XETRA";
   if(StringFind(s, "CAC")      >= 0)
      return "XETRA";
   if(StringFind(s, "ESP35")    >= 0)
      return "XETRA";
   if(StringFind(s, "IBEX")     >= 0)
      return "XETRA";

// Japan
   if(StringFind(s, "JP225")    >= 0)
      return "TSE";
   if(StringFind(s, "NIKKEI")   >= 0)
      return "TSE";
   if(StringFind(s, "NIK225")   >= 0)
      return "TSE";
   if(StringFind(s, "N225")     >= 0)
      return "TSE";

// HK
   if(StringFind(s, "HK50")     >= 0)
      return "HKEX";
   if(StringFind(s, "HSI")      >= 0)
      return "HKEX";
   if(StringFind(s, "HANG")     >= 0)
      return "HKEX";

// AU
   if(StringFind(s, "AUS200")   >= 0)
      return "ASX";
   if(StringFind(s, "AU200")    >= 0)
      return "ASX";
   if(StringFind(s, "ASX")      >= 0)
      return "ASX";
   if(StringFind(s, "SPI")      >= 0)
      return "ASX";

// CN
   if(StringFind(s, "CHINA50")  >= 0)
      return "SSE";
   if(StringFind(s, "CN50")     >= 0)
      return "SSE";
   if(StringFind(s, "A50")      >= 0)
      return "SSE";
   if(StringFind(s, "CSI")      >= 0)
      return "SSE";

   return "";
  }

//+------------------------------------------------------------------+
//| LoadHolidaysFile                                                 |
//| Reads and validates MQL5\Files\<InpHolidaysFile>.                |
//| Populates g_holDates[], g_holMarkets[], g_holCount.              |
//| No CRC: users can edit the file by hand.                         |
//+------------------------------------------------------------------+
void LoadHolidaysFile()
  {
//--- reset state
   g_holCount     = 0;
   g_holStatus    = HOL_STATUS_DISABLED;
   g_holStatusMsg = "";

//--- try common folder first, then local files folder
   int h = FileOpen(InpHolidaysFile, FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h == INVALID_HANDLE)
      h = FileOpen(InpHolidaysFile, FILE_READ|FILE_TXT|FILE_ANSI);

   if(h == INVALID_HANDLE)
     {
      g_holStatus    = HOL_STATUS_MISSING;
      g_holStatusMsg = "HOLIDAYS|file missing";
      Print("MarketClockPro: holidays.txt not found at '", InpHolidaysFile, "'. Falling back to broker sessions.");
      return;
     }

//--- parse header and body
   string   magic         = "";
   bool     inBody        = false;
   bool     sawBeginMarker = false;
   bool     sawEndMarker  = false;
   int      parsedCount   = 0;
   int      malformedCount = 0;

   while(!FileIsEnding(h))
     {
      string line = FileReadString(h);
      StringReplace(line, "\r", "");

      if(StringLen(line) == 0)
         continue;

      //--- header
      if(!inBody)
        {
         if(StringFind(line, "MAGIC:") == 0)
           {
            magic = StringSubstr(line, 6);
           }
         else
            if(StringFind(line, "COVERAGE_FROM:") == 0)
              {
               g_holCoverageFrom = StringToTime(StringSubstr(line, 14));
              }
            else
               if(StringFind(line, "COVERAGE_TO:") == 0)
                 {
                  g_holCoverageTo = StringToTime(StringSubstr(line, 12));
                 }
               else
                  if(line == "---BEGIN_HOLIDAYS---")
                    {
                     inBody = true;
                     sawBeginMarker = true;
                    }
         continue;
        }

      //--- body: YYYY-MM-DD:MARKET:NAME
      if(line == "---END_HOLIDAYS---")
        {
         sawEndMarker = true;
         break;
        }

      string trimmed = line;
      StringTrimLeft(trimmed);
      if(StringLen(trimmed) == 0)
         continue;
      if(StringGetCharacter(trimmed, 0) == '#')
         continue;

      int p1 = StringFind(line, ":");
      if(p1 < 0)
        {
         malformedCount++;
         continue;
        }
      int p2 = StringFind(line, ":", p1 + 1);
      if(p2 < 0)
        {
         malformedCount++;
         continue;
        }

      string dateStr = StringSubstr(line, 0, p1);
      string market  = StringSubstr(line, p1 + 1, p2 - p1 - 1);

      if(StringLen(dateStr) != 10 ||
         StringGetCharacter(dateStr, 4) != '-' ||
         StringGetCharacter(dateStr, 7) != '-')
        {
         malformedCount++;
         continue;
        }

      datetime dt = StringToTime(dateStr);
      if(dt == 0)
        {
         malformedCount++;
         continue;
        }

      if(StringLen(market) == 0)
        {
         malformedCount++;
         continue;
        }

      if(parsedCount < HOL_MAX_ENTRIES)
        {
         g_holDates[parsedCount]   = dt;
         g_holMarkets[parsedCount] = market;
         parsedCount++;
        }
     }

   FileClose(h);

//--- validate MAGIC
   if(magic != HOL_MAGIC)
     {
      g_holStatus    = HOL_STATUS_CORRUPT;
      g_holStatusMsg = "HOLIDAYS|invalid header";
      Print("MarketClockPro: holidays.txt missing or wrong MAGIC header (expected '", HOL_MAGIC, "'). Falling back.");
      g_holCount = 0;
      return;
     }

//--- validate section markers
   if(!sawBeginMarker || !sawEndMarker)
     {
      g_holStatus    = HOL_STATUS_CORRUPT;
      g_holStatusMsg = "HOLIDAYS|file truncated";
      Print("MarketClockPro: holidays.txt missing BEGIN/END markers. Falling back.");
      g_holCount = 0;
      return;
     }

//--- validate entry count
   if(parsedCount == 0)
     {
      g_holStatus    = HOL_STATUS_CORRUPT;
      g_holStatusMsg = "HOLIDAYS|no entries";
      Print("MarketClockPro: holidays.txt parsed 0 valid entries. Falling back.");
      return;
     }

//--- validate format quality (malformed ratio)
   if(malformedCount > parsedCount / 4)
     {
      g_holStatus    = HOL_STATUS_CORRUPT;
      g_holStatusMsg = "HOLIDAYS|many bad lines";
      Print("MarketClockPro: holidays.txt has too many malformed lines (", malformedCount, " bad vs ", parsedCount, " valid). Falling back.");
      g_holCount = 0;
      return;
     }

//--- validate coverage
   datetime today = TimeCurrent();
   if(g_holCoverageTo > 0 && g_holCoverageTo < today)
     {
      g_holStatus    = HOL_STATUS_OUTDATED;
      g_holStatusMsg = "HOLIDAYS|file outdated";
      Print("MarketClockPro: holidays.txt is outdated (coverage_to=", TimeToString(g_holCoverageTo, TIME_DATE), "). Falling back.");
      g_holCount = 0;
      return;
     }

//--- soft warning: coverage ending soon (30 days)
   if(g_holCoverageTo > 0 && (g_holCoverageTo - today) < 30 * 86400)
     {
      Print("MarketClockPro: holidays.txt coverage ends within 30 days (", TimeToString(g_holCoverageTo, TIME_DATE), "). Consider updating soon.");
     }

//--- commit
   g_holCount  = parsedCount;
   g_holStatus = HOL_STATUS_OK;
   Print("MarketClockPro: holidays.txt loaded OK. Entries=", g_holCount,
         (malformedCount > 0 ? StringFormat(" (skipped %d malformed)", malformedCount) : ""),
         " Coverage=", TimeToString(g_holCoverageFrom, TIME_DATE),
         " -> ", TimeToString(g_holCoverageTo, TIME_DATE));
  }

//+------------------------------------------------------------------+
//| IsHolidayForMarket                                                |
//+------------------------------------------------------------------+
bool IsHolidayForMarket(datetime utcDate, const string market)
  {
   if(g_holStatus != HOL_STATUS_OK)
      return false;
   if(StringLen(market) == 0)
      return false;
   if(g_holCount == 0)
      return false;

// Strip time
   MqlDateTime dt;
   TimeToStruct(utcDate, dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   datetime dayKey = StructToTime(dt);

   for(int i = 0; i < g_holCount; i++)
     {
      if(g_holDates[i] == dayKey && g_holMarkets[i] == market)
         return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string HolidayStatusText()
  {
   switch(g_holStatus)
     {
      case HOL_STATUS_DISABLED:
         return "disabled";
      case HOL_STATUS_OK:
         return StringFormat("OK (%d entries)", g_holCount);
      case HOL_STATUS_MISSING:
         return "file missing";
      case HOL_STATUS_CORRUPT:
         return "corrupt";
      case HOL_STATUS_OUTDATED:
         return "outdated";
     }
   return "unknown";
  }

//+------------------------------------------------------------------+
//| ComputeCorner                                                    |
//+------------------------------------------------------------------+
void ComputeCorner()
  {
   switch(InpCorner)
     {
      case HUD_TOP_RIGHT:
         g_cornerCode = CORNER_RIGHT_UPPER;
         g_anchor     = ANCHOR_RIGHT_UPPER;
         break;
      case HUD_TOP_LEFT:
         g_cornerCode = CORNER_LEFT_UPPER;
         g_anchor     = ANCHOR_LEFT_UPPER;
         break;
      case HUD_BOTTOM_RIGHT:
         g_cornerCode = CORNER_RIGHT_LOWER;
         g_anchor     = ANCHOR_RIGHT_LOWER;
         break;
      case HUD_BOTTOM_LEFT:
         g_cornerCode = CORNER_LEFT_LOWER;
         g_anchor     = ANCHOR_LEFT_LOWER;
         break;
     }
   g_xBase = HUD_X_OFFSET;
   g_yBase = HUD_Y_OFFSET;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ComputeAccentColor()
  {
   if(g_periodSec <= 60)
      g_accentColor = C'0,230,118';
   else
      if(g_periodSec <= 300)
         g_accentColor = C'105,240,174';
      else
         if(g_periodSec <= 900)
            g_accentColor = C'255,235,59';
         else
            if(g_periodSec <= 1800)
               g_accentColor = C'255,167,38';
            else
               if(g_periodSec <= 3600)
                  g_accentColor = C'239,83,80';
               else
                  if(g_periodSec <= 14400)
                     g_accentColor = C'66,165,245';
                  else
                     if(g_periodSec <= 86400)
                        g_accentColor = C'171,71,188';
                     else
                        if(g_periodSec <= 604800)
                           g_accentColor = C'0,188,212';
                        else
                           g_accentColor = C'255,215,0';
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ComputePanelColors()
  {
   if(InpTheme == THEME_DARK)
     {
      g_clrPanel  = C'15,15,20';
      g_clrBorder = C'45,45,60';
     }
   else
      if(InpTheme == THEME_LIGHT)
        {
         g_clrPanel  = C'240,240,245';
         g_clrBorder = C'200,200,210';
        }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int MeasureTextWidth(int fontSize, const string text)
  {
   uint w = 0, h = 0;
   TextSetFont(HUD_FONT, -fontSize * 10);
   TextGetSize(text, w, h);
   return (int)w;
  }

//+------------------------------------------------------------------+
//| BuildHUD                                                         |
//+------------------------------------------------------------------+
bool BuildHUD()
  {
   bool isUpper = (g_cornerCode == CORNER_RIGHT_UPPER || g_cornerCode == CORNER_LEFT_UPPER);
   int dir = isUpper ? 1 : -1;
   int yPos = g_yBase;

   g_panelBgName     = PREFIX + "PBG";
   g_panelBorderName = PREFIX + "PBR";

   int yStart = yPos;

//--- timer (always shown)
   if(!MakeLabel(PREFIX + "Timer", g_xBase, yPos, HUD_FONT, InpPrimaryFontSize, g_accentColor, "00:00"))
      return false;
   g_lastTimerColor = g_accentColor;
   yPos += dir * (InpPrimaryFontSize + HUD_LINE_SPACING + 2);

//--- timeframe label
   if(InpShowTimeframe)
     {
      MakeLabel(PREFIX + "TF", g_xBase, yPos, HUD_FONT, InpSecondaryFontSize, InpSecondaryColor, GetTimeframeLabel());
      yPos += dir * (InpSecondaryFontSize + HUD_LINE_SPACING);
     }

//--- session (primary + sub)
   if(InpShowSession)
     {
      MakeLabel(PREFIX + "Sess", g_xBase, yPos, HUD_FONT, InpSecondaryFontSize, InpSecondaryColor, " ");
      g_lastSessColor = InpSecondaryColor;
      g_lastSessText  = " ";
      yPos += dir * (InpSecondaryFontSize + HUD_LINE_SPACING);

      MakeLabel(PREFIX + "SessSub", g_xBase, yPos, HUD_FONT, InpSecondaryFontSize, InpSecondaryColor, " ");
      g_lastSessSubColor = InpSecondaryColor;
      g_lastSessSubText  = " ";
      yPos += dir * (InpSecondaryFontSize + HUD_LINE_SPACING);
     }

//--- spread
   if(InpShowSpread)
     {
      MakeLabel(PREFIX + "Spr", g_xBase, yPos, HUD_FONT, InpSecondaryFontSize, InpSecondaryColor, " ");
      g_lastSpreadColor = InpSecondaryColor;
      g_lastSpreadText  = " ";
      yPos += dir * (InpSecondaryFontSize + HUD_LINE_SPACING);
     }

//--- ADR
   if(InpShowADR)
     {
      MakeLabel(PREFIX + "ADR", g_xBase, yPos, HUD_FONT, InpSecondaryFontSize, InpSecondaryColor, " ");
      g_lastADRText = " ";
      yPos += dir * (InpSecondaryFontSize + HUD_LINE_SPACING);
     }

//--- status banner (two lines)
   MakeLabel(PREFIX + "Status", g_xBase, yPos, HUD_FONT, InpSecondaryFontSize - 1, g_clrCaution, " ");
   g_lastStatusText = " ";
   yPos += dir * (InpSecondaryFontSize - 1 + HUD_LINE_SPACING);

   MakeLabel(PREFIX + "StatusSub", g_xBase, yPos, HUD_FONT, InpSecondaryFontSize - 1, g_clrCaution, " ");
   g_lastStatusSubText = " ";
   yPos += dir * (InpSecondaryFontSize - 1 + HUD_LINE_SPACING);

//--- panel background
   if(InpTheme != THEME_STEALTH)
     {
      int panelHeight = MathAbs(yPos - yStart) + 8;
      int panelWidth  = ComputePanelWidth();

      int panelX, panelY;
      if(isUpper)
         panelY = g_yBase - 5;
      else
         panelY = g_yBase - panelHeight + 5;

      bool isRight = (g_cornerCode == CORNER_RIGHT_UPPER || g_cornerCode == CORNER_RIGHT_LOWER);
      if(isRight)
         panelX = g_xBase - panelWidth + 4;
      else
         panelX = g_xBase - 8;

      if(panelX < 1)
         panelX = 1;
      if(panelY < 1)
         panelY = 1;

      CreateRectLabel(g_panelBorderName, panelX - 1, panelY - 1,
                      panelWidth + 2, panelHeight + 2, g_clrBorder, 2);
      CreateRectLabel(g_panelBgName, panelX, panelY,
                      panelWidth, panelHeight, g_clrPanel, 3);
     }

   return true;
  }

//+------------------------------------------------------------------+
//| ComputePanelWidth                                                |
//+------------------------------------------------------------------+
int ComputePanelWidth()
  {
   int maxW = 0;
   int w;

   w = MeasureTextWidth(InpPrimaryFontSize, "-00:00:00");
   if(w > maxW)
      maxW = w;

   if(InpShowTimeframe)
     {
      w = MeasureTextWidth(InpSecondaryFontSize, "MN");
      if(w > maxW)
         maxW = w;
     }

   if(InpShowSession)
     {
      string s1 = "LDN+NY (59m)";
      w = MeasureTextWidth(InpSecondaryFontSize, s1);
      if(w > maxW)
         maxW = w;
      if(InpMarketClosedAlert)
        {
         w = MeasureTextWidth(InpSecondaryFontSize, "XETRA CLOSED (holiday)");
         if(w > maxW)
            maxW = w;
         if(InpShowTimeToOpen)
           {
            w = MeasureTextWidth(InpSecondaryFontSize, "Opens in 2d 04h");
            if(w > maxW)
               maxW = w;
           }
        }
     }

   if(InpShowSpread)
     {
      w = MeasureTextWidth(InpSecondaryFontSize, "SPR 999.9 pp");
      if(w > maxW)
         maxW = w;
     }

   if(InpShowADR)
     {
      w = MeasureTextWidth(InpSecondaryFontSize, "DR 999% ADR");
      if(w > maxW)
         maxW = w;
     }

// Status banner
   w = MeasureTextWidth(InpSecondaryFontSize - 1, "HOLIDAYS");
   if(w > maxW)
      maxW = w;
   w = MeasureTextWidth(InpSecondaryFontSize - 1, "symbol not mapped");
   if(w > maxW)
      maxW = w;

   if(maxW <= 0)
      maxW = 100;
   return maxW + 20;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MakeLabel(const string name, int x, int y,
               const string font, int size, color clr, const string text)
  {
   if(!ObjectCreate(g_chartID, name, OBJ_LABEL, 0, 0, 0))
      return false;

   ObjectSetInteger(g_chartID, name, OBJPROP_CORNER,     g_cornerCode);
   ObjectSetInteger(g_chartID, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(g_chartID, name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(g_chartID, name, OBJPROP_BACK,       false);
   ObjectSetInteger(g_chartID, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(g_chartID, name, OBJPROP_HIDDEN,     true);
   ObjectSetInteger(g_chartID, name, OBJPROP_ZORDER,     100);
   ObjectSetInteger(g_chartID, name, OBJPROP_ANCHOR,     g_anchor);
   ObjectSetString(g_chartID,  name, OBJPROP_FONT,       font);
   ObjectSetInteger(g_chartID, name, OBJPROP_FONTSIZE,   size);
   ObjectSetInteger(g_chartID, name, OBJPROP_COLOR,      clr);
   ObjectSetString(g_chartID,  name, OBJPROP_TEXT,       text);

   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CreateRectLabel(const string name, int x, int y, int w, int h,
                     color clr, int zOrder)
  {
   if(ObjectCreate(g_chartID, name, OBJ_RECTANGLE_LABEL, 0, 0, 0))
     {
      ObjectSetInteger(g_chartID, name, OBJPROP_CORNER,       g_cornerCode);
      ObjectSetInteger(g_chartID, name, OBJPROP_XDISTANCE,    x);
      ObjectSetInteger(g_chartID, name, OBJPROP_YDISTANCE,    y);
      ObjectSetInteger(g_chartID, name, OBJPROP_XSIZE,        w);
      ObjectSetInteger(g_chartID, name, OBJPROP_YSIZE,        h);
      ObjectSetInteger(g_chartID, name, OBJPROP_BGCOLOR,      clr);
      ObjectSetInteger(g_chartID, name, OBJPROP_BORDER_TYPE,  BORDER_FLAT);
      ObjectSetInteger(g_chartID, name, OBJPROP_BORDER_COLOR, clr);
      ObjectSetInteger(g_chartID, name, OBJPROP_WIDTH,        0);
      ObjectSetInteger(g_chartID, name, OBJPROP_BACK,         false);
      ObjectSetInteger(g_chartID, name, OBJPROP_SELECTABLE,   false);
      ObjectSetInteger(g_chartID, name, OBJPROP_HIDDEN,       true);
      ObjectSetInteger(g_chartID, name, OBJPROP_ZORDER,       zOrder);
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void StartTimer()
  {
   if(g_timerCreated)
     {
      EventKillTimer();
      g_timerCreated = false;
     }

   int ms = (g_periodSec >= 3600) ? 1000 : 500;

   g_timerCreated = EventSetMillisecondTimer(ms);
   if(!g_timerCreated)
     {
      g_timerCreated = EventSetTimer(1);
      if(!g_timerCreated)
         Print("Market Clock Pro: CRITICAL - Timer init failed");
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string GetTimeframeLabel()
  {
   ENUM_TIMEFRAMES tf = Period();
   switch(tf)
     {
      case PERIOD_M1:
         return "M1";
      case PERIOD_M2:
         return "M2";
      case PERIOD_M3:
         return "M3";
      case PERIOD_M4:
         return "M4";
      case PERIOD_M5:
         return "M5";
      case PERIOD_M6:
         return "M6";
      case PERIOD_M10:
         return "M10";
      case PERIOD_M12:
         return "M12";
      case PERIOD_M15:
         return "M15";
      case PERIOD_M20:
         return "M20";
      case PERIOD_M30:
         return "M30";
      case PERIOD_H1:
         return "H1";
      case PERIOD_H2:
         return "H2";
      case PERIOD_H3:
         return "H3";
      case PERIOD_H4:
         return "H4";
      case PERIOD_H6:
         return "H6";
      case PERIOD_H8:
         return "H8";
      case PERIOD_H12:
         return "H12";
      case PERIOD_D1:
         return "D1";
      case PERIOD_W1:
         return "W1";
      case PERIOD_MN1:
         return "MN";
      default:
         return "??";
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool HourInSession(int hour, int open, int close)
  {
   int o = open % 24;
   int c = close % 24;
   if(o < 0)
      o += 24;
   if(c < 0)
      c += 24;

   if(o < c)
      return (hour >= o && hour < c);
   else
      if(o > c)
         return (hour >= o || hour < c);
      else
         return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int MinutesToSessionEnd(int utcHour, int utcMin, int open, int close)
  {
   int o = open  % 24;
   if(o < 0)
      o += 24;
   int c = close % 24;
   if(c < 0)
      c += 24;

   if(o == c)
      return 1440;

   int cur = utcHour * 60 + utcMin;
   int cls = c * 60;

   int diff = cls - cur;
   if(diff <= 0)
      diff += 1440;
   return diff;
  }

//+------------------------------------------------------------------+
//| IsSymbolTradingNow - broker-session-based detection              |
//+------------------------------------------------------------------+
bool IsSymbolTradingNow(datetime &nextOpenServer)
  {
   nextOpenServer = 0;

//--- symbol trade mode
   long mode = SymbolInfoInteger(Symbol(), SYMBOL_TRADE_MODE);
   if(mode == SYMBOL_TRADE_MODE_DISABLED)
      return false;

   datetime serverNow = TimeTradeServer();
   if(serverNow == 0)
      return true;

   MqlDateTime dt;
   TimeToStruct(serverNow, dt);
   int todayDow = dt.day_of_week;
   int secOfDay = dt.hour * 3600 + dt.min * 60 + dt.sec;

   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   datetime todayMidnight = StructToTime(dt);

   bool anySessionsEverFound = false;
   datetime nextOpenToday = 0;

//--- scan today's sessions
   for(int idx = 0; idx < 4; idx++)
     {
      datetime from, to;
      if(!SymbolInfoSessionTrade(Symbol(), (ENUM_DAY_OF_WEEK)todayDow, idx, from, to))
         break;

      anySessionsEverFound = true;

      MqlDateTime fromDt, toDt;
      TimeToStruct(from, fromDt);
      TimeToStruct(to,   toDt);
      int fromSec = fromDt.hour * 3600 + fromDt.min * 60 + fromDt.sec;
      int toSec   = toDt.hour   * 3600 + toDt.min   * 60 + toDt.sec;

      if(secOfDay >= fromSec && secOfDay < toSec)
         return true;

      if(fromSec > secOfDay)
        {
         datetime openAbs = todayMidnight + (datetime)fromSec;
         if(nextOpenToday == 0 || openAbs < nextOpenToday)
            nextOpenToday = openAbs;
        }
     }

//--- next open found today (after current time)
   if(nextOpenToday > 0)
     {
      nextOpenServer = nextOpenToday;
      return false;
     }

//--- lookahead up to 7 days for earliest session
   for(int daysAhead = 1; daysAhead <= 7; daysAhead++)
     {
      datetime futureMidnight = todayMidnight + (datetime)(daysAhead * 86400);
      MqlDateTime fdt;
      TimeToStruct(futureMidnight, fdt);
      int futureDow = fdt.day_of_week;

      datetime earliestFuture = 0;
      for(int idx = 0; idx < 4; idx++)
        {
         datetime from, to;
         if(!SymbolInfoSessionTrade(Symbol(), (ENUM_DAY_OF_WEEK)futureDow, idx, from, to))
            break;

         anySessionsEverFound = true;

         MqlDateTime fromDt;
         TimeToStruct(from, fromDt);
         int fromSec = fromDt.hour * 3600 + fromDt.min * 60 + fromDt.sec;

         datetime openAbs = futureMidnight + (datetime)fromSec;
         if(earliestFuture == 0 || openAbs < earliestFuture)
            earliestFuture = openAbs;
        }

      if(earliestFuture > 0)
        {
         nextOpenServer = earliestFuture;
         return false;
        }
     }

//--- broker did not expose any sessions: assume always tradable
   if(!anySessionsEverFound)
      return true;

   return false;
  }

//+------------------------------------------------------------------+
//| IsMarketClosedByHoliday                                          |
//| Sets nextOpenUTC to the next non-holiday weekday.                |
//+------------------------------------------------------------------+
bool IsMarketClosedByHoliday(datetime &nextOpenUTC)
  {
   nextOpenUTC = 0;

   if(g_holStatus != HOL_STATUS_OK)
      return false;
   if(StringLen(g_symbolMarket) == 0)
      return false;

   datetime utcNow = GetCurrentUTCTime();
   if(!IsHolidayForMarket(utcNow, g_symbolMarket))
      return false;

   MqlDateTime dt;
   TimeToStruct(utcNow, dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   datetime dayKey = StructToTime(dt);

   for(int daysAhead = 1; daysAhead <= 14; daysAhead++)
     {
      datetime candidate = dayKey + (datetime)(daysAhead * 86400);
      MqlDateTime cdt;
      TimeToStruct(candidate, cdt);

      // 0=Sunday, 6=Saturday
      if(cdt.day_of_week == 0 || cdt.day_of_week == 6)
         continue;
      if(IsHolidayForMarket(candidate, g_symbolMarket))
         continue;

      nextOpenUTC = candidate;
      return true;
     }

   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string FormatTimeToOpen(long secsToOpen)
  {
   if(secsToOpen <= 0)
      return "";

   long days  = secsToOpen / 86400;
   long hours = (secsToOpen % 86400) / 3600;
   long mins  = (secsToOpen % 3600) / 60;

   if(days > 0)
      return StringFormat("Opens in %dd %02dh", (int)days, (int)hours);
   if(hours > 0)
      return StringFormat("Opens in %dh%02dm", (int)hours, (int)mins);
   return StringFormat("Opens in %dm", (int)mins);
  }

//+------------------------------------------------------------------+
//| DetermineCloseReason - weekend/session/fallback                  |
//+------------------------------------------------------------------+
string DetermineCloseReason()
  {
   datetime serverNow = TimeTradeServer();
   if(serverNow == 0)
      return "";

   MqlDateTime dt;
   TimeToStruct(serverNow, dt);
   if(dt.day_of_week == 0 || dt.day_of_week == 6)
      return "weekend";

// Check UTC too for brokers whose local day differs from UTC
   datetime utcNow = GetCurrentUTCTime();
   MqlDateTime udt;
   TimeToStruct(utcNow, udt);
   if(udt.day_of_week == 0 || udt.day_of_week == 6)
      return "weekend";

   return "session";
  }

//+------------------------------------------------------------------+
//| GetSessionLabel                                                   |
//+------------------------------------------------------------------+
string GetSessionLabel()
  {
//--- cache on minute boundary
   datetime utcNow = GetCurrentUTCTime();
   MqlDateTime udt;
   TimeToStruct(utcNow, udt);
   int utcHour = udt.hour;
   int utcMin  = udt.min;

   if(utcHour == g_sessLastHour && utcMin == g_sessLastMinute)
      return g_sessCache;

   g_sessLastHour   = utcHour;
   g_sessLastMinute = utcMin;
   g_sessSubCache   = "";

   if(InpMarketClosedAlert)
     {
      //--- holiday has priority over broker sessions
      datetime nextOpenHol = 0;
      if(IsMarketClosedByHoliday(nextOpenHol))
        {
         g_marketOpen = false;
         string prefix = (StringLen(g_symbolMarket) > 0) ? g_symbolMarket : "MARKET";
         g_sessCache = prefix + " CLOSED (holiday)";
         if(InpShowTimeToOpen && nextOpenHol > 0)
           {
            long secsToOpen = (long)nextOpenHol - (long)GetCurrentUTCTime();
            if(secsToOpen > 0)
               g_sessSubCache = FormatTimeToOpen(secsToOpen);
           }
         return g_sessCache;
        }

      //--- broker sessions
      datetime nextOpenServer = 0;
      g_marketOpen = IsSymbolTradingNow(nextOpenServer);

      if(!g_marketOpen)
        {
         string prefix = (StringLen(g_symbolMarket) > 0) ? g_symbolMarket : "MARKET";
         string reason = DetermineCloseReason();

         if(StringLen(reason) > 0)
            g_sessCache = prefix + " CLOSED (" + reason + ")";
         else
            g_sessCache = prefix + " CLOSED";

         if(InpShowTimeToOpen && nextOpenServer > 0)
           {
            long secsToOpen = (long)nextOpenServer - (long)TimeTradeServer();
            if(secsToOpen > 0)
               g_sessSubCache = FormatTimeToOpen(secsToOpen);
           }
         return g_sessCache;
        }
     }
   else
     {
      g_marketOpen = true;
     }

//--- geographic sessions
   string s = "";
   int n = 0;
   int  minEnd[4];
   bool active[4] = {false, false, false, false};

   if(HourInSession(utcHour, TOK_OPEN, TOK_CLOSE))
     {
      s += "TOK";
      n++;
      active[0] = true;
      minEnd[0] = MinutesToSessionEnd(utcHour, utcMin, TOK_OPEN, TOK_CLOSE);
     }
   if(HourInSession(utcHour, LDN_OPEN, LDN_CLOSE))
     {
      if(n > 0)
         s += "+";
      s += "LDN";
      n++;
      active[1] = true;
      minEnd[1] = MinutesToSessionEnd(utcHour, utcMin, LDN_OPEN, LDN_CLOSE);
     }
   if(HourInSession(utcHour, NY_OPEN, NY_CLOSE))
     {
      if(n > 0)
         s += "+";
      s += "NY";
      n++;
      active[2] = true;
      minEnd[2] = MinutesToSessionEnd(utcHour, utcMin, NY_OPEN, NY_CLOSE);
     }
   if(HourInSession(utcHour, SYD_OPEN, SYD_CLOSE))
     {
      if(n > 0)
         s += "+";
      s += "SYD";
      n++;
      active[3] = true;
      minEnd[3] = MinutesToSessionEnd(utcHour, utcMin, SYD_OPEN, SYD_CLOSE);
     }

   if(n == 0)
     {
      g_sessCache = "QUIET";
      return g_sessCache;
     }

   if(n >= 2)
     {
      int soonest = 99999;
      for(int i = 0; i < 4; i++)
         if(active[i] && minEnd[i] < soonest)
            soonest = minEnd[i];

      if(soonest < 99999)
        {
         if(soonest >= 60)
            s += StringFormat(" (%dh%02dm)", soonest / 60, soonest % 60);
         else
            s += StringFormat(" (%dm)", soonest);
        }
     }

   g_sessCache = s;
   return g_sessCache;
  }

//+------------------------------------------------------------------+
//| Spread                                                            |
//+------------------------------------------------------------------+
string GetSpreadText(long spread)
  {
   int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
   if(digits == 5 || digits == 3)
      return StringFormat("%.1f pp", (double)spread / 10.0);
   return StringFormat("%d pt", (int)spread);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void UpdateSpreadHistory(long spread)
  {
   g_spreadHistory[g_spreadHistIdx] = spread;
   g_spreadHistIdx = (g_spreadHistIdx + 1) % SPREAD_HISTORY_SIZE;
   if(g_spreadHistCount < SPREAD_HISTORY_SIZE)
      g_spreadHistCount++;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsSpreadAnomalous(long spread)
  {
   if(g_spreadHistCount < 10)
      return false;

   double sum = 0;
   for(int i = 0; i < g_spreadHistCount; i++)
      sum += (double)g_spreadHistory[i];

   double avg = sum / (double)g_spreadHistCount;
   if(avg <= 0)
      return false;

   return ((double)spread / avg) > SPREAD_ANOMALY_MULT;
  }

//+------------------------------------------------------------------+
//| ADR                                                              |
//+------------------------------------------------------------------+
string GetADRText()
  {
   if(!g_d1DataReady)
     {
      long bars = 0;
      if(!SeriesInfoInteger(Symbol(), PERIOD_D1, SERIES_BARS_COUNT, bars) || bars < 2)
         return "--% ADR";
      g_d1DataReady = true;
     }

   datetime currentDay = iTime(Symbol(), PERIOD_D1, 0);
   if(currentDay == 0)
      return "--% ADR";

   if(g_adrLastCalc != currentDay || g_adrValue <= 0)
     {
      g_adrValue    = CalcADR(MathMax(InpADRPeriod, 1));
      g_adrLastCalc = currentDay;
     }

   if(g_adrValue <= 0)
      return "--% ADR";

   double dayH = iHigh(Symbol(), PERIOD_D1, 0);
   double dayL = iLow(Symbol(), PERIOD_D1, 0);

   if(dayH <= 0 || dayL <= 0 || dayH <= dayL)
      return "0% ADR";

   double dr = dayH - dayL;
   int pct = (int)MathRound((dr / g_adrValue) * 100.0);
   if(pct < 0)
      pct = 0;
   if(pct > 999)
      pct = 999;

   return StringFormat("%d%% ADR", pct);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double CalcADR(int periods)
  {
   double total = 0;
   int counted  = 0;
   int maxBars  = periods + 10;

   for(int i = 1; i <= maxBars && counted < periods; i++)
     {
      double h = iHigh(Symbol(), PERIOD_D1, i);
      double l = iLow(Symbol(), PERIOD_D1, i);

      if(h > 0 && l > 0 && h > l)
        {
         total += (h - l);
         counted++;
        }
     }

   return (counted > 0) ? (total / (double)counted) : 0;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string FormatCountdown(long secsLeft)
  {
   long a = MathAbs(secsLeft);
   int d = (int)(a / 86400);
   int h = (int)((a % 86400) / 3600);
   int m = (int)((a % 3600) / 60);
   int s = (int)(a % 60);

   string pfx = (secsLeft < 0) ? "-" : "";

   if(d > 0)
      return pfx + StringFormat("%dd %02d:%02d:%02d", d, h, m, s);
   if(h > 0)
      return pfx + StringFormat("%02d:%02d:%02d", h, m, s);
   return pfx + StringFormat("%02d:%02d", m, s);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SetTextRaw(const string name, const string text)
  {
   ObjectSetString(g_chartID, name, OBJPROP_TEXT, text);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SetColorRaw(const string name, color clr)
  {
   ObjectSetInteger(g_chartID, name, OBJPROP_COLOR, clr);
  }

//+------------------------------------------------------------------+
//| RefreshHUD                                                       |
//+------------------------------------------------------------------+
void RefreshHUD()
  {
   if(!g_initialized)
      return;
   if(Bars(Symbol(), Period()) < 1)
      return;

   datetime barTime    = iTime(Symbol(), Period(), 0);
   datetime serverTime = TimeTradeServer();
   if(barTime == 0 || serverTime == 0)
      return;

//--- new bar detection
   if(barTime != g_lastBarTime)
     {
      g_lastBarTime  = barTime;
      g_alertPlayed  = false;
      g_lastSecsLeft = -999;

      if(!g_d1DataReady)
        {
         long bars = 0;
         if(SeriesInfoInteger(Symbol(), PERIOD_D1, SERIES_BARS_COUNT, bars) && bars >= 2)
            g_d1DataReady = true;
        }
     }

//--- refresh broker-UTC offset periodically (DST handling)
   if((long)serverTime - (long)g_lastOffsetCheck >= OFFSET_REFRESH_SEC)
     {
      ComputeBrokerOffset();
      g_lastOffsetCheck = serverTime;
     }

//--- compute seconds left to candle close
   long elapsed  = (long)serverTime - (long)barTime;
   long secsLeft = g_periodSec - elapsed;
   if(secsLeft < 0)
      secsLeft = 0;
   if(secsLeft > g_periodSec)
      secsLeft = g_periodSec;

   bool timeChanged = (secsLeft != g_lastSecsLeft);
   g_lastSecsLeft = secsLeft;

   bool dirty = false;

//--- timer
   if(timeChanged)
     {
      string newText = FormatCountdown(secsLeft);
      if(newText != g_lastTimerText)
        {
         SetTextRaw(PREFIX + "Timer", newText);
         g_lastTimerText = newText;
         dirty = true;
        }

      color newClr;
      if(InpAlertEnabled && secsLeft <= g_alertSecs && secsLeft > 0)
         newClr = g_clrWarn;
      else
         if(secsLeft <= MathMax(g_alertSecs * 2, 10) && secsLeft > 0)
            newClr = g_clrCaution;
         else
            newClr = g_accentColor;

      if(newClr != g_lastTimerColor)
        {
         SetColorRaw(PREFIX + "Timer", newClr);
         g_lastTimerColor = newClr;
         dirty = true;
        }
     }

//--- session
   if(g_objSess)
     {
      string newSess = GetSessionLabel();
      string newSub  = g_sessSubCache;
      if(StringLen(newSub) == 0)
         newSub = " ";  // prevent empty-label fallback

      if(newSess != g_lastSessText)
        {
         SetTextRaw(PREFIX + "Sess", newSess);
         g_lastSessText = newSess;
         dirty = true;
        }

      color newSessClr = (InpMarketClosedAlert && !g_marketOpen)
                         ? g_clrMarketClosed
                         : InpSecondaryColor;
      if(newSessClr != g_lastSessColor)
        {
         SetColorRaw(PREFIX + "Sess", newSessClr);
         g_lastSessColor = newSessClr;
         dirty = true;
        }

      if(newSub != g_lastSessSubText)
        {
         SetTextRaw(PREFIX + "SessSub", newSub);
         g_lastSessSubText = newSub;
         dirty = true;
        }

      color newSubClr = (InpMarketClosedAlert && !g_marketOpen)
                        ? g_clrMarketClosed
                        : InpSecondaryColor;
      if(newSubClr != g_lastSessSubColor)
        {
         SetColorRaw(PREFIX + "SessSub", newSubClr);
         g_lastSessSubColor = newSubClr;
         dirty = true;
        }
     }

//--- spread
   if(g_objSpr)
     {
      long curSpread = SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
      UpdateSpreadHistory(curSpread);

      if(curSpread != g_lastSpread)
        {
         string newText = "SPR " + GetSpreadText(curSpread);
         SetTextRaw(PREFIX + "Spr", newText);
         g_lastSpread     = curSpread;
         g_lastSpreadText = newText;
         dirty = true;
        }

      color newSprClr = IsSpreadAnomalous(curSpread) ? g_clrWarn : InpSecondaryColor;
      if(newSprClr != g_lastSpreadColor)
        {
         SetColorRaw(PREFIX + "Spr", newSprClr);
         g_lastSpreadColor = newSprClr;
         dirty = true;
        }
     }

//--- ADR
   if(g_objADR)
     {
      string newADR = "DR " + GetADRText();
      if(newADR != g_lastADRText)
        {
         SetTextRaw(PREFIX + "ADR", newADR);
         g_lastADRText = newADR;
         dirty = true;
        }
     }

//--- status banner (split on '|')
   string statusHead = " ";  // space prevents empty-label fallback
   string statusBody = " ";
   if(g_holStatusShownUntil > 0 && TimeCurrent() <= g_holStatusShownUntil &&
      StringLen(g_holStatusMsg) > 0)
     {
      int sepPos = StringFind(g_holStatusMsg, "|");
      if(sepPos >= 0)
        {
         statusHead = StringSubstr(g_holStatusMsg, 0, sepPos);
         statusBody = StringSubstr(g_holStatusMsg, sepPos + 1);
        }
      else
        {
         statusHead = g_holStatusMsg;
        }
     }

   if(statusHead != g_lastStatusText)
     {
      SetTextRaw(PREFIX + "Status", statusHead);
      g_lastStatusText = statusHead;
      dirty = true;
     }
   if(statusBody != g_lastStatusSubText)
     {
      SetTextRaw(PREFIX + "StatusSub", statusBody);
      g_lastStatusSubText = statusBody;
      dirty = true;
     }

//--- alert sound
   if(InpAlertEnabled && secsLeft <= g_alertSecs && secsLeft > 0 && !g_alertPlayed)
     {
      PlaySound(ALERT_SOUND);
      g_alertPlayed = true;
     }
   else
      if(secsLeft > g_alertSecs)
        {
         g_alertPlayed = false;
        }

   if(dirty)
      ChartRedraw(g_chartID);
  }

//+------------------------------------------------------------------+
//| OnTimer                                                          |
//+------------------------------------------------------------------+
void OnTimer()
  {
   RefreshHUD();
  }

//+------------------------------------------------------------------+
//| OnCalculate                                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   return rates_total;
  }

//+------------------------------------------------------------------+
//| OnChartEvent                                                     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
  {
   if(id == CHARTEVENT_CHART_CHANGE && g_initialized)
     {
      // Force full repaint with sentinels
      g_lastSecsLeft    = -999;
      g_lastTimerText   = "\x01";
      g_lastSessText    = "\x01";
      g_lastSessSubText = "\x01";
      g_lastSpreadText  = "\x01";
      g_lastADRText     = "\x01";
      g_lastStatusText    = "\x01";
      g_lastStatusSubText = "\x01";
      g_lastSpread      = -1;
      RefreshHUD();
     }
  }

//+------------------------------------------------------------------+
//| CleanupObjects                                                   |
//+------------------------------------------------------------------+
void CleanupObjects()
  {
   if(g_chartID == 0)
      g_chartID = ChartID();
   int total = ObjectsTotal(g_chartID);
   for(int i = total - 1; i >= 0; i--)
     {
      string name = ObjectName(g_chartID, i);
      if(StringFind(name, PREFIX) == 0)
         ObjectDelete(g_chartID, name);
     }
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_initialized = false;

   if(g_timerCreated)
     {
      EventKillTimer();
      g_timerCreated = false;
     }

   long deinitChart = ChartID();
   int total = ObjectsTotal(deinitChart);
   for(int i = total - 1; i >= 0; i--)
     {
      string name = ObjectName(deinitChart, i);
      if(StringFind(name, PREFIX) == 0)
         ObjectDelete(deinitChart, name);
     }

   Print("Market Clock Pro v1.0 - Shutdown (Reason: ", reason, ")");
  }
//+------------------------------------------------------------------+

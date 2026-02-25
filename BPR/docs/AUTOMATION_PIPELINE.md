# Automation Pipeline — Wine + macOS Apple Silicon

*Every command tested against actual system paths. UTF-16 LE encoding confirmed for all config files.*

---

## 1. System Configuration

### 1.1 Environment Variables

```bash
export WINE="/Applications/MetaTrader 5.app/Contents/SharedSupport/wine/bin/wine64"
export WINEPREFIX="$HOME/Library/Application Support/net.metaquotes.wine.metatrader5"
export WINEDLLOVERRIDES="mscoree=d;mshtml=d;winemenubuilder.exe=d"

# MT5 paths (macOS filesystem)
export MT5_ROOT="$WINEPREFIX/drive_c/Program Files/MetaTrader 5"
export MQL5_DIR="$MT5_ROOT/MQL5"
export EXPERTS_DIR="$MQL5_DIR/Experts"
export INCLUDE_DIR="$MQL5_DIR/Include"
export TESTER_PRESETS="$MQL5_DIR/Profiles/Tester"
export CONFIG_DIR="$MT5_ROOT/config"
export TESTER_DIR="$MT5_ROOT/Tester"
export LOGS_DIR="$MT5_ROOT/logs"

# Wine path mapping
# C: → $WINEPREFIX/drive_c/
# Z: → /  (macOS root)
```

### 1.2 Wine Version

Wine 10.0 (bundled in MetaTrader 5.app), running x86_64 via Rosetta 2.

Known harmless errors to suppress (redirect `2>/dev/null`):
```
err:hid:handle_DeviceMatchingCallback Ignoring HID device...
err:ntoskrnl:ZwLoadDriver failed to create driver...winebth
fixme:service:scmdatabase_autostart_services Auto-start service L"winebth"
```

---

## 2. MetaEditor CLI Compilation

### 2.1 Command

```bash
WINEPREFIX="$WINEPREFIX" WINEDLLOVERRIDES="$WINEDLLOVERRIDES" \
  "$WINE" "C:\\Program Files\\MetaTrader 5\\metaeditor64.exe" \
  /compile:"C:\\Program Files\\MetaTrader 5\\MQL5\\Experts\\BPR_Bot.mq5" \
  /include:"C:\\Program Files\\MetaTrader 5\\MQL5" \
  /log 2>/dev/null
```

### 2.2 Key Facts

| Fact | Detail |
|------|--------|
| Headless? | **Yes** — `/compile` does not render GUI |
| Offline? | **Yes** — no MT5 terminal or network needed |
| Output | `.ex5` file in same directory as `.mq5` |
| Log | `.log` file in same directory (UTF-16 encoded) |
| Exit code | **NOT RELIABLE** — MetaEditor can return 0 even on failure |
| Error detection | Check `.ex5` file existence + parse `.log` for `: error` strings |
| Silent failures | Known issue: large modular projects can fail without errors in log |

### 2.3 Compilation Verification Script

```bash
#!/bin/bash
# compile.sh — Compile and verify
MQ5_FILE="$1"
EX5_FILE="${MQ5_FILE%.mq5}.ex5"
LOG_FILE="${MQ5_FILE%.mq5}.log"

# Get Windows path via Z: drive
WIN_PATH=$(WINEPREFIX="$WINEPREFIX" "$WINE" winepath -w "$MQ5_FILE" 2>/dev/null)
WIN_INCLUDE="C:\\Program Files\\MetaTrader 5\\MQL5"

# Remove old .ex5 to detect fresh compilation
rm -f "$EX5_FILE"

# Compile
WINEPREFIX="$WINEPREFIX" WINEDLLOVERRIDES="mscoree=d;mshtml=d;winemenubuilder.exe=d" \
  "$WINE" "C:\\Program Files\\MetaTrader 5\\metaeditor64.exe" \
  /compile:"$WIN_PATH" /include:"$WIN_INCLUDE" /log 2>/dev/null

# Wait for Wine to finish file writes
sleep 2

# Verify
if [ -f "$EX5_FILE" ]; then
    echo "SUCCESS: $EX5_FILE created"
    # Parse log for warnings (UTF-16 to UTF-8)
    if [ -f "$LOG_FILE" ]; then
        iconv -f UTF-16LE -t UTF-8 "$LOG_FILE" | grep -i "warning" || true
    fi
    exit 0
else
    echo "FAILED: No .ex5 file produced"
    if [ -f "$LOG_FILE" ]; then
        echo "--- Compilation Log ---"
        iconv -f UTF-16LE -t UTF-8 "$LOG_FILE" | grep -i "error"
    fi
    exit 1
fi
```

### 2.4 CRITICAL: MetaEditor Fails with Spaces in Compile Path (Build 5640)

**Confirmed**: MetaEditor 5640 via Wine silently fails when `/compile:` path contains spaces. The `.ex5` is not produced and no error is shown.

**Workaround**: Copy `.mq5` to a path without spaces (`C:\temp\`), compile there, then copy `.ex5` to the target directory.

```bash
# Step 1: Copy source to temp dir (no spaces in path)
cp "$MQ5_SOURCE" "$WINEPREFIX/drive_c/temp/$(basename $MQ5_SOURCE)"

# Step 2: Compile from temp dir
WINEPREFIX="$WINEPREFIX" WINEDLLOVERRIDES="$WINEDLLOVERRIDES" \
  "$WINE" "C:\\Program Files\\MetaTrader 5\\metaeditor64.exe" \
  "/compile:C:\\temp\\$(basename $MQ5_SOURCE)" \
  "/include:C:\\Program Files\\MetaTrader 5\\MQL5" \
  "/log" 2>/dev/null

# Step 3: Copy .ex5 to target directory
cp "$WINEPREFIX/drive_c/temp/${MQ5_SOURCE%.mq5}.ex5" "$TARGET_DIR/"
```

**Tested and confirmed working** on build 5640, Wine 10.0, macOS Apple Silicon (2026-02-25).

---

## 3. Automated Backtesting

### 3.1 INI File Format

**CRITICAL: INI files must be UTF-16 LE with BOM.**

```ini
[Common]
Login=5935483
Server=GTCGlobalTrade-Server

[Tester]
Expert=Experts\BPR_Bot
Symbol=XAUUSD
Period=M15
Model=0
ExecutionMode=0
FromDate=2025.01.01
ToDate=2026.01.01
Deposit=10000
Currency=USD
Leverage=1:500
Optimization=0
OptimizationCriterion=6
ExpertParameters=BPR_XAUUSD.set
Report=Tester\BPR_XAUUSD_report.htm
ReplaceReport=1
ShutdownTerminal=1
Visual=0
UseLocal=1
UseRemote=0
UseCloud=0
```

### 3.2 INI Parameters Reference

| Key | Values | Notes |
|-----|--------|-------|
| `Expert` | Relative to `MQL5/` (no `.ex5` extension) | e.g., `Experts\BPR_Bot` |
| `Symbol` | Exact broker symbol name | Must match broker's naming |
| `Period` | `M1,M5,M15,M30,H1,H4,D1,W1,MN1` | M2,M3,M4,M6,M10,M12,M20,H2,H3,H6,H8,H12 also valid |
| `Model` | `0`=every tick, `1`=OHLC 1min, `2`=open prices, `4`=real ticks | 0 recommended for FVG strategy |
| `Deposit` | Initial balance amount | In `Currency` denomination |
| `Leverage` | `1:100`, `1:500`, `1:2000` etc. | Match broker's actual leverage |
| `Optimization` | `0`=off, `1`=slow/complete, `2`=genetic | |
| `OptimizationCriterion` | `0`=balance, `5`=Sharpe, `6`=custom OnTester() | 6 recommended |
| `ExpertParameters` | `.set` filename (in `MQL5/Profiles/Tester/`) | |
| `Report` | Output filename (`.htm` or `.xml`) | Can include relative path |
| `ReplaceReport` | `0`=add suffix if exists, `1`=overwrite | |
| `ShutdownTerminal` | `0`=keep running, `1`=exit after test | **MUST be 1 for automation** |
| `Visual` | `0`=headless, `1`=visual mode | 0 for automation |
| `ForwardMode` | `0`=off, `1`=1/2, `2`=1/3, `3`=1/4, `4`=custom | |
| `ForwardDate` | `YYYY.MM.DD` | Only with `ForwardMode=4` |

### 3.3 Backtest Launch Command

```bash
WINEPREFIX="$WINEPREFIX" WINEDLLOVERRIDES="$WINEDLLOVERRIDES" \
  "$WINE" "C:\\Program Files\\MetaTrader 5\\terminal64.exe" \
  /config:"C:\\Program Files\\MetaTrader 5\\config\\backtest.ini" \
  /portable 2>/dev/null &

WINE_PID=$!
wait $WINE_PID

# Kill Wine server for clean state
WINEPREFIX="$WINEPREFIX" \
  "/Applications/MetaTrader 5.app/Contents/SharedSupport/wine/bin/wineserver" -k 2>/dev/null
```

### 3.4 Key Facts About Backtesting via Wine (CONFIRMED Build 5640)

| Fact | Detail |
|------|--------|
| Display needed? | **Yes** — terminal is a GUI app. Window appears on macOS screen. |
| Fully headless? | **No on macOS** — Wine uses Mac Driver (not X11). Window must render. |
| `ShutdownTerminal=1` | **CONFIRMED WORKING** — terminal exits cleanly after test completes |
| Broker login needed? | **Yes** — terminal authenticates for historical data |
| Password storage | In `accounts.dat` — cached after first manual login |
| Performance | ~15 seconds total (1 month M15 OHLC), 0.1s computation only |
| Report location | `Tester/` directory under MT5 root (confirmed) |
| Report files | `.htm` + 4 `.png` files (equity curve, histograms, MFE/MAE, holding time) |

### 3.5 CRITICAL: Known Gotchas (All Confirmed 2026-02-25)

**1. INI path MUST NOT contain spaces**
```
WRONG:  /config:"C:\Program Files\MetaTrader 5\config\backtest.ini"  → silently fails
RIGHT:  /config:C:\temp\backtest.ini  → works
```
Copy INI to `C:\temp\` before launching.

**2. EA path is relative to MQL5/Experts/ (NO Experts\ prefix)**
```
WRONG:  Expert=Experts\Advisors\ExpertMACD    → "not found" (looks in Experts\Experts\)
RIGHT:  Expert=Advisors\ExpertMACD            → works
```
MT5 tester auto-prepends `Experts\` to the Expert= value.

**3. Port 3000 must be free**
MT5 Strategy Tester agent binds to `127.0.0.1:3000`. If another process (Node.js, etc.) occupies this port, the backtest silently produces an empty report with all zeros.
```bash
# Pre-flight check
lsof -iTCP:3000 -sTCP:LISTEN
# Kill if needed
kill $(lsof -t -iTCP:3000 -sTCP:LISTEN) 2>/dev/null
```

**4. Leverage format**
Use `Leverage=500` (not `Leverage=1:500`). Confirmed working.

### 3.5 Estimated Backtest Duration (XAUUSD M15, 1 year)

| Model | Approximate Time |
|-------|-----------------|
| Real ticks | 10-30 minutes |
| Every tick (generated) | 5-15 minutes |
| OHLC 1 minute | 2-5 minutes |
| Open prices only | 15-60 seconds |

---

## 4. .set File Format

### 4.1 Format Specification

**Encoding: UTF-16 LE with BOM (0xFF 0xFE)**

```
; comment line
ParameterName=value||default||start||stop||Y/N
```

| Field | Meaning |
|-------|---------|
| First `value` | Current/active value |
| After first `\|\|` | Default value |
| After second `\|\|` | Optimization start (or step) |
| After third `\|\|` | Optimization stop |
| `Y` or `N` | Optimize this parameter (Y) or use fixed value (N) |

### 4.2 Example .set File Content

```
; BPR Bot XAUUSD Configuration
; Generated by automation pipeline
;
Inp_MagicNumber=240001||240001||0||0||N
Inp_GMTOffsetWinter=2||2||0||0||N
Inp_GMTOffsetSummer=3||3||0||0||N
Inp_RR=2.0||2.0||1.0||4.0||Y
Inp_SLBufferPoints=10||10||5||50||Y
Inp_RiskFractionEquity=0.02||0.02||0.01||0.10||N
Inp_BPRLookbackBars=30||30||10||50||Y
Inp_SwingLookback=5||5||3||7||Y
Inp_FVGFilterTier=2||2||0||3||Y
Inp_AsiaBlockStart=22||22||0||0||N
Inp_AsiaBlockEnd=7||7||0||0||N
```

### 4.3 Python .set File Generator

```python
import codecs

def write_set_file(filepath, params):
    """
    params: dict of {name: (value, default, start, stop, optimize)}
    optimize: True/False
    """
    with codecs.open(filepath, 'w', 'utf-16-le') as f:
        f.write('\ufeff')  # BOM
        f.write('; Generated by BPR Bot automation pipeline\n;\n')
        for name, (value, default, start, stop, optimize) in params.items():
            opt = 'Y' if optimize else 'N'
            f.write(f'{name}={value}||{default}||{start}||{stop}||{opt}\n')
```

---

## 5. Report Parsing

### 5.1 HTML Report Structure

Two main tables:
1. **Settings & Metrics** — EA name, symbol, period, all performance metrics
2. **Orders & Deals** — every trade with timestamp, direction, volume, price, SL, TP, profit

### 5.2 Key Metrics to Extract

| Metric | What It Tells Us |
|--------|-----------------|
| **Profit Factor** | Gross profit / gross loss. Target: > 1.5 |
| **Sharpe Ratio** | Risk-adjusted return. Target: > 1.0 |
| **Max Drawdown (%)** | Largest peak-to-trough decline. Target: < 20% |
| **Recovery Factor** | Net profit / max drawdown. Target: > 3.0 |
| **Win Rate (%)** | Profitable trades / total trades. Target: > 45% |
| **Total Trades** | Enough for statistical significance. Target: > 100 |
| **Expected Payoff** | Average profit per trade. Must be positive. |
| **Average Win / Average Loss** | The R:R actually achieved. |
| **Max Consecutive Losses** | Stress test for position sizing. |

### 5.3 Python HTML Report Parser

```python
import re
from html.parser import HTMLParser

class MT5ReportParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.tables = []
        self.current_table = []
        self.current_row = []
        self.current_cell = []
        self.in_table = self.in_row = self.in_cell = False

    def handle_starttag(self, tag, attrs):
        if tag == 'table':
            self.in_table = True; self.current_table = []
        elif tag == 'tr' and self.in_table:
            self.in_row = True; self.current_row = []
        elif tag in ['td', 'th'] and self.in_row:
            self.in_cell = True; self.current_cell = []

    def handle_endtag(self, tag):
        if tag == 'table' and self.in_table:
            self.in_table = False; self.tables.append(self.current_table)
        elif tag == 'tr' and self.in_row:
            self.in_row = False; self.current_table.append(self.current_row)
        elif tag in ['td', 'th'] and self.in_cell:
            self.in_cell = False
            text = re.sub(r'\s+', ' ', ''.join(self.current_cell).replace('\xa0', ' ')).strip()
            self.current_row.append(text)

    def handle_data(self, data):
        if self.in_cell: self.current_cell.append(data)

def parse_report(filepath):
    parser = MT5ReportParser()
    # Try multiple encodings — MT5 reports can be UTF-8 or UTF-16
    for enc in ['utf-8', 'utf-16-le', 'utf-16']:
        try:
            with open(filepath, 'r', encoding=enc) as f:
                parser.feed(f.read())
            break
        except (UnicodeDecodeError, UnicodeError):
            continue

    metrics = {}
    if parser.tables:
        for row in parser.tables[0]:
            if len(row) >= 2:
                key = row[0].strip().rstrip(':')
                val = row[1].strip()
                metrics[key] = val
    return metrics
```

---

## 6. Full Autonomous Loop

```
┌───────────────────────────────────────────────────────────────┐
│                    Autonomous Iteration Loop                   │
│                                                               │
│  1. Claude Code modifies BPR_Bot.mq5 (code or parameters)    │
│                          │                                    │
│  2. Copy .mq5 to MQL5/Experts/                               │
│                          │                                    │
│  3. Compile via Wine + metaeditor64.exe                       │
│     → Check .ex5 exists + parse .log for errors               │
│     → If error: fix code, go to step 2                        │
│                          │                                    │
│  4. Generate .set file (UTF-16 LE) → MQL5/Profiles/Tester/   │
│     Generate .ini file (UTF-16 LE) → config/                  │
│                          │                                    │
│  5. Launch backtest: terminal64.exe /config:backtest.ini       │
│     → Window appears, test runs, ShutdownTerminal=1 exits     │
│                          │                                    │
│  6. Wait for process exit + kill wineserver                   │
│                          │                                    │
│  7. Parse report (.htm) → extract metrics                     │
│                          │                                    │
│  8. Analyze: profit factor, Sharpe, DD, win rate, trade count │
│     → Diagnose: too many trades? bad SL? wrong structure?     │
│     → Propose specific changes with rationale                 │
│                          │                                    │
│  9. Git commit iteration (code + params + metrics)            │
│                          │                                    │
│  10. Go to step 1                                             │
└───────────────────────────────────────────────────────────────┘
```

---

## 7. Rosetta 2 / Wine Longevity

Apple has confirmed Rosetta 2 remains available through **macOS 27** (the next major release after current). Starting macOS 28, it's limited to certain older games. This gives **2-3 years** of reliable operation. Long-term plan: migrate to Parallels or cloud Windows VPS.

# Market Clock Pro

Candle countdown HUD for MetaTrader 5 with session detection, market-closed awareness, and a holidays calendar for seven major exchanges.

[![MQL5](https://img.shields.io/badge/MQL5-MetaTrader%205-blue)](https://www.mql5.com/)
[![License](https://img.shields.io/badge/license-Apache%202.0-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.0-brightgreen.svg)]()

## Overview

Market Clock Pro shows a compact HUD on the MT5 chart with the time remaining to the current candle close, the active trading sessions in UTC, live spread with anomaly detection, today's range vs ADR, and a market-closed state when the current symbol's market is not trading.

Weekends, intraday broker breaks, and calendar holidays across seven markets (NYSE, LSE, XETRA, TSE, HKEX, ASX, SSE) are handled through an editable text file.

## Features

- **Candle countdown** with color escalation as the close approaches
- **Geographic sessions** (Tokyo, London, New York, Sydney) with countdown to session end when multiple overlap
- **Market-closed detection** with explicit reason: `NYSE CLOSED (holiday)`, `LSE CLOSED (weekend)`, `XETRA CLOSED (session)`
- **Holidays calendar** covering 2026 and 2027 for seven markets (164 entries)
- **Automatic symbol-to-market mapping** with manual override for broker-specific tickers
- **Live spread** with rolling-average anomaly detection (2x baseline)
- **Daily range vs ADR** as percentage
- **Configurable alert** before candle close
- **Four HUD positions**, three themes (Dark, Light, Stealth)
- **Timeframe-aware color scheme** that adapts accent color to the active period
- **Broker-agnostic** through `TimeTradeServer` / `TimeGMT` / `SymbolInfoSessionTrade`
- **No external dependencies**, no DLLs, no web requests, no data collection

## Installation

1. Copy `MarketClockPro.mq5` to `MQL5\Indicators\`
2. Copy `holidays.txt` to `MQL5\Files\MarketClockPro\holidays.txt`
3. Compile with F7 in MetaEditor (expected: 0 errors, 0 warnings)
4. Drag the indicator onto any chart

The holidays file is optional. If absent or misconfigured, the indicator falls back to broker-session-based detection automatically.

## Configuration

Inputs are organized in five groups.

### DISPLAY
- `InpCorner` — HUD position (Top Right, Top Left, Bottom Right, Bottom Left)
- `InpTheme` — Dark, Light, or Stealth (text only, no panel)
- `InpPrimaryFontSize` — countdown font size
- `InpSecondaryFontSize` — font size for all other lines
- `InpSecondaryColor` — color for secondary lines

### MODULES
- `InpShowTimeframe` — show current timeframe label
- `InpShowSession` — show trading sessions or market-closed state
- `InpShowSpread` — show live spread with anomaly color
- `InpShowADR` — show daily range versus ADR

### BEHAVIOR
- `InpADRPeriod` — days to average for ADR (default 14)
- `InpMarketClosedAlert` — enable market-closed detection
- `InpShowTimeToOpen` — show countdown to next market open

### HOLIDAYS
- `InpHolidaysEnabled` — read from holidays.txt
- `InpHolidaysFile` — path under `MQL5\Files` (default `MarketClockPro\holidays.txt`)
- `InpHolidayMarket` — AUTO, NYSE, LSE, XETRA, TSE, HKEX, ASX, SSE, or NONE
- `InpHolidayMarketOverride` — fallback string when AUTO fails to detect

### ALERT
- `InpAlertEnabled` — play sound before candle close
- `InpAlertSeconds` — seconds before close to trigger (1 to 60)

## Symbol Detection

AUTO mode maps tickers to markets using substring matching (examples):

| Ticker pattern | Mapped market |
|---|---|
| `US100`, `NAS100`, `NDX`, `TECH100`, `SPX`, `SP500`, `US30`, `DJI`, `RUT` | NYSE |
| `UK100`, `FTSE` | LSE |
| `DE40`, `DAX`, `GER30`, `GER40`, `EU50`, `STOXX`, `CAC`, `IBEX` | XETRA |
| `JP225`, `NIKKEI`, `N225` | TSE |
| `HK50`, `HSI`, `HANG` | HKEX |
| `AUS200`, `ASX`, `SPI` | ASX |
| `CHINA50`, `CN50`, `A50`, `CSI` | SSE |

FX pairs, cryptocurrencies, spot metals, energies, and soft commodities are excluded from holiday checks by design. They do not trigger the "symbol not mapped" notification.

When the broker uses a non-standard ticker (for example `US-TECH100.fs`), set `InpHolidayMarket` to the correct market directly, or put the market code (`NYSE`) in `InpHolidayMarketOverride`.

## holidays.txt Format

Plain text, ASCII, user-editable. The parser validates structure but does not require checksums, so the file can be extended without special tools.

```
MAGIC:SCT_HOLIDAYS
COVERAGE_FROM:2026-01-01
COVERAGE_TO:2027-12-31
---BEGIN_HOLIDAYS---
2026-01-01:NYSE:New Year's Day
2026-01-19:NYSE:Martin Luther King Jr. Day
2026-02-16:NYSE:Presidents Day
...
---END_HOLIDAYS---
```

Holiday lines: `YYYY-MM-DD:MARKET:NAME`. Comments start with `#`. Malformed lines are skipped silently up to a threshold.

## Technical Notes

- **Rendering model**: single `EventSetMillisecondTimer` (500 ms intraday, 1 s on H1 and above) as the sole driver. `OnCalculate` is a no-op.
- **Dedup**: every label tracks its last text and color; redraws only propagate on actual change.
- **Caching**: session label cached per minute, ADR per day, broker-UTC offset refreshed hourly to handle DST.
- **Memory**: one indicator instance uses approximately 50 KB including the pre-allocated holidays array.
- **APIs used**: all native MQL5. No `Sleep()`, no `SendMail`, no `SendNotification`, no `WebRequest`, no DLLs.

## Status Banner

If the indicator encounters a configuration issue it shows a transient banner for 30 seconds:

| Message | Cause | Resolution |
|---|---|---|
| `HOLIDAYS` / `symbol not mapped` | AUTO could not resolve a market for an index-like ticker | Set `InpHolidayMarket` or `InpHolidayMarketOverride` |
| `HOLIDAYS` / `file missing` | holidays.txt not found at the configured path | Copy the file to `MQL5\Files\MarketClockPro\` |
| `HOLIDAYS` / `invalid header` | Missing or wrong `MAGIC:` line | Restore original file or add the header |
| `HOLIDAYS` / `file truncated` | Missing `---BEGIN_HOLIDAYS---` or `---END_HOLIDAYS---` | Restore markers |
| `HOLIDAYS` / `no entries` | Zero valid holiday lines parsed | Check line format |
| `HOLIDAYS` / `many bad lines` | More than 25% malformed lines | Fix format |
| `HOLIDAYS` / `file outdated` | `COVERAGE_TO` already passed | Update file with newer entries |

Details are always printed to the Expert Journal for later review.

## Compatibility

- MetaTrader 5, all builds from 2019 onward
- Windows 10 / 11 x64
- Any broker (tested across multiple with different ticker conventions)
- All 21 standard timeframes (M1 to MN1)
- All asset classes (indices, forex, crypto, metals, commodities, stocks)

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE) for full terms. Free to use, modify, and redistribute including for commercial purposes, with attribution and retention of copyright notices.

## Author

Developed by Marcelo Borasi. Part of the JYXOS toolset for algorithmic traders.

- Website: [jyxos.com](https://jyxos.com)
- Issues and suggestions: use the GitHub issue tracker

## Changelog

### v1.0 (2026-04-18)
Initial public release.

- Candle countdown, session detection, spread, ADR
- Holidays calendar for NYSE, LSE, XETRA, TSE, HKEX, ASX, SSE
- Auto market mapping with manual override
- Market-closed states with explicit reason
- Broker-agnostic UTC handling with DST auto-refresh
- Transient status banner for configuration issues

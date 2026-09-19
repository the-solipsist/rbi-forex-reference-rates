# RBI Forex Reference Rates Archive (1998–present)

Gap-free historical dataset of the **Reserve Bank of India (RBI) Reference
Exchange Rates** for major currencies against the Indian Rupee (INR),
auto-updated daily at 06:00 IST by a scheduled GitHub Actions workflow.

**Coverage:** August 25, 1998 to September 18, 2026 (28.1 years)
**Total Records:** 26,929
**Total Trading Days:** 6,668

## Data

| Currency | Description | Unit | Coverage Start |
| :--- | :--- | :--- | :--- |
| **USD** | US Dollar | 1 | 1998-08-25 |
| **GBP** | Great Britain Pound | 1 | 1998-08-25 |
| **EUR** | Euro | 1 | 1999-01-04 |
| **JPY** | Japanese Yen | 100 | 1998-08-25 |
| **AED** | UAE Dirham | 1 | 2026-01-22 |
| **IDR** | Indonesian Rupiah | 10,000 | 2026-01-22 |

*EUR was introduced on 1999-01-01, but the first RBI reference rate was
published on 1999-01-04.*

## Files

1. **`rbi_forex_reference_rates_long.csv`** — long format
   (`date,currency,rate,unit`). Best for SQL and programmatic processing.
2. **`rbi_forex_reference_rates_wide.csv`** — pivoted wide format,
   currencies as columns. Best for Excel, VisiData, and plotting.
3. **`rbi_forex_reference_rates.parquet`** — columnar format for
   DuckDB, Pandas, and Polars.

## Methodology & Data Sources

The series is the RBI reference exchange rate, from two sources:

- **1998–2018**: the [RBI Reference Rate Archive](https://www.rbi.org.in/scripts/referenceratearchive.aspx).
- **2018–present**: the **FBIL reference rates** — Financial Benchmarks India
  Pvt Ltd is the official benchmark administrator, and RBI publishes FBIL's
  rates. RBI's archive page has a gap for July 2018 – March 2022, which was
  filled from the FBIL series via NSE's public API and cross-checked against
  FBIL's own public API.

Each day a workflow fetches any new trading days since the last recorded date
(using the RBI archive, falling back to the FBIL API if that fetch fails, and
cross-checking the results against FBIL), appends them, and regenerates the
long/wide CSVs and parquet. See
[`scripts/update.sh`](scripts/update.sh) and
[`.github/workflows/update.yml`](.github/workflows/update.yml).

### Validation & corrections

- **Deduplication**: data from both sources was merged and duplicates removed.
- **Zero-rate filtering**: placeholder entries (rate = 0.0000) for EUR prior to
  its introduction in January 1999 were removed.
- **Missing day correction**: fixed missing GBP/JPY data for the first date
  (1998-08-25) in early iterations.
- **Unit normalization**: consistent units (JPY per 100, IDR per 10,000).

## Usage

### Best fit at a glance

| Task | Tool |
| :--- | :--- |
| Querying & analysis | **DuckDB** — reads CSV & parquet natively; the repo's own engine |
| Charting from SQL | **ggsql** — Grammar of Graphics for SQL, DuckDB-backed |
| Programmatic analysis | **Python** — pandas/polars read the parquet |
| Interactive browsing | **VisiData** — parquet or wide CSV |
| Quick CLI plots | **Gnuplot** — wide CSV |

### DuckDB (SQL) — best for analysis

```sql
-- Annual average USD rate
SELECT YEAR(date::DATE) AS year, AVG(rate)
FROM 'rbi_forex_reference_rates_long.csv'
WHERE currency = 'USD'
GROUP BY year ORDER BY year;

-- Latest rates, straight from the parquet
SELECT * FROM 'rbi_forex_reference_rates.parquet'
WHERE date = (SELECT max(date) FROM 'rbi_forex_reference_rates.parquet');
```

### ggsql — best for charting from SQL

[ggsql](https://ggsql.org/) adds Grammar-of-Graphics clauses to SQL and pushes
computation down to DuckDB. Load the parquet into a database once, then chart:

```sql
-- one-time: build a DuckDB database from the parquet
duckdb rates.duckdb "CREATE TABLE rates AS SELECT * FROM read_parquet('rbi_forex_reference_rates.parquet');"

-- USD/INR over time
ggsql exec --reader duckdb://rates.duckdb "
SELECT date, rate FROM rates WHERE currency = 'USD'
VISUALISE date AS x, rate AS y
DRAW line
SCALE x VIA date
LABEL title => 'USD/INR RBI reference rate'"
```

### Python (pandas) — best for programmatic analysis

```python
import pandas as pd

rates = pd.read_parquet("rbi_forex_reference_rates.parquet")
usd = rates[rates.currency == "USD"].set_index("date")
usd["rate"].plot()   # needs matplotlib; the parquet also reads with polars/duckdb
```

### VisiData — interactive browsing

```bash
vd rbi_forex_reference_rates.parquet
# or the wide CSV, for side-by-side currency comparison
vd rbi_forex_reference_rates_wide.csv
```

### Gnuplot — quick plots (wide format)

```gnuplot
set datafile separator ","
plot "rbi_forex_reference_rates_wide.csv" using 1:7 with lines title "USD/INR"
```

## Copyright & License

The files in this repository are a compilation of **facts** — Reserve Bank of
India reference exchange rates — and contain no original expression. Under the
Copyright Act, 1957 (India), copyright protects only original works and
requires a modicum of creativity; a bare compilation of facts carries no such
originality. Accordingly, this data is **not copyrightable** and is in the
**public domain** — see *Eastern Book Company v. D.B. Modak*, (2008) 1 SCC 1
(holding that factual data without original expression is not protected).

To remove any residual doubt, the repository is additionally dedicated to the
public domain under the [CC0 1.0 Universal Public Domain
Dedication](https://creativecommons.org/publicdomain/zero/1.0/) — see
[`LICENSE`](LICENSE). You may copy, modify, distribute, and use the data for
any purpose, without attribution or permission.

## Disclaimer

For informational purposes only. Refer to the official RBI website for
critical financial reporting or legal purposes.

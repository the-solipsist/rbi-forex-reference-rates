# RBI Forex Reference Rates Archive (1998–present)

Gap-free historical dataset of the **Reserve Bank of India (RBI) Reference
Exchange Rates** for major currencies against the Indian Rupee (INR),
auto-updated every Monday 06:00 IST by a scheduled GitHub Actions workflow.

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

1. **`rbi_forex_reference_rates_1998_2026_long.csv`** — long format
   (`date,currency,rate,unit`). Best for SQL and programmatic processing.
2. **`rbi_forex_reference_rates_1998_2026_wide.csv`** — pivoted wide format,
   currencies as columns. Best for Excel and plotting.
3. **`rbi_forex_reference_rates_1998_2026.parquet`** — columnar format for
   DuckDB / Pandas / Polars.
4. **`RBI_FOREX_REFERENCE_RATES_DOCUMENTATION.md`** — detailed methodology.

## Methodology & Data Sources

Primary source: the [RBI Reference Rate Archive](https://www.rbi.org.in/scripts/referenceratearchive.aspx).
The historical series was built by merging and validating the RBI archive with
NSE historical data (used to fill a gap for July 2018 – March 2022).

Each Monday a workflow fetches any new trading days since the last recorded
date, appends them, and regenerates the wide CSV and parquet. See
[`scripts/update.sh`](scripts/update.sh) and
[`.github/workflows/update.yml`](.github/workflows/update.yml).

## Usage

### DuckDB (fastest)

```sql
SELECT YEAR(date::DATE) AS year, AVG(rate)
FROM 'rbi_forex_reference_rates_1998_2026_long.csv'
WHERE currency = 'USD'
GROUP BY year ORDER BY year;
```

### gnuplot (wide format)

```gnuplot
set datafile separator ","
plot "rbi_forex_reference_rates_1998_2026_wide.csv" using 1:7 with lines title "USD/INR"
```

## Disclaimer

For informational purposes only. Refer to the official RBI website for
critical financial reporting or legal purposes.

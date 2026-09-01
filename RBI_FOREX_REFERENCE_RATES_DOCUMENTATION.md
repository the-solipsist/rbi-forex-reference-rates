# RBI Forex Reference Rates Archive (1998-2026)

## Overview
This archive contains a comprehensive, gap-free historical dataset of the Reserve Bank of India (RBI) Reference Exchange Rates for major currencies against the Indian Rupee (INR). It is auto-updated daily at 06:00 IST by a scheduled GitHub Actions workflow (`scripts/update.sh`), which fetches any new trading days from the RBI Reference Rate Archive and regenerates all files.

**Coverage:** August 25, 1998 to September 1, 2026 (28.0 years)
**Total Records:** 26,833
**Total Trading Days:** 6,656

## Currencies Included
| Currency | Description | Unit | Coverage Start |
| :--- | :--- | :--- | :--- |
| **USD** | US Dollar | 1 | 1998-08-25 |
| **GBP** | Great Britain Pound | 1 | 1998-08-25 |
| **EUR** | Euro | 1 | 1999-01-04* |
| **JPY** | Japanese Yen | 100 | 1998-08-25 |
| **AED** | UAE Dirham | 1 | 2026-01-22 |
| **IDR** | Indonesian Rupiah | 10,000 | 2026-01-22 |

*\* EUR was introduced on 1999-01-01, but the first RBI reference rate was published on 1999-01-04.*

## Files Provided
1. **`rbi_forex_reference_rates_1998_2026_long.csv`**: Standard long format (date, currency, rate, unit). Best for SQL and programmatic processing.
2. **`rbi_forex_reference_rates_1998_2026_wide.csv`**: Wide format (pivoted). Currencies as columns. Best for Excel, plotting, and side-by-side comparison.
3. **`rbi_forex_reference_rates_1998_2026.parquet`**: Columnar format. Best for high-performance analysis in DuckDB, VisiData, or Python (Pandas/Polars).

## Methodology & Data Sources
This dataset was constructed by merging and validating data from two primary sources:
1. **RBI Reference Rate Archive**: Direct fetch from RBI's official archive (`https://www.rbi.org.in/scripts/referenceratearchive.aspx`).
2. **NSE Historical Data**: Used to fill a significant gap discovered in the RBI archive for the period **July 2018 to March 2022**. Data was fetched via NSE's RBI Reference Rate API.

### Validation & Corrections
- **Deduplication**: Combined data from both sources and removed duplicate entries.
- **Zero-Rate Filtering**: Removed placeholder entries (rate = 0.0000) for EUR prior to its official introduction in January 1999.
- **Missing Day Correction**: Fixed an issue where GBP and JPY data for the very first date (1998-08-25) were missing in early iterations.
- **Unit Normalization**: Ensured consistent units (JPY per 100, IDR per 10,000).

## Usage Examples

### DuckDB (Fastest)
```sql
-- Calculate annual average USD rate
SELECT YEAR(date::DATE) as year, AVG(rate) 
FROM 'rbi_forex_reference_rates_1998_2026_long.csv' 
WHERE currency='USD' 
GROUP BY year ORDER BY year;
```

### VisiData
```bash
vd rbi_forex_reference_rates_1998_2026_wide.csv
```

### gnuplot (using wide format)
```gnuplot
set datafile separator ","
plot "rbi_forex_reference_rates_1998_2026_wide.csv" using 1:7 with lines title "USD/INR"
```

## Disclaimer
This data is provided for informational purposes only. While every effort has been made to ensure accuracy and completeness through cross-validation, users should refer to the official RBI website for critical financial reporting or legal purposes.

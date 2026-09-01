#!/usr/bin/env bash
#
# update.sh — fetch new RBI reference rates and regenerate the dataset.
#
# Fetches RBI reference exchange rates since the last recorded date, appends
# them to the long-format CSV, regenerates the wide CSV and the parquet, and
# refreshes the documentation. It performs no git operations — the calling
# workflow commits and pushes.
#
# Usage:
#   bash scripts/update.sh            # fetch + regenerate
#   bash scripts/update.sh --debug    # verbose logging
#
# Data source: RBI Reference Rate Archive
#   https://www.rbi.org.in/scripts/referenceratearchive.aspx
#
# Run daily by .github/workflows/update.yml (06:00 IST).
#
set -euo pipefail

export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

DEBUG_LEVEL="${DEBUG_LEVEL:-1}"

log_info()  { if [[ "$DEBUG_LEVEL" -ge 1 ]]; then echo "[INFO]  $*"; fi; }
log_debug() { if [[ "$DEBUG_LEVEL" -ge 2 ]]; then echo "[DEBUG] $*"; fi; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug) DEBUG_LEVEL=2; shift ;;
        -h|--help)
            sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "Error: unknown option: $1" >&2; exit 1 ;;
    esac
done

# --- configuration -------------------------------------------------------
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LONG="$REPO_DIR/rbi_forex_reference_rates_1998_2026_long.csv"
WIDE="$REPO_DIR/rbi_forex_reference_rates_1998_2026_wide.csv"
PARQUET="$REPO_DIR/rbi_forex_reference_rates_1998_2026.parquet"
DOC="$REPO_DIR/RBI_FOREX_REFERENCE_RATES_DOCUMENTATION.md"

RBI_URL="https://www.rbi.org.in/scripts/referenceratearchive.aspx"
UA="Mozilla/5.0 (X11; Linux x86_64; rv:147.0) Gecko/20100101 Firefox/147.0"
CHUNK_DAYS=30

# --- helpers -------------------------------------------------------------

# URL-encode a ViewState token (only +, = and / need escaping).
enc() { echo "$1" | sed 's/+/%2B/g; s/=/%3D/g; s/\//%2F/g'; }

# Fetch one date range (DD/MM/YYYY..DD/MM/YYYY) from the RBI archive and emit
# long-format rows (date,currency,rate,unit) on stdout. Uses ViewState tokens
# from a fresh GET, as the archive page requires a POST with those tokens.
fetch_rbi_range() {
    local from_d="$1" to_d="$2"
    local page vs vsg ev response

    page=$(curl -s --max-time 30 -H "User-Agent: $UA" "$RBI_URL") || return 1
    vs=$(echo "$page"  | grep -o '__VIEWSTATE" value="[^"]*"'         | cut -d'"' -f3) || true
    vsg=$(echo "$page" | grep -o '__VIEWSTATEGENERATOR" value="[^"]*"' | cut -d'"' -f3) || true
    ev=$(echo "$page"  | grep -o '__EVENTVALIDATION" value="[^"]*"'    | cut -d'"' -f3) || true

    if [[ -z "$vs" || -z "$vsg" || -z "$ev" ]]; then
        echo "Error: could not extract ViewState tokens from RBI page" >&2
        return 1
    fi

    response=$(curl -s --compressed --max-time 60 -X POST "$RBI_URL" \
        -H "User-Agent: $UA" \
        -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
        -H "Accept-Language: en-US,en;q=0.9" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -H "Origin: https://www.rbi.org.in" \
        -H "Referer: $RBI_URL" \
        --data-raw "__EVENTTARGET=&__EVENTARGUMENT=&__VIEWSTATE=$(enc "$vs")&__VIEWSTATEGENERATOR=$(enc "$vsg")&__EVENTVALIDATION=$(enc "$ev")&UsrFontCntr%24txtSearch=&chkAll=on&txtFromDate=${from_d}&txtToDate=${to_d}&btnSubmit=+GO+") || return 1

    # RBI emits one <td height="20" ...> cell per value, in the order:
    # Date, USD, GBP, EUR, JPY, AED, IDR (newest first). Group them into rows.
    echo "$response" | grep -o '<td height="20"[^>]*>[^<]*</td>' | awk '
        function is_date(s) { return (s ~ /^[0-9][0-9]\/[0-9][0-9]\/[0-9][0-9][0-9][0-9]$/) }
        function emit() {
            if (date == "") return
            split(date, d, "/")
            iso = sprintf("%04d-%02d-%02d", d[3], d[2], d[1])
            if (usd ~ /^[0-9]+(\.[0-9]+)?$/ && usd != "0.0000") print iso ",USD," usd ",1"
            if (gbp ~ /^[0-9]+(\.[0-9]+)?$/ && gbp != "0.0000") print iso ",GBP," gbp ",1"
            if (eur ~ /^[0-9]+(\.[0-9]+)?$/ && eur != "0.0000") print iso ",EUR," eur ",1"
            if (jpy ~ /^[0-9]+(\.[0-9]+)?$/ && jpy != "0.0000") print iso ",JPY," jpy ",100"
            if (aed ~ /^[0-9]+(\.[0-9]+)?$/ && aed != "0.0000") print iso ",AED," aed ",1"
            if (idr ~ /^[0-9]+(\.[0-9]+)?$/ && idr != "0.0000") print iso ",IDR," idr ",10000"
            date=usd=gbp=eur=jpy=aed=idr=""
        }
        {
            cell = $0
            sub(/^<td height="20"[^>]*>/, "", cell)
            sub(/<\/td>$/, "", cell)
            gsub(/^[ \t]+|[ \t]+$/, "", cell)
            gsub(/&nbsp;/, "", cell)
            if (is_date(cell)) { emit(); date = cell }
            else if (date != "" && cell ~ /^[0-9]+(\.[0-9]+)?$/) {
                if      (usd == "") usd = cell
                else if (gbp == "") gbp = cell
                else if (eur == "") eur = cell
                else if (jpy == "") jpy = cell
                else if (aed == "") aed = cell
                else if (idr == "") idr = cell
            }
        }
        END { emit() }
    ' || true
}

last_date() {
    duckdb -csv -noheader -c "SELECT max(date) FROM read_csv('$1', header=true);" 2>/dev/null | tail -1
}

# --- main ----------------------------------------------------------------
last=$(last_date "$LONG")
if [[ -z "$last" ]]; then
    echo "Error: could not determine last date in $LONG" >&2
    exit 1
fi
log_info "Last recorded date: $last"

from_iso=$(date -d "$last + 1 day" +%Y-%m-%d)
to_iso=$(date +%Y-%m-%d)
log_info "Fetching $from_iso → $to_iso from RBI archive..."

from_epoch=$(date -d "$from_iso" +%s)
to_epoch=$(date -d "$to_iso" +%s)

if [[ $from_epoch -gt $to_epoch ]]; then
    log_info "Already up to date."
    exit 0
fi

tmp_rows=$(mktemp)
dedup=$(mktemp)
trap 'rm -f "$tmp_rows" "$dedup"' EXIT

cur=$from_epoch
while [[ $cur -le $to_epoch ]]; do
    cend=$((cur + (CHUNK_DAYS - 1) * 86400))
    if [[ $cend -gt $to_epoch ]]; then cend=$to_epoch; fi
    f=$(date -d "@$cur" +%d/%m/%Y)
    t=$(date -d "@$cend" +%d/%m/%Y)
    log_debug "  chunk: $f → $t"
    fetch_rbi_range "$f" "$t" >> "$tmp_rows"
    sleep 1
    cur=$((cend + 86400))
done

new_count=$(wc -l < "$tmp_rows")
if [[ "$new_count" -eq 0 ]]; then
    log_info "No new records found. Nothing to do."
    exit 0
fi
log_info "Fetched $new_count new records."

# Append to the long CSV, dropping any accidental duplicates (idempotent).
cat "$LONG" "$tmp_rows" | awk '!seen[$0]++' > "$dedup"

# Sanity: no duplicate (date,currency) pairs after the merge.
dup=$(duckdb -csv -noheader -c \
    "SELECT count(*) FROM (SELECT date, currency, count(*) c FROM read_csv('$dedup', header=true, columns={'date':'VARCHAR','currency':'VARCHAR','rate':'DOUBLE','unit':'BIGINT'}) GROUP BY date, currency HAVING c > 1);" \
    2>/dev/null | tail -1)
if [[ "$dup" != "0" ]]; then
    echo "Error: $dup duplicate (date,currency) pairs after merge — aborting." >&2
    exit 1
fi

# Regenerate the long CSV in canonical order (date, currency) and normalized
# rate formatting. The deduped merge above is append-only; this keeps the
# published file deterministically sorted.
duckdb -c "COPY (SELECT date, currency, rate, unit FROM read_csv('$dedup', header=true, columns={'date':'VARCHAR','currency':'VARCHAR','rate':'DOUBLE','unit':'BIGINT'}) ORDER BY date, currency) TO '$LONG' (HEADER, DELIMITER ',');"
log_info "Long CSV updated (sorted)."

# Regenerate derived files.
log_info "Regenerating wide CSV and parquet..."
duckdb -c "COPY (PIVOT read_csv('$LONG', header=true, columns={'date':'VARCHAR','currency':'VARCHAR','rate':'DOUBLE','unit':'BIGINT'}) ON currency IN ('AED','EUR','GBP','IDR','JPY','USD') USING first(rate) GROUP BY date ORDER BY date) TO '$WIDE' (HEADER, DELIMITER ',');"
duckdb -c "COPY (SELECT date::DATE AS date, currency, rate::DOUBLE AS rate, unit::BIGINT AS unit FROM read_csv('$LONG', header=true) ORDER BY date, currency) TO '$PARQUET' (FORMAT PARQUET);"

# Update documentation with fresh counts.
log_info "Updating documentation..."
python3 - "$LONG" "$DOC" <<'PY'
import csv, datetime, re, sys
long_path, doc_path = sys.argv[1:3]
count, dates = 0, set()
with open(long_path) as f:
    for row in csv.DictReader(f):
        count += 1
        dates.add(row['date'])
start, end = min(dates), max(dates)
years = round((datetime.date.fromisoformat(end) - datetime.date.fromisoformat(start)).days / 365.25, 1)
def fmt(d):
    return datetime.date.fromisoformat(d).strftime("%B %-d, %Y")
with open(doc_path) as f:
    text = f.read()
text = re.sub(r'\*\*Coverage:\*\* .*', f'**Coverage:** {fmt(start)} to {fmt(end)} ({years} years)', text)
text = re.sub(r'\*\*Total Records:\*\* [0-9,]+', f'**Total Records:** {count:,}', text)
text = re.sub(r'\*\*Total Trading Days:\*\* [0-9,]+', f'**Total Trading Days:** {len(dates):,}', text)
with open(doc_path, 'w') as f:
    f.write(text)
print(f"doc: {count} records, {len(dates)} trading days, {start} → {end}")
PY

log_info "Done."

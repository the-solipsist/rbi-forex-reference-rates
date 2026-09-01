#!/usr/bin/env bash
#
# zenodo_upload.sh — upload the RBI reference rates dataset to Zenodo.
#
# Creates the initial deposition on first run, then a new version on each
# subsequent run (all versions share the same concept DOI, each gets its own
# version DOI). Uploads the dataset files, sets metadata, and publishes.
#
# Usage:
#   ZENODO_TOKEN=... bash scripts/zenodo_upload.sh            # upload + publish
#   ZENODO_TOKEN=... bash scripts/zenodo_upload.sh --dry-run  # create draft, don't publish
#
# Scheduled quarterly by .github/workflows/zenodo.yml.
#
set -euo pipefail

export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API="https://zenodo.org/api"
TITLE="RBI Forex Reference Rates Archive"
LONG="$REPO_DIR/rbi_forex_reference_rates_long.csv"
FILES=(
    "rbi_forex_reference_rates_long.csv"
    "rbi_forex_reference_rates_wide.csv"
    "rbi_forex_reference_rates.parquet"
    "README.md"
)

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

if [[ -z "${ZENODO_TOKEN:-}" ]]; then
    echo "Error: ZENODO_TOKEN is not set" >&2
    exit 1
fi

auth=(-H "Authorization: Bearer $ZENODO_TOKEN")

# curl with retries and visible errors (Zenodo can be transiently flaky).
zen() {
    curl -sSf --retry 3 --retry-all-errors --retry-delay 2 "$@"
}

# --- metadata -------------------------------------------------------------
start_date="1998-08-25"
end_date=$(tail -1 "$LONG" | cut -d, -f1)
if [[ -z "$end_date" ]]; then
    echo "Error: could not determine data coverage end date" >&2
    exit 1
fi
publication_date=$(date +%Y-%m-%d)

description="Gap-free historical dataset of Reserve Bank of India (RBI) Reference Exchange Rates for major currencies (USD, GBP, EUR, JPY, AED, IDR) against the Indian Rupee (INR), covering $start_date to $end_date. Auto-updated daily from the RBI Reference Rate Archive. Files: long-format CSV (date,currency,rate,unit), wide-format CSV, and Parquet. The data are facts and are not copyrightable under Indian law (Eastern Book Company v. D.B. Modak, (2008) 1 SCC 1); the dataset is dedicated to the public domain under CC0 1.0."

metadata=$(jq -n \
    --arg title "$TITLE" \
    --arg version "$end_date" \
    --arg pubdate "$publication_date" \
    --arg start "$start_date" \
    --arg end "$end_date" \
    --arg description "$description" \
    '{title:$title, upload_type:"dataset", access_right:"open", license:"cc-zero",
      publication_date:$pubdate, version:$version, description:$description,
      creators:[{name:"Prakash, Pranesh", orcid:"0000-0002-5368-4827"}],
      keywords:["RBI","forex","exchange rates","INR","Reserve Bank of India","reference rates","parquet"],
      related_identifiers:[{relation:"isSupplementTo",
                            identifier:"https://github.com/the-solipsist/rbi-forex-reference-rates"}],
      dates:[{start:$start, end:$end, type:"Valid", description:"Data coverage"}]}')

# --- find or create deposition ---------------------------------------------
list=$(zen "${auth[@]}" "$API/deposit/depositions?size=100")
dep_id=$(echo "$list" | jq -r --arg t "$TITLE" \
    '[.[] | select(.metadata.title == $t)] | sort_by(.id) | .[-1].id // empty')

if [[ -z "$dep_id" ]]; then
    echo "No existing deposition — creating initial one..."
    resp=$(zen -X POST "${auth[@]}" -H "Content-Type: application/json" -d '{}' "$API/deposit/depositions")
    dep_id=$(echo "$resp" | jq -r .id)
else
    submitted=$(echo "$list" | jq -r --argjson id "$dep_id" '.[] | select(.id == $id) | .submitted')
    if [[ "$submitted" == "true" ]]; then
        echo "Creating new version from published deposition $dep_id..."
        resp=$(zen -X POST "${auth[@]}" "$API/deposit/depositions/$dep_id/actions/newversion")
        dep_id=$(basename "$(echo "$resp" | jq -r '.links.latest_draft')")
    else
        echo "Reusing unpublished draft $dep_id..."
    fi
fi
echo "Deposition id: $dep_id"

# --- replace files ---------------------------------------------------------
bucket=$(zen "${auth[@]}" "$API/deposit/depositions/$dep_id" | jq -r '.links.bucket')
for f in $(zen "${auth[@]}" "$API/deposit/depositions/$dep_id/files" | jq -r '.[].id'); do
    zen -X DELETE "${auth[@]}" "$API/deposit/depositions/$dep_id/files/$f" > /dev/null
done
for f in "${FILES[@]}"; do
    echo "Uploading $f..."
    zen --upload-file "$REPO_DIR/$f" "${auth[@]}" "$bucket/$f" > /dev/null
done

# --- set metadata ------------------------------------------------------------
jq -n --argjson m "$metadata" '{metadata:$m}' > /tmp/zenodo_meta.json
zen -X PUT "${auth[@]}" -H "Content-Type: application/json" \
    --data @/tmp/zenodo_meta.json "$API/deposit/depositions/$dep_id" > /dev/null

if $DRY_RUN; then
    echo "DRY RUN: draft $dep_id created and files uploaded, but NOT published."
    exit 0
fi

resp=$(zen -X POST "${auth[@]}" "$API/deposit/depositions/$dep_id/actions/publish")
echo "Published: $(echo "$resp" | jq -r '.doi_url')"

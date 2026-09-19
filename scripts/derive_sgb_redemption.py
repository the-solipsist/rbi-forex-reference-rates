#!/usr/bin/env python3
"""Derive SGB premature-redemption prices from IBJA 999 gold closes.

Why derivation instead of scraping: every RBI press release states the same
rule — redemption price is the simple average of the IBJA 999-purity gold
closing price for the three business days before the redemption date. The
price is therefore a pure function of (a) IBJA closes, which this project
already captures daily, and (b) the tranche calendar below. Each derived
price is verifiable against its RBI press release (prid recorded per row).

Example:
    python scripts/derive_sgb_redemption.py \\
        --ibja data/ibja_999_closes.csv --tranches data/sgb_tranches.csv \\
        --output data/sgb_redemption.csv
    python scripts/derive_sgb_redemption.py --help
"""

import argparse
import csv
import sys
from datetime import date, timedelta
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path


def load_closes(path: Path) -> dict[date, Decimal]:
    """Load IBJA 999 closes as {date: per-gram Decimal}.

    Accepts the full closes schema (gold_999 per 10g, as published) or the
    legacy single-column form (close_inr_per_10g). Converts per-10g to
    per-gram: redemption prices are quoted per gram of gold.
    """
    closes: dict[date, Decimal] = {}
    with path.open() as f:
        reader = csv.DictReader(l for l in f if not l.startswith("#"))
        col = ("gold_999" if "gold_999" in (reader.fieldnames or [])
               else "close_inr_per_10g")
        for row in reader:
            if row.get("date", "").strip() and row.get(col, "").strip():
                closes[date.fromisoformat(row["date"].strip())] = (
                    Decimal(row[col].strip()) / Decimal(10)
                )
    return closes


def previous_business_days(day: date, closes: dict[date, Decimal],
                           n: int = 3) -> list[date]:
    """Walk back over calendar days, keeping only days with a close."""
    found: list[date] = []
    cur = day - timedelta(days=1)
    while len(found) < n and (day - cur).days < 15:
        if cur in closes:
            found.append(cur)
        cur -= timedelta(days=1)
    return found


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--ibja", required=True,
                    help="CSV with date,close_inr_per_gram (IBJA 999)")
    ap.add_argument("--tranches", required=True,
                    help="CSV with id,tranche,redemption_date,"
                         "press_release_prid")
    ap.add_argument("--output", required=True, help="Output CSV path")
    ap.add_argument("--dry-run", action="store_true",
                    help="Compute and report without writing")
    args = ap.parse_args(argv)

    closes = load_closes(Path(args.ibja))
    out_rows: list[list[str]] = []
    missing = 0
    # Skip '#' comment lines (the calendar file documents itself up top).
    with Path(args.tranches).open() as f:
        text = "".join(l for l in f if not l.startswith("#"))
    for t in csv.DictReader(text.splitlines()):
            rdate = date.fromisoformat(t["redemption_date"].strip())
            days = previous_business_days(rdate, closes)
            if len(days) < 3:
                print(f"[WARN] only {len(days)} closes before {rdate} "
                      f"({t['tranche']})", file=sys.stderr)
                missing += 1
                continue
            # RBI rule: simple average of the three closes, in rupees.
            # IBJA publishes per 10g; closes file is per gram already.
            avg = (sum(closes[d] for d in days) / Decimal(3)).quantize(
                Decimal("1"), rounding=ROUND_HALF_UP
            )
            out_rows.append([
                t.get("id", "").strip() or t["tranche"].strip(),
                t["tranche"].strip(), rdate.isoformat(), str(avg),
                ";".join(d.isoformat() for d in sorted(days)),
                t.get("press_release_prid", "").strip(),
            ])

    if args.dry_run:
        for r in out_rows[:10]:
            print("[DRY-RUN]", ",".join(r))
        print(f"[DRY-RUN] {len(out_rows)} derived, {missing} missing")
        return 0

    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["id", "tranche", "redemption_date", "price_inr",
                    "source_days", "press_release_prid"])
        w.writerows(out_rows)
    print(f"[INFO] wrote {len(out_rows)} rows ({missing} missing) to {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

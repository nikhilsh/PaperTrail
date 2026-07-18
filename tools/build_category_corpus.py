#!/usr/bin/env python3
"""Build a Create ML text-classification corpus from correction_events.

Exports the (already anonymized) correction/confirmation events via PostgREST
using the service-role key, then pivots them into (text, label) pairs for
category classification:

- Events are grouped into "save moments": same install_id + merchant_key
  within a 2-minute window (one save writes its field events together).
- A moment yields a training example only if it carries a category value
  (corrected_value of a `category` correction, or of a `confirmed-*`
  category confirmation).
- The example text is the merchant key plus any product-name value in the
  same moment plus the document kind — the same signals the app has at
  inference time.

Usage:
  SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... build_category_corpus.py out.csv

Exits 0 with a "corpus too small" message (and no CSV) below MIN_EXAMPLES,
so the training workflow can no-op cleanly until enough data exists.
"""

import csv
import json
import os
import sys
import urllib.request

MIN_EXAMPLES = 200
WINDOW_SECONDS = 120
PAGE_SIZE = 1000


def fetch_events(base_url: str, key: str):
    rows, offset = [], 0
    while True:
        req = urllib.request.Request(
            f"{base_url}/rest/v1/correction_events"
            f"?select=install_id,merchant_key,field_name,corrected_value,document_kind,created_at"
            f"&order=created_at.asc&limit={PAGE_SIZE}&offset={offset}",
            headers={"apikey": key, "Authorization": f"Bearer {key}"},
        )
        with urllib.request.urlopen(req, timeout=60) as resp:
            page = json.load(resp)
        rows.extend(page)
        if len(page) < PAGE_SIZE:
            return rows
        offset += PAGE_SIZE


def moments(events):
    """Group events into save moments (install + merchant + 2-min window)."""
    from datetime import datetime

    def ts(row):
        return datetime.fromisoformat(row["created_at"].replace("Z", "+00:00")).timestamp()

    buckets = {}
    for row in events:
        key = (row["install_id"], row["merchant_key"])
        buckets.setdefault(key, []).append(row)

    for (install, merchant), rows in buckets.items():
        rows.sort(key=ts)
        current, current_start = [], None
        for row in rows:
            t = ts(row)
            if current_start is None or t - current_start <= WINDOW_SECONDS:
                current.append(row)
                current_start = current_start if current_start is not None else t
            else:
                yield merchant, current
                current, current_start = [row], t
        if current:
            yield merchant, current


def examples(events):
    for merchant, rows in moments(events):
        category = None
        product = None
        kind = None
        for row in rows:
            field = row["field_name"]
            if field == "category":
                category = row["corrected_value"]
            elif field == "productName":
                product = row["corrected_value"]
            if kind is None and row.get("document_kind") not in (None, "unknown"):
                kind = row["document_kind"]
        if not category:
            continue
        text = " ".join(part for part in (merchant, product, kind) if part)
        yield text, category


def main():
    out_path = sys.argv[1]
    base_url = os.environ["SUPABASE_URL"].rstrip("/")
    key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]

    events = fetch_events(base_url, key)
    pairs = list(examples(events))
    print(f"events: {len(events)}, category examples: {len(pairs)}")

    if len(pairs) < MIN_EXAMPLES:
        print(f"corpus too small (<{MIN_EXAMPLES} examples) — skipping training")
        return

    with open(out_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["text", "label"])
        writer.writerows(pairs)
    print(f"wrote {out_path}")


if __name__ == "__main__":
    main()

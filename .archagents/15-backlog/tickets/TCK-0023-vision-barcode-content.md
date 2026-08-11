---
id: TCK-0023
slug: vision-barcode-content
title: "Vision barcode — content smoke with real barcode image"
source: full-parity-backlog
created_at: 2026-08-11T04:00:00-03:00
status: done
priority: low
category: feature
effort: S
related: [TCK-0018]
---

# TCK-0023 — Vision barcode content

## Gap

Vision row is `supported` via OCR content + barcode **API path**. Barcode returned empty list for non-barcode PNG — **content** not proven.

## Work

1. Host smoke with PNG/JPEG containing a known barcode (e.g. Code128 / QR of fixed payload).
2. Assert `barcodes` non-empty with expected value (or symbology present).
3. Append evidence-log line; tighten notes on vision row if needed.

## AC

- [ ] Dual-run barcode content smoke green **or** typed VISION_BARCODE_UNAVAILABLE recorded

## Closure

DONE 2026-08-11: barcode PARITY-BARCODE-777 dual-run.

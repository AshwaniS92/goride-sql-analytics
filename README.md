# GoRide — Ride-Share SQL Analytics 🚕

25 production-style SQL queries answering business questions on a messy, merged ride-sharing database — the result of an acquisition, a parcel-line launch, and B2B onboarding in 18 months.

**Author:** Ashwani Sherawat · Data Engineering, UE Germany · 2026

## Dataset

PostgreSQL database (course-provided): **10 tables · 30K ride trips · 5K parcel deliveries · 3K customers · 800 drivers**, spanning two source systems (`goride` / `quickhop`).

## The Challenge

The data carries **14 documented real-world quirks**, including duplicate customer/driver identities, cross-system trip ID collisions, mismatched rating scales (1–5 vs 1–10), inconsistent phone formats, status enum drift, and mis-tagged payments — all of which had to be handled in SQL, not cleaned upfront.

## Highlights

- **Entity resolution** — deduplicated customers and drivers via `merged_into_*` links and `COALESCE`
- **Revenue reconciliation** — applied payment-correction flags to fix mis-tagged launch-week parcel payments
- **Fraud detection** — flagged cancelled trips with retained (never-refunded) payments using `NOT EXISTS`
- **Ghost trip audit** — matched trips against time-bounded driver-vehicle assignments
- **Per-driver-month earnings by zone** — greatest-per-group with zone-name canonicalization

## Files

`queries.sql` — all 25 queries · `outputs.md` — query results · `notes.md` — reflections on the hardest problems

## Key Lesson

With multi-source data, the query is the easy part — knowing which identity, status, and flag to trust is the real work.

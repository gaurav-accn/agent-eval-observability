# Reflection Brief — Evaluation and Observability Capstone

**Name:** Kunwar Gaurav Sahu
**Date:** 2026-11-18

> Ground every answer in your own run. When a question asks for a number, file name, or line, paste
> it from your artifacts — a reviewer should be able to find it. Answers that are correct in the
> abstract but cite nothing do not meet the bar. Keep it short and specific.

---

## 0. Environment

| Field | Value |
|---|---|
| OS & version | Ubuntu 24.04.5 LTS, kernel `6.8.0-1070-azure`, x86_64, GitHub Codespaces (`environment.txt`) |
| Python version | Python 3.14.2 (`environment.txt`) |
| Date run | 2026-11-17 (System 1 pipeline) · 2026-11-18 (Systems 2–3, all perturbations) |
| Ran any system live? (which) | Yes. System 1 `pipeline` plus both `extract` perturbation runs via `https://claude.vocareum.com` (`"HTTP/1.1 200 OK"` lines in `01-policy-pipeline/pipeline-run.txt`), and the System 2 perturbation with `--mode record`. System 3 ran offline only. |

---

## 1. Validated, routed pipeline

| Evidence | Value |
|---|---|
| Passing test count | `45 passed, 3 skipped` (the 3 `live` tests skip without a key) — `01-policy-pipeline/tests.txt` |
| Routing output file | `01-policy-pipeline/routing_decisions.json` (`"decisions_written": 9`) |
| auto_approve / human_review / spot_check counts | 0 / 8 / 1 (plus `"escalations": 1`, POL-2025-009) — `pipeline-run.txt` |

**1a. Retry boundary.** From your perturbation run (a required field removed), paste the escalation
record. How many API calls did the system make, and why is retrying a futile case worse than
escalating it?

> `01-policy-pipeline/perturb-no-premium.txt`:
> ```
> "category": "missing_source", "detected_pattern": "premium_amount_absent",
> "field": "premium_amount", "kind": "escalation", "policy_id": "POL-2025-001-NOPREM",
> "reason": "Field 'premium_amount' returned null — the source document does not contain this information. Retry is futile; escalate to human review."
> ```
> **One API call** (`grep -c "HTTP Request"` → `perturb-no-premium.txt:1`).
>
> A retry re-asks the same model about the same text, and the premium is not in that text, so no
> retry can produce a correct answer. In the best case it wastes calls and latency and returns
> `null` again. In the worst case the error feedback ("premium_amount is required") pushes the model
> to produce a plausible number, and an honest gap becomes a confident fabrication that then flows
> into routing. Escalating keeps the gap visible to a human. Retrying is reserved for failures the
> model can actually fix: in the same pipeline run, POL-2025-010's `consistency` failure
> (`premium_does_not_match_components`) was retried (repeated `validation_failed` lines), while
> POL-2025-009's `missing_source` (`endorsements_absent`) was the run's single escalation.

**1b. Reading the router.** Pick one `human_review` record from your routing output. Which of the
three signals (confidence, reviewer, integration) sent it to a human? If you had trusted the model's
confidence alone, what would have happened?

> **POL-2025-002 → `human_review`, driven by the reviewer signal alone.**
> `01-policy-pipeline/routing_decisions.json`:
> ```
> "confidence_summary": { "coverage_limit": 1.0, "deductible": 0.95, "endorsements": 1.0,
>                         "exclusions": 1.0, "policy_type": 1.0, "premium_amount": 1.0 },
> "decision": "human_review",
> "fields_below_threshold": [],
> "integration_failures": [],
> "policy_id": "POL-2025-002"
> ```
> `pipeline-run.txt`: `review_disagreement policy_id=POL-2025-002 fields=['deductible', 'coverage_limit']`
>
> The confidence signal was clean (`fields_below_threshold: []`) and there were no integration
> failures. The only thing that sent this record to a human was the independent reviewer disputing
> `deductible` and `coverage_limit`. With confidence alone, POL-2025-002 would have been
> **auto-approved**: the model claimed `1.0` on `coverage_limit` and `0.95` on `deductible`, the
> exact two fields a second model reading the same document disagreed with.
>
> For contrast, POL-2025-001 had two signals firing at once:
> `"reason": "fields_below_threshold=['endorsements']; reviewer_disagreement=['coverage_limit']"`.
> The router records *which* signals fired instead of a single score, and that makes each decision
> auditable. One caveat: the reviewer disagreed on all 8 human-review policies, with disagreements
> concentrated on `deductible` (4) and `coverage_limit` (3). A reviewer that flags 8 of 9 policies
> may be over-strict, so its disagreement rate per field needs calibrating against labels too, just
> like the extractor's confidence.

**1c. Where the aggregate lies.** Run the calibration snippet. Quote the one cell whose accuracy lags
its confidence, plus the overall figure. What does slicing by `policy_type × field` catch that a
single number hides?

> `01-policy-pipeline/calibration-report.txt`:
> ```
> umbrella  exclusions      n=2 conf=0.93 acc=0.00 brier=0.865
> OVERALL brier=0.291
> ```
> The overall 0.291 looks moderate because it averages in four well-calibrated labels
> (`auto premium_amount` brier 0.003, `home deductible` 0.010). The slice shows that one cell is
> **always wrong at 0.93 confidence**, so any auto-approve threshold at or below 0.93 would approve
> exactly the field the model never gets right. A single number tells you something is off. The
> slice tells you *which* `policy_type × field` to route to humans or give a higher threshold.

---

## 2. Schema-enforced two-pass extraction

| Evidence | Value |
|---|---|
| Passing test count | `25 passed` — `02-mortgage-extraction/tests.txt` |
| Document run | `fixtures/documents/income_sum_mismatch.txt` (also `appraisal_informal_sqft.txt`, `income_missing_bonus.txt`) |
| Classified type | `type=income_verification`, then routed to `tool=extract_income_verification` (`discrepancy-run.txt`); the appraisal document classified as `type=appraisal` (`extract-run.txt`) |

**2a. Two guarantees.** Paste your discrepancy-run output. Tool use already forces valid JSON, yet the
validator still catches a bad sum. Why are these two different guarantees? Name one error each cannot
catch.

> `02-mortgage-extraction/discrepancy-run.txt`:
> ```
> "base_monthly": 5416.67, "bonus_monthly": 1250.0, "commission_monthly": 2140.0,
> "overtime_monthly": 385.5, "other_monthly": 450.0, "stated_monthly_total": 10892.17
> "validation": { "consistent": false, "discrepancies": [
>   { "field": "total_monthly_income", "calculated": 9642.17, "stated": 10892.17, "delta": -1250.0 } ] }
> ```
> Forced tool use guarantees **shape**: every field exists and has the right type. `10892.17` is a
> perfectly valid number, so the schema is satisfied. The validator guarantees **agreement between
> fields**: it recomputes the sum and finds a $1,250 gap that no type check can see.
>
> - *What the schema cannot catch:* this exact error, values that are well-typed but internally
>   inconsistent.
> - *What the validator cannot catch:* values that are wrong but still add up (e.g. bonus read into
>   `other_monthly`; the sum is unchanged). It also cannot check anything when the total is absent:
>   `missing-field-run.txt` reports `"consistent": true` with `"stated_monthly_total": null`. That
>   `true` means "nothing to compare", not "verified".
>
> The delta also helps diagnose the error: `-1250.0` equals `bonus_monthly` exactly, which suggests
> the bonus was counted twice in the stated total.

**2b. Refusing to fabricate.** Run on a document missing a field. Paste that field's output. Why null
instead of an invented value? Point to the schema choice that allows it.

> `02-mortgage-extraction/missing-field-run.txt` (`income_missing_bonus.txt`):
> `"base_monthly": 5673.08, "bonus_monthly": null, "bonus_ytd": null`
>
> Underwriting treats an extracted number as a fact, so an invented bonus would inflate qualifying
> income. `null` keeps "the document was silent" distinct from "the document said 0". The schema
> allows this because income fields like `bonus_monthly` are **nullable unions and not in the
> required list**, so the model has a legal way to say "not stated". If the schema demanded a
> non-null number, the model would be forced to guess. This is checked by
> `test_ac_01_04_at_least_three_nullable_fields` and `test_ac_03_03_missing_bonus_returns_none`
> (both PASSED in `tests.txt`).

**2c. Normalization.** Quote one field where the source text and extracted value differ in format
("about 2,400 sq ft" → `2400`). Why normalize at extraction time rather than downstream?

> Source (`fixtures/documents/appraisal_informal_sqft.txt`, line 37):
> `Gross Living Area:   approximately 2,400 sq ft (above-grade finished)` →
> `"gross_living_area_sqft": 2400` (`02-mortgage-extraction/extract-run.txt`).
>
> The model also picked the right number among several on the page. The same document lists the
> lot as `approx. 20,037 sq ft`, the basement as `~900 sq ft total`, and the garage as `441 sq ft`,
> and only the above-grade living area went into `gross_living_area_sqft`.
>
> The extraction step is the only stage that sees the context ("about", the comma, the unit). Code
> downstream only gets a string and would need its own parser for every format a document might use.
> Normalizing once into the schema's integer type means the validator, price-per-sq-ft maths and
> comparisons all work on one representation. The rules sit in a single referenced constant
> (`test_ac_03_05_normalization_rules_is_single_referenced_constant`), so they can be audited in one
> place. The tradeoff is that "about" (the fact that the figure was approximate) is lost in the
> integer.

---

## 3. Multi-source synthesis

| Evidence | Value |
|---|---|
| Passing test count | `34 passed, 1 warning` (a chromadb `DeprecationWarning`, not a failure) — `03-supply-chain/tests.txt` |
| Briefing file | `03-supply-chain/briefing.md` (captured from `investigation-run.txt`) |
| Section the conflict landed in | **Contested** (`on_time_delivery_rate`, ⚠️ ESCALATE) |

**3a. Annotate, don't arbitrate.** Quote one conflicting-metric pair from your briefing — both values,
sources, dates. Give one way a reader is better served by the preserved conflict than by a single
reconciled number.

> `03-supply-chain/briefing.md`:
> ```
> ### on_time_delivery_rate  _[2 sources, conflicting]_  ⚠️ ESCALATE
> - escalation: high-impact metric is contested across sources
>     - 95.0 percent — supplier_audit (as of 2026-04-10)
>     - 78.0 percent — logistics (as of 2026-04-05)
> ```
> A reconciled number such as the 86.5 % average would be a figure neither source reported, and it
> would hide that our own shipment data is 17 points worse than the supplier's audit. The gap itself
> is the risk signal: it triggers the escalation, and the attribution tells the reader whom to
> question (the supplier's audit vs our logistics records) before trusting either value.

**3b. Source goes dark.** Run with `--simulate-timeout`. Paste the part of the briefing showing the
failed source. How is "unreachable" handled differently from "nothing to report," and why does the run
still finish?

> `03-supply-chain/timeout-run.txt`:
> ```
> > Sources unavailable: logistics unavailable (timeout)
> ## Incomplete
> ### late_shipment_count  _[missing source: timeout reading logistics]_
> ### production_capacity_utilization  _[missing source: no source reported this metric]_  ⚠️ ESCALATE
> ```
> The two Incomplete entries mean different things. *"timeout reading logistics"* means we could not
> ask: the value probably exists, and the fix is to retry or repair the connection. *"no source
> reported this metric"* means the sources answered and none has the data, so the fix is to find a
> new source. The run still finishes because each source read is isolated. The coordinator records
> the failure as an annotation and synthesizes from the remaining sources, because a partial briefing
> with a declared gap is more useful than no briefing.
>
> One limitation (`perturb-diff.txt`): with logistics gone, `on_time_delivery_rate` moved from
> Contested to Well-Established ("single source only", 95.0 %) and Contested became `_none_`. The
> banner is honest, but the section label now overstates certainty.

**3c. Dates as a guardrail.** Quote two claims about the same supplier with different dates. How does
requiring a date stop a time difference from reading as a contradiction?

> `03-supply-chain/briefing.md`:
> ```
> ### defect_rate_ppm  _[corroborated across 2 sources]_
>     - 180.0 ppm — supplier_audit (as of 2026-04-10)
>     - 190.0 ppm — internal_quality (as of 2026-04-08)
> ```
> Without dates, "180 vs 190" reads as two sources disagreeing. With dates, a reader sees two
> measurements taken two days apart, and a small difference between them is normal drift, which is
> why the system labels it corroborated rather than contested. Dates also make the real conflict
> something a reader can investigate. The port-strike claim (`industry_news, 2026-03-17`: strike from
> March 16 delaying deliveries five to nine days) suggests checking whether logistics' 78 % (as of
> 2026-04-05) covers the strike window while the audit's 95 % does not. Without dates, all the reader
> could conclude is that one source is wrong.

---

## 4. Synthesis

**4a. One principle.** Name the single moment in your runs (system + artifact) where *evaluate the
output, don't trust the model's word* most clearly caught something a trusting design would have
shipped.

> **System 2, `02-mortgage-extraction/discrepancy-run.txt`.** The model did its job perfectly: it
> copied `stated_monthly_total: 10892.17` exactly as printed, in valid JSON. A trusting design would
> have shipped $10,892.17 a month as the borrower's income. Recomputing the line items gave
> `calculated: 9642.17` and `delta: -1250.0`, an overstatement of about 13 % in qualifying income
> that matches a double-counted bonus. The extraction was accurate, but the document was wrong, and
> only an independent check of the output caught that.

**4b. Confidence ≠ correctness.** Pick the system where this mattered most, and explain why using
something you observed.

> **System 1**, because it is the only system whose router acts on confidence. In the calibration
> report, `umbrella exclusions` sits at `conf=0.93 acc=0.00`. In my live run, POL-2025-002 had
> `"fields_below_threshold": []`, with `coverage_limit: 1.0` and `deductible: 0.95`
> (`routing_decisions.json`), yet the reviewer disputed exactly those two fields
> (`pipeline-run.txt`). Confidence is the model grading its own work. Routing on it alone would have
> auto-approved policies that the independent signal sent to humans: with the reviewer in the loop,
> the run produced `"auto_approve": 0` out of 9 decisions.

**4c. Apply it.** Describe a real workflow where an LLM pulls structured results from messy input.
Which pattern — validated retry with escalation, independent review with deterministic routing, or
provenance-preserving conflict annotation — would you reach for first, and what would you instrument
to know when it broke?

> In identity and access management, an LLM could read free-text access-request tickets and emails
> and extract `{user, application, role/entitlement, approver, business justification, expiry}` to
> feed provisioning or access certification.
>
> I would reach for **validated retry with escalation** first, for these reasons:
> - A missing approver or justification is a `missing_source` case, like the premium in System 1. It
>   must escalate, because an invented approver is an audit failure.
> - A malformed date or unknown app ID is a format error, so it is retried with error feedback.
> - A deterministic cross-check against the IAM catalog (does this role exist for this application?)
>   plays the same part as System 2's arithmetic validator.
>
> I would instrument:
> - the escalation rate split by category (`missing_source` / format / consistency) per application
> - the retry-count distribution
> - the null rate per field
> - accuracy from a spot-check sample sliced by `application × field`, like the calibration report,
>   with an alert when any single slice drifts, since System 1 showed that the overall number hides
>   the broken cell.

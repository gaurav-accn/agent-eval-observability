# Perturbation Log

For each system, make one deliberate change to an input or configuration, predict the outcome, run
it, and record what actually happened. See the starters in the Instructions, or design your own (your
own experiment earns more credit).

---

### System 1 — validated, routed pipeline

- **Change I made (file + what I changed):** Copied `data/policies/POL-2025-001.txt` to
  `/tmp/perturb/POL-no-premium.txt` and deleted line 16, so the premium information is genuinely
  absent from the document. Diff (`01-policy-pipeline/perturb-diff.txt`):
  ```
  16d15
  <    Total Policy Premium ........................  $ 1,847.62
  ```
  I kept an untouched copy (`/tmp/perturb/POL-original.txt`) as the control and ran both live.
- **Command I ran:**
  ```
  policy-extractor extract --policy-id POL-2025-001        /tmp/perturb/POL-original.txt
  policy-extractor extract --policy-id POL-2025-001-NOPREM /tmp/perturb/POL-no-premium.txt
  grep -c "HTTP Request" perturb-original.txt perturb-no-premium.txt
  ```
- **What I predicted:** The model returns `premium_amount: null`, the validator classifies it as
  `missing_source` (not a format error), and the system escalates after a single API call, with no
  retry and no invented premium.
- **What actually happened (paste the key output line):** (`01-policy-pipeline/perturb-no-premium.txt`)
  ```
  INFO validation_failed
  "category": "missing_source",
  "detected_pattern": "premium_amount_absent",
  "field": "premium_amount",
  "kind": "escalation",
  "reason": "Field 'premium_amount' returned null — the source document does not contain this information. Retry is futile; escalate to human review."
  ```
  `grep -c "HTTP Request"` → `perturb-no-premium.txt:1`, meaning exactly one API call.
- **How this differs from the unperturbed run:** The control (`perturb-original.txt`) also made one
  call, but it returned `"kind": "extraction"`, `"premium_amount": 1847.62`, `"retry_count": 0`,
  `"validation_history": []`. Removing one line turned a clean extraction into an immediate
  escalation, and the call count stayed at 1, so the retry loop never ran. For comparison, in the
  full pipeline run (`pipeline-run.txt`) the `consistency` failure on POL-2025-010
  (`premium_does_not_match_components`) *was* retried. The retry loop runs only when the failure
  category is one that a retry can fix.

---

### System 2 — schema-enforced two-pass extraction

*(Own experiment: the reverse of the starter. I repaired the bad total instead of breaking a good
one, to check that the validator also stops flagging once the inconsistency is gone.)*

- **Change I made (file + what I changed):** Copied `fixtures/documents/income_sum_mismatch.txt` to
  `/tmp/perturb/income_total_fixed.txt` and replaced the stated monthly total `10,892.17` with the
  true line-item sum `9,642.17` in both places it appears. Diff (`02-mortgage-extraction/perturb-diff.txt`):
  ```
  37c37
  < TOTAL MONTHLY EARNINGS                         10,892.17   35,929.43
  > TOTAL MONTHLY EARNINGS                         9,642.17   35,929.43
  78c78
  < Gross Earnings (Monthly)              10,892.17    35,929.43
  > Gross Earnings (Monthly)              9,642.17    35,929.43
  ```
- **Command I ran:** (live API, because an edited document has no recorded fixture)
  ```
  mortgage-extract /tmp/perturb/income_total_fixed.txt --mode record
  ```
- **What I predicted:** Same line items as before, `stated_monthly_total: 9642.17`, and the validator
  reports `consistent: true` with no discrepancies.
- **What actually happened (paste the key output line):** (`02-mortgage-extraction/perturb-total-fixed.txt`)
  ```
  "stated_monthly_total": 9642.17
  "validation": { "consistent": true, "discrepancies": [] }
  ```
- **How this differs from the unperturbed run:** The original document (`discrepancy-run.txt`)
  produced `"consistent": false` with
  `{"field": "total_monthly_income", "calculated": 9642.17, "stated": 10892.17, "delta": -1250.0}`.
  The line items were identical in both runs (base 5416.67, bonus 1250.0, commission 2140.0,
  overtime 385.5, other 450.0), so the only thing that changed the verdict was the stated total. That
  shows the validator flags a real arithmetic mismatch, and the flag is not a side effect of anything
  else in the document. The original delta (-1250.0) equals `bonus_monthly` (1250.0), which points to
  the bonus being counted twice in the original stated total.

---

### System 3 — multi-source synthesis

- **Change I made (file + what I changed):** A configuration change rather than a data edit: I ran
  with `--simulate-timeout`, which makes the `logistics` source fail to respond.
- **Command I ran:**
  ```
  supply-chain-investigate meridian --offline                      # control
  supply-chain-investigate meridian --offline --simulate-timeout   # perturbed
  diff investigation-run.txt timeout-run.txt > perturb-diff.txt
  ```
- **What I predicted:** The run finishes rather than aborting, a banner names the failed source, and
  metrics that only logistics supplied (`late_shipment_count`) move to Incomplete.
- **What actually happened (paste the key output line):** (`03-supply-chain/timeout-run.txt`)
  ```
  > Sources unavailable: logistics unavailable (timeout)
  ## Incomplete
  ### late_shipment_count  _[missing source: timeout reading logistics]_
  ```
  The run completed and printed all three sections.
- **How this differs from the unperturbed run:** (`03-supply-chain/perturb-diff.txt`)
  - `late_shipment_count`: Well-Established (11.0 shipments, logistics) → **Incomplete** (timeout).
  - `average_lead_time_days`: "corroborated across 2 sources" → "single source only".
  - **`on_time_delivery_rate`: Contested (95.0 % supplier_audit vs 78.0 % logistics, ⚠️ ESCALATE) →
    Well-Established "single source only" at 95.0 %**, and the Contested section became `_none_`.

  I did not predict the last change. When the source that disagreed went dark, the conflict
  disappeared from the briefing and the optimistic 95 % value was promoted to "Well-Established".
  The only remaining warnings are the banner and the "single source only" tag, so a reader who
  skims the section headings would conclude that delivery performance is fine.

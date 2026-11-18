#!/usr/bin/env bash
# Builds capstone-submission/ in the layout from the project README,
# and prints the 4 values still marked ⟨VERIFY⟩ in reflection-brief.md.
set -euo pipefail

ROOT=/workspaces/agent-eval-observability
PROJ="$ROOT/Project-Evaluation and Observability Project"
EVID="$PROJ/evidence-pack"
OUT="$PROJ/capstone-submission"
P2="$ROOT/Build a Resilient Mortgage Document Extraction System/04-validate-mathematical-consistency/solution"

S1="$OUT/01-policy-pipeline";      E1="$EVID/01-policy-pipeline"
S2="$OUT/02-mortgage-extraction";  E2="$EVID/02-mortgage"
S3="$OUT/03-supply-chain";         E3="$EVID/03-supply-chain"
mkdir -p "$S1/screenshots" "$S2/screenshots" "$S3/screenshots"

static_checks() {  # $1 = evidence dir, $2 = output dir
  { echo "===== mypy ====="; cat "$1/mypy.txt"; echo; echo "===== ruff ====="; cat "$1/ruff.txt"; } > "$2/static-checks.txt"
}

# ---- root files
cp "$PROJ/reflection-brief.md" "$PROJ/perturbation-log.md" "$OUT/"
{
  cat "$EVID/environment.txt"
  echo
  echo "Setup: GitHub Codespaces. One venv per project, created inside each final-exercise solution/ folder:"
  echo "  python3 -m venv .venv && .venv/bin/pip install -e \".[dev]\""
} > "$OUT/environment.txt"

# ---- 01 policy pipeline
cp "$E1/tests.txt" "$E1/pipeline-run.txt" "$E1/routing_decisions.json" "$S1/"
cp "$E1/calibration.txt" "$S1/calibration-report.txt"
static_checks "$E1" "$S1"
cp "$E1"/perturb-*.txt "$S1/"
[ -f "$E1/sample-human-review.txt" ] && cp "$E1/sample-human-review.txt" "$S1/"

# ---- 02 mortgage (re-run in replay mode with -v so the classified document type is logged)
cp "$E2/tests.txt" "$S2/"
static_checks "$E2" "$S2"
cp "$E2/perturb-diff.txt" "$E2/perturb-total-fixed.txt" "$S2/"
cd "$P2"
.venv/bin/mortgage-extract fixtures/documents/appraisal_informal_sqft.txt --mode replay -v > "$S2/extract-run.txt" 2>&1 || true
.venv/bin/mortgage-extract fixtures/documents/income_sum_mismatch.txt     --mode replay -v > "$S2/discrepancy-run.txt" 2>&1 || true
.venv/bin/mortgage-extract fixtures/documents/income_missing_bonus.txt    --mode replay -v > "$S2/missing-field-run.txt" 2>&1 || true

# ---- 03 supply chain
cp "$E3/tests.txt" "$E3/timeout-run.txt" "$E3/perturb-diff.txt" "$S3/"
static_checks "$E3" "$S3"
cp "$E3/briefing-run.txt" "$S3/investigation-run.txt"
grep -v -E "^(Loading weights|Warning: You are sending)" "$E3/briefing-run.txt" > "$S3/briefing.md"

echo "Built: $OUT"
echo
echo "################ VALUES FOR THE ⟨VERIFY⟩ PLACEHOLDERS ################"
echo "== [0] OS (environment.txt) =="
cat "$EVID/environment.txt"
echo
echo "== [2] Classified document type (verbose logs) =="
grep -i -h -E "classif|doc(ument)?[_ ]?type" "$S2/extract-run.txt" "$S2/discrepancy-run.txt" || echo "(no classify line found — paste head of discrepancy-run.txt instead)"; head -5 "$S2/discrepancy-run.txt"
echo
echo "== [1b] POL-2025-001 in routing_decisions.json =="
grep -n -B2 -A20 '"POL-2025-001"' "$S1/routing_decisions.json" | head -40 || true
echo
echo "== [2c] sq-ft line in the appraisal source =="
grep -n -i -E "sq|square" "$P2/fixtures/documents/appraisal_informal_sqft.txt" || true

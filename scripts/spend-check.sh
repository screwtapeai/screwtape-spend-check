#!/usr/bin/env bash
# Screwtape Spend Check: calls the public Screwtape.ai API and fails on a block verdict.
# Needs curl and jq (preinstalled on GitHub-hosted runners).
set -euo pipefail

: "${ST_API_KEY:?api-key is required}"
echo "::add-mask::$ST_API_KEY"
ST_ENDPOINT="${ST_ENDPOINT:-duplicate}"
ST_FAIL_ON="${ST_FAIL_ON:-not-pass}"
ST_API_URL="${ST_API_URL:-https://screwtape.ai}"
OUT="${GITHUB_OUTPUT:-/dev/stdout}"

case "$ST_ENDPOINT" in duplicate|judge) ;; *) echo "::error::endpoint must be duplicate or judge"; exit 2 ;; esac
case "$ST_FAIL_ON" in not-pass|escalate) ;; *) echo "::error::fail-on must be not-pass or escalate"; exit 2 ;; esac

if [ -n "${ST_REQUEST_FILE:-}" ]; then
  BODY=$(jq -c . "$ST_REQUEST_FILE")
else
  if [ -n "${ST_AGENT_OUTPUT_FILE:-}" ]; then
    AGENT_OUTPUT=$(cat "$ST_AGENT_OUTPUT_FILE")
  else
    AGENT_OUTPUT="${ST_AGENT_OUTPUT:-}"
  fi
  [ -n "$AGENT_OUTPUT" ] || { echo "::error::Set agent-output, agent-output-file or request-file"; exit 2; }
  BODY=$(jq -cn \
    --arg task "${ST_TASK:-Decide whether the agent may pay this invoice.}" \
    --arg out "$AGENT_OUTPUT" \
    --arg evidence "${ST_EVIDENCE:-}" \
    --argjson checks "${ST_CHECKS:-[]}" \
    --argjson dup "${ST_DUPLICATE:-null}" \
    --arg endpoint "$ST_ENDPOINT" '
    {task: $task, agent_output: $out}
    + (if ($evidence | length) > 0 then {evidence: ($evidence | split("\n") | map(select(length > 0)))} else {} end)
    + (if ($checks | length) > 0 then {checks: $checks} else {} end)
    + (if $endpoint == "duplicate" and $dup != null then {duplicate: $dup} else {} end)')
fi

HEADERS=(-H "Authorization: Bearer $ST_API_KEY" -H "Content-Type: application/json" -H "User-Agent: screwtape-spend-check/1.0")
[ -n "${ST_IDEMPOTENCY_KEY:-}" ] && HEADERS+=(-H "Idempotency-Key: $ST_IDEMPOTENCY_KEY")

RESPONSE_FILE=$(mktemp)
STATUS=$(curl -sS -m 90 -o "$RESPONSE_FILE" -w '%{http_code}' "${HEADERS[@]}" -d "$BODY" "$ST_API_URL/v1/$ST_ENDPOINT")
if [ "$STATUS" != "200" ]; then
  echo "::error::Screwtape returned HTTP $STATUS: $(jq -r '.error.code // .error // "error"' "$RESPONSE_FILE" 2>/dev/null) $(jq -r '.error.message // ""' "$RESPONSE_FILE" 2>/dev/null)"
  exit 1
fi

field() { jq -r "$1 // \"\"" "$RESPONSE_FILE"; }
VERDICT=$(field .verdict)
ACTION=$(field .next_step.action)
ERROR_TYPE=$(field .next_step.error_type)
DUP_STATUS=$(field .duplicate.status)
RECEIPT_ID=$(field .receipt.receipt_id)
REQUEST_ID=$(field .request_id)
HINT=$(field .next_step.hint)

{
  echo "verdict=$VERDICT"
  echo "action=$ACTION"
  echo "error-type=$ERROR_TYPE"
  echo "duplicate-status=$DUP_STATUS"
  echo "receipt-id=$RECEIPT_ID"
  echo "request-id=$REQUEST_ID"
} >> "$OUT"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Screwtape spend check"
    echo "| verdict | action | reason | duplicate | receipt |"
    echo "|---|---|---|---|---|"
    echo "| $VERDICT | $ACTION | $ERROR_TYPE | ${DUP_STATUS:-n/a} | ${RECEIPT_ID:-none} |"
  } >> "$GITHUB_STEP_SUMMARY"
fi

echo "verdict=$VERDICT action=$ACTION reason=$ERROR_TYPE duplicate=${DUP_STATUS:-n/a} receipt=${RECEIPT_ID:-none}"

BLOCK=false
if [ "$ST_FAIL_ON" = "escalate" ]; then
  [ "$ACTION" = "escalate" ] && BLOCK=true
else
  [ "$ACTION" != "pass" ] && BLOCK=true
fi
case "$DUP_STATUS" in duplicate|possible_duplicate) BLOCK=true ;; esac

if [ "$BLOCK" = true ]; then
  echo "::error title=Screwtape blocked this spend::action=$ACTION reason=$ERROR_TYPE duplicate=${DUP_STATUS:-n/a}. ${HINT}"
  exit 1
fi

# Screwtape Spend Check

A GitHub Action that checks an AI agent's payment, or any agent output, with the public
[Screwtape.ai](https://screwtape.ai) API and **fails the step on a block verdict**. Use it to gate a
payment run, an invoice batch, or an agent's output before it is merged or shipped.

- Spend check: line items and tax must add up to the total, and the invoice must match your evidence.
- Duplicate-invoice check: the same invoice, or the same vendor and amount within a few days, is blocked.
- Every result carries a signed receipt id for your audit trail.

## Usage

```yaml
- uses: screwtapeai/screwtape-spend-check@v1
  with:
    api-key: ${{ secrets.SCREWTAPE_API_KEY }}
    agent-output-file: invoices/inv-1042.json
    evidence: |
      PO-77 for Acme Supplies: Widgets 400.00, Shipping 100.00, tax 95.00, total 595.00 USD.
    checks: '[{"type":"sum","parts":["items.0.amount","items.1.amount","tax"],"total":"total","tolerance":0.01}]'
```

Full workflow: [`examples/workflow.yml`](examples/workflow.yml).

Get a free key (10 calls a day) at [screwtape.ai/signup](https://screwtape.ai/signup/) and save it as the
repository secret `SCREWTAPE_API_KEY`.

## When the step fails

| Result | Step |
|---|---|
| `next_step.action` is `pass` | passes |
| `next_step.action` is `retry` or `escalate` | fails (with `fail-on: escalate`, only `escalate` fails) |
| `duplicate.status` is `duplicate` or `possible_duplicate` | always fails |
| API error (bad key, quota, invalid body) | fails |

## Inputs

| Input | Default | Description |
|---|---|---|
| `api-key` | required | Screwtape.ai API key, from a secret. |
| `endpoint` | `duplicate` | `duplicate` (spend check plus duplicate-invoice check) or `judge` (any output). |
| `task` | `Decide whether the agent may pay this invoice.` | What the agent was asked to do. |
| `agent-output` / `agent-output-file` | | The output to check, for example the invoice JSON. |
| `evidence` | | Purchase order, contract or approval text, one item per line. |
| `checks` | `[]` | JSON array of [deterministic checks](https://screwtape.ai/docs/checks/). |
| `duplicate` | vendor, invoice_id, total, currency; `store: false` | Duplicate-check paths. Set `"store": true` to remember invoices across runs. |
| `request-file` | | A complete request body; replaces the inputs above. |
| `fail-on` | `not-pass` | `not-pass` or `escalate`. |
| `idempotency-key` | | Re-runs with the same key are not charged twice. |
| `api-url` | `https://screwtape.ai` | API host. |

## Outputs

`verdict`, `action`, `error-type`, `duplicate-status`, `receipt-id`, `request-id`. A summary table is
written to the job summary.

## Requirements

`bash`, `curl` and `jq`, all preinstalled on GitHub-hosted Ubuntu and macOS runners. The key is masked in logs.

## Pricing

Free: 10 calls a day. Sandbox Evaluation Pack: $100 for 2,000 checks. Enterprise pilot: support@screwtape.ai.

## License

MIT

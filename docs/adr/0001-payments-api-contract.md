# The public API contract is the in-repo OpenAPI spec

The public Zapi API has no backend spec, SDK, or shipped surface to transcribe;
the marketing snippets are labelled illustrative. We therefore author the
contract ourselves at `content/openapi/payments.yaml` and
`content/openapi/payouts.yaml` (OpenAPI 3.1.0), and treat those files as
canonical until a backend spec exists — at which point the backend becomes the
generator and these retire to derived. The docs' API reference is generated
from them, so a field changes in the spec first, never in a page.

## Consequences

- Amounts are integer santim, currency codes uppercase (`ETB`), timestamps
  ISO 8601 UTC, JSON fields snake_case, multi-word paths kebab-case, and the
  API is path-versioned (`/v1`). Every object carries `livemode` and a typed
  identifier prefix.
- Requests carry no payer PII. Phone numbers, bank accounts, and card details
  are collected on Zapi's hosted surfaces. This is a security and PCI boundary,
  not an omission.
- Payments are push-style: one create call with `confirm`, no capture or void.
  Refunds are partial, repeatable, and capped at the captured amount.
- `Idempotency-Key` is required on every `POST`, retained for 24 hours, and a
  replay returns the original response.
- Errors use one envelope (`type`, `code`, `message`, `param`) with a closed
  code list defined in the spec.
- Webhooks are at-least-once with a per-endpoint `whsec_` secret, an HMAC
  signature over the timestamp and raw body, three delivery attempts, and
  dashboard-only refire.
- Test mode chooses outcomes on the hosted checkout. There are no `test_*`
  request parameters and no separate test endpoints.
- Payouts are the only money-out object. Recipients are onboarded in the
  dashboard and referenced by `rcp_`; the public API has no recipient
  endpoints.
- There is no SDK. `@zapi/node` is unpublished, so the docs are REST and curl
  only.
- Fees, settlement times, latency, and numeric rate limits are not published
  until a verified source exists.

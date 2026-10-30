# Research: API source of truth for docs.zapihq.com

Ticket: https://github.com/zapihq/docs.zapihq.com/issues/5
Date: 2026-10-26
Question: Where does docs.zapihq.com get its API truth from, so every endpoint, parameter, webhook event, error code, and SDK method in the new docs is real rather than invented?

## Verdict

**There is no ground truth for the public Zapi payments API anywhere in `D:\vite\zapi`.**
No OpenAPI spec, no backend repo, no SDK source, and no previously-written API docs
exist for the public API. Everything currently written about the public API lives in
the marketing site's "illustrative" snippets, which are explicitly labeled
*Illustrative API flow* / *Illustrative distribution* (self-disclaiming, not spec-grade).

The only real, spec-grade artifact in the workspace is the **internal Staff IAM API**
(OpenAPI 3.1.0, 2,068 lines) — admin identity/authorization, **not** the public
payments API. It proves the internal spec authoring conventions exist, but contains
zero payments truth.

Consequence: until the user (or the not-yet-present backend repo) supplies a spec or
the backend source, **every endpoint, parameter, webhook event, error code, and SDK
method in the new docs would be invented.** Writing the API reference realistically
requires the gaps listed at the bottom to be answered first.

## Inventory of artifacts (exhaustive, per search scope)

### 1. `D:\vite\zapi\internal.zapihq.com` — internal admin (real spec, wrong domain)

| Artifact | What it covers |
|---|---|
| `openapi.yaml` (root, 2,068 lines, OpenAPI 3.1.0, version `2026-08-26`) | Zapi Staff IAM API (internal): Departments, Roles, Permissions, Users, Auth (TOTP MFA, sessions, refresh), Grants, AuthorizationChecks (mTLS only). Full request/response schemas, cursor pagination, error responses (InvalidCursor / Unauthorized / Forbidden), bearer `staffSession` security. |
| `staff-iam.json` | Permission catalog + access tiers aligned with `openapi.yaml`. |
| `src/apiClient.ts` | Axios client for `VITE_IAM_API_URL`: bearer-token attach, 401→`/auth/refresh` rotation via HttpOnly cookie. Internal usage pattern only. |
| `docs/adr/` (5 ADRs) | Cursor pagination contract, entity schemas, form-bridge — internal IAM conventions. |
| `docs/agents/*`, `GLOSSARY.md`, `CODING_STANDARDS.md` | Repo conventions; all scoped to staff IAM. |

Key negative finding: `openapi.yaml`'s descriptions reference
`microservice_implementation/stage_1/FEATURES.md` and
`ZAPI_CORE_SYSTEM_ARCHITECTURE.md §6` — **neither file exists anywhere under
`D:\vite\zapi`** (searched by name and by directory). The public-payments backend
repo is simply not present on this machine.

### 2. `D:\vite\zapi\content\www.zapihq.com` — marketing site (illustrative claims only)

- `app/products/payments/terminal.tsx` — a `curl https://api.zapihq.com/v1/payments`
  snippet (`Bearer sk_live_...`, `amount=1000`, `currency=ETB`, response
  `{ id: "pay_9f2c1a", status: "initiated", amount, currency, checkout_url:
  "https://pay.zapihq.com/pay_9f2c1a" }`). Footer literally says **"Illustrative API
  flow"** — intentional placeholder, not spec.
- `components/common/hero/hero-terminal.tsx` — three `@zapi/node` SDK snippets:
  - `new Zapi('sk_live_...')`; `zapi.transfers.create({ amount: 5000, currency: 'etb', destination: 'acct_1Lj2...', description })`
  - `zapi.payments.create({ amount, currency, payment_method: 'tele_birr', confirm: true })`
  - `zapi.webhooks.constructEvent(req.rawBody, req.headers['zapi-signature'], 'whsec_live_...')`
  These are the only constraints on the SDK surface anywhere, and they are marketing
  copy, not library source.
- `components/common/future-grid/index.tsx` — webhook payload sample
  (`POST /webhook/zapi`, `{ "type": "payment.success", "data": { "id": "txn_12345",
  "amount": 50000, "currency": "etb", "provider": "telebirr" } }`; "idempotent JSON
  payloads… 3-try retry policy, event logging, manual webhook refiring"),
  Idempotency-Key card (`Idempotency-Key: req_9x8...`, "same 200 OK",
  "24-hour window"), test-mode card (simulated latency, mock errors, timeouts,
  webhook delays), multi-party settlement card, refund card (partial refunds;
  1,000 ETB charge).
- `app/llms.txt/route.ts` — product roster (Payments, Checkout, Payment Links,
  Billing, Invoicing, Payouts, Reporting, Tax) and pointers to
  `docs.zapihq.com/api-reference` (which 404s) and a changelog (which doesn't exist yet).
- `app/pricing/fee-calculator.tsx` — fee rates: domestic 2% ETB, international 1.5%
  (marketing pricing, constant-coded in the component).

### 3. `D:\vite\zapi\old` — nothing usable

- `old/dashboard` — Turborepo (`apps/internal` staff IAM admin, `apps/merchant`
  scaffold with **zero API calls**, `packages/{data-table,form,ui,eslint-config,typescript-config}`),
  `mock/staff-iam-mock-server.mjs` (IAM only), `staff-iam.json`.
- `old/dashboard.zapihq.com` — earlier Vite dashboard scaffold, IAM only, no public API calls.
- Grep for `api.zapihq.com`, `pay.zapihq.com`, `sk_live`, `payment.success`,
  `telebirr`, `EthSwitch`, `constructEvent`, `Idempotency-Key` across the tree
  (excluding node_modules/.next/dist/coverage/.git) hits **only** the marketing
  components above and IAM artifacts. No API-reference pages, no tutorials, no
  older docs sites.

### 4. `D:\vite\zapi\content\docs.zapihq.com` — current docs repo (empty shell)

- Pure Fumadocs starter: `content/docs/index.mdx` ("Hello World"), `test.mdx`.
  `content/docs/{api-reference,concepts,guides,integration,payment-methods}/` exist
  but are **empty directories**.
- `source.config.ts`, `app/`, and `lib/` contain **no** references to spec
  files, OpenAPI generation, or API seeds. No Fumadocs OpenAPI plugin is
  installed.
- Git history: starter scaffold + CI/agent workflow only (5 commits, no docs content).

### 5. `D:\vite\zapi\worktrees` — empty; `D:\vite\zapi\www.zapihq.com` (top level) — empty stub.

### 6. Live web

- `https://docs.zapihq.com` → Fumadocs starter ("You can open /docs and see the
  documentation"); `https://docs.zapihq.com/api-reference` → **404**.
- npm: `https://registry.npmjs.org/@zapi/node` → **404** (package not published);
  npm search shows no `@zapi` scope owner. The SDK does not exist publicly.

## Ground-truth status table

| Docs input | Ground truth exists? | Where |
|---|---|---|
| Public payments endpoints / parameters | ❌ No | Nowhere (only illustrative `{amount, currency, reference}` on `POST /v1/payments`) |
| Auth (`Authorization: Bearer sk_live/sk_test`) | ⚠️ Marketing only | `terminal.tsx`, `hero-terminal.tsx` (`sk_live_...`) |
| Webhook events | ⚠️ One event, marketing only | `payment.success` in `future-grid/index.tsx`; delivery path `POST /webhook/zapi`; 3-try retry claim |
| Webhook signature scheme | ⚠️ Marketing only | `zapi-signature` header + `whsec_live_...` + `zapi.webhooks.constructEvent` (Stripe-shaped, unverified) |
| Idempotency (key enforcement, 24h window) | ⚠️ Marketing only | `future-grid/index.tsx` (`req_9x8...`, "Same 200 OK") |
| Test mode / error simulation | ⚠️ Marketing prose only | `future-grid/index.tsx`; no canned test numbers or force-error codes anywhere |
| Refunds (partial/full) | ⚠️ Marketing prose only | `future-grid/index.tsx` refund card; no endpoint/params |
| Transfers / payouts | ⚠️ Marketing only | `hero-terminal.tsx` (`transfers.create`) |
| Multi-party settlement / virtual accounts | ⚠️ Marketing prose only | settlement diagram; no virtual-account API anywhere |
| `@zapi/node` SDK | ❌ No source; not on npm | Only the three marketing snippets |
| Error codes / error response envelope | ❌ No | Nothing public; IAM spec's error shapes are internal-only |
| Currency casing (`ETB` vs `etb`) | ❌ Inconsistent | Marketing mixes both — must be decided |
| Fee/pricing figures | ⚠️ Marketing constants | `fee-calculator.tsx` (2% domestic, 1.5% international) |

## Recommended mechanics once truth exists

The repo currently has no spec-ingestion machinery. Cleanest path: put a
`content/openapi.yaml` (or `content/openapi/` split by product) in this repo as the
single source of truth and drive both pages and SDK snippets from it (e.g. a
Fumadocs OpenAPI integration), so docs can't drift from spec. If the backend repo
lands on this machine, its route definitions/validation schemas become the source
and the spec is derived from (or co-located with) them.

## Gap list — needs user answers before API is documented as real

1. **Does the public payments backend (and its spec) exist anywhere?** If yes, where
   can it be obtained (repo, file, or export)? If it doesn't exist yet, what is its
   state and ETAabling the docs to mark explicitly-depecified endpoints?
2. **Canonical endpoint inventory**: confirm `https://api.zapihq.com/v1/...`; list
   payments (create/confirm/capture/void?), refunds (partial semantics), transfers/
   payouts, virtual accounts, settlement/split participants, balances, checkout
   sessions, webhook endpoint registration/management, test-mode triggers.
3. **Auth details**: key formats (`sk_live_*`/`sk_test_*` confirmed only as brand
   claims), request auth header, any session/edge requirements, rate limits.
4. **Webhook events**: full event enum beyond `payment.success`
   (`payment.failed`? `refund.*`? `payout.*`/`transfer.*`? `settlement.*`?),
   delivery URL, signature algorithm (HMAC-SHA256 of body + timestamp?),
   `zapi-signature` header format, retry schedule ("3 tries" — with what backoff?), refire semantics.
5. **Idempotency**: is `Idempotency-Key` mandatory on mutating endpoints? Key format
   (`req_…` planted?), 24-hour window confirm, replay response behavior quoted "Same 200 OK".
6. **Test mode specifics**: canned credentials/phone/bank numbers, error-code
   injection names, simulated latency values, webhook delay sliders — the marketing
   prose promises all of these but names none of them.
7. **Error codes**: enumerations + envelope shape (`type`/`code`/`message`?).
8. **`@zapi/node`**: does the SDK exist privately? Method names in marketing
   (`payments.create`, `transfers.create`, `webhooks.constructEvent`) need to be
   confirmed against real source or made officially "planned" in docs.
9. **Currency casing**: canonical `ETB` vs `etb` (marketing currently mixes).
10. **Changelog**: marketing's llms.txt advertises `docs.zapihq.com/changelog` —
    does the user want it in scope for the rebuild?

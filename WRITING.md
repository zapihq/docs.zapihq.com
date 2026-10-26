# Writing the Zapi docs

The contract for every page on docs.zapihq.com, so pages written in a dozen
sessions read as one hand. Read it before writing or editing anything in
`content/docs/`. Term definitions live in `GLOSSARY.md`; this file decides how
to *say* things. Edit this file only as an explicit, recorded decision — not
mid-task.

Some rows below are **docs-proposed defaults**: the public API has no
authoritative spec yet, so docs state a default and the eventual backend spec
(API-truth decision) may overturn it. When that happens, change the default
here and in samples — never copy the old lore into individual pages.

## Voice

- Address the reader as **you** — the developer building on Zapi. Instructions
  are imperative: "Pass the `Idempotency-Key` header." Never passive
  construction ("The header should be passed…").
- Zapi itself is **"we"** or **"Zapi"**, used lightly, for what Zapi's own
  systems do ("We retry each delivery three times."). Not everywhere.
- Present tense.
- **Plain, confident, precise.** Say the thing once, correctly. State the
  constraint or the value; never decorate it.
- **No unverified claims.** Performance figures (latency, fees, reconciliation
  time, availability) appear only when a verified source backs them. Anything
  not yet shipped is labeled **"planned"**; anything that doesn't execute is
  labeled **"illustrative"** — the marketing site's honesty pattern, carried
  forward. Never present a sample as a spec.

## Money

- In prose, amounts are written **`1,000 ETB`**: numeral first, thousands
  separators, uppercase ISO 4217 code after it, space-separated. Never `Br`,
  never code-as-prefix (`ETB 1,000.00`), never lowercase "birr" as a unit
  (the word "birr" may appear only when speaking about the currency
  culturally, never as a unit).
- In code, amounts are **integer minor units (santim)**: `amount: 100000` is
  1,000.00 ETB. First time a page shows a sample with an amount, gloss the
  unit in the prose next to it. *(Docs-proposed default; backend may
  override.)*
- Payload casing is likewise a docs-proposed default: currency codes
  **uppercase** (`ETB`), provider values without underscores (`telebirr`).
  This kills the current marketing mix of `'etb'`/`ETB` and
  `tele_birr`/`telebirr`.

## Names

- Object identifiers carry **typed prefixes**, always:

  | Object            | Prefix  | Example         |
  | ----------------- | ------- | --------------- |
  | Payment           | `pay_`  | `pay_9f2c1a`    |
  | Refund            | `refnd_`| `refnd_4k1q7c`  |
  | Virtual account   | `acct_` | `acct_1Lj2kf`   |
  | Idempotency key   | `req_`  | `req_9x8h2m`    |
  | Webhook secret    | `whsec_`| `whsec_live_…`  |

  `txn_` is retired everywhere, including any marketing copy a docs page
  mirrors.
- Webhook event names are **dotted lowercase `resource.state`**, anchored on
  the already-public `payment.success`. The full event lexicon is an
  API-truth decision; until it rules, don't invent events beyond what's on
  record.
- Multi-word URL path segments are **kebab-case** (`payment-links`). JSON
  fields are **snake_case**, shown as on the wire.
- The API base URL appears in full once per page (`https://api.zapihq.com/v1`);
  after that, paths only (`POST /v1/payments`).
- SDK snippets show `zapi.<resource>.<action>` exactly as the real `@zapi/node`
  source/via the API-truth decision records; they never invent methods beyond
  what's on record.

## Terminology

Definitions live in `GLOSSARY.md`. Usage rules here.

- **Merchant** = Zapi's client organization; "your business" is fine
  informally. Never "customer" for the merchant (reserved for any product
  names that emerge).
- **Payer** = the person or organization paying through a Zapi-powered flow.
  Never "user" or "buyer".
- **Payout** = the money-out product, in prose. "Transfer" is reserved for a
  distinct API object if the API-truth decision introduces one — even if the
  eventual SDK method turns out to be `transfers.create`, the **prose word
  stays Payout** (Stripe does the same). Until that resolution, never use
  both interchangeably for money-out.
- **test mode** is canonical in prose. "Sandbox" appears only when quoting a
  marketing CTA or a dashboard label.
- **telebirr**: one lowercase word, in prose and payloads. `tele_birr` is
  retired.
- Brands as written: **EthSwitch**, **private banks** named properly and
  spelled out on first use in a page (Commercial Bank of Ethiopia (CBE),
  Awash Bank, Bank of Abyssinia (BOA), Dashen Bank), and **National Bank of
  Ethiopia (NBE)** spelled out on first use.
- Dates in prose: **26 Oct 2026** (day, clipped month, year).

## Format mechanics

- Headings and page titles are **sentence case**: "Handle payment failures",
  never "Handle Payment Failures".
- Code samples carry a **one-line prose gloss immediately before the block**;
  that gloss does the explaining. Inline comments appear only when a line is
  genuinely non-obvious. No comment walls, no commented TODOs in published
  samples.

## Banned words

seamless, blazing, effortless, lightning-fast, revolutionary, world-class,
state-of-the-art, and any "fastest / most powerful" superlative without a
verified source. The marketing micro-claim pattern ("RECONCILIATION TIME: 0
MINUTES.") never appears in docs.

The contrast, as one habit:

> Bad: "The API can be utilized to facilitate seamless, lightning-fast payment
> acceptance across multiple revolutionary rails."
>
> Good: "Charge a payer's telebirr wallet exactly once, even if you retry,
> with one request to `POST /v1/payments`."

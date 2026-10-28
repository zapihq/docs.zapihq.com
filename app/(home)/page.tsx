import Link from "next/link";

import { HomeMotion } from "@/components/home/motion";

const ring =
  "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand";

const cards = [
  {
    title: "Quickstart",
    description: "Send your first payment in test mode and read the response.",
    hint: "POST /v1/payments",
    href: "/docs/quickstart",
    wide: true,
  },
  {
    title: "API reference",
    description: "Endpoints, request fields, and response shapes.",
    hint: "/v1/payments",
    href: "/docs/api-reference/payments",
  },
  {
    title: "Payment methods",
    description: "telebirr wallets, bank accounts, and cards.",
    hint: "provider",
    href: "/docs/payment-methods/telebirr",
  },
  {
    title: "Webhooks",
    description: "Receive payment.success and acknowledge it.",
    hint: "payment.success",
    href: "/docs/guides/receive-webhooks",
  },
  {
    title: "Test mode",
    description: "Simulate payments without moving money.",
    hint: "sk_test_",
    href: "/docs/guides/test-mode",
  },
] as const;

const request = `curl https://api.zapihq.com/v1/payments \\
  -H "Authorization: Bearer sk_test_..." \\
  -H "Idempotency-Key: req_9x8h2m" \\
  -d amount=100000 \\
  -d currency=ETB \\
  -d provider=telebirr \\
  -d reference=order_1042`;

const response = `{
  "id": "pay_9f2c1a",
  "status": "initiated",
  "amount": 100000,
  "currency": "ETB",
  "checkout_url": "https://pay.zapihq.com/pay_9f2c1a"
}`;

export default function HomePage() {
  return (
    <main className="flex-1">
      <HomeMotion />

      <section className="mx-auto grid w-full max-w-6xl gap-12 px-4 pt-14 pb-16 sm:pt-20 lg:grid-cols-[minmax(0,1.05fr)_minmax(0,0.95fr)] lg:items-center lg:gap-16 lg:pt-24 lg:pb-24">
        <div>
          <h1
            data-anim="hero"
            className="max-w-[16ch] text-[clamp(2.3rem,5.2vw,3.5rem)] leading-[1.03] font-semibold tracking-[-0.035em] text-balance"
          >
            One API for payments in Ethiopia.
          </h1>
          <p
            data-anim="hero"
            className="mt-6 max-w-[48ch] text-[17px] leading-[1.6] text-pretty"
          >
            Accept telebirr wallets, bank accounts, and cards. Send one request
            to{" "}
            <code className="rounded-md bg-panel-2 px-1.5 py-0.5 font-mono text-[0.86em] whitespace-nowrap">
              POST /v1/payments
            </code>{" "}
            and the payment settles to your balance.
          </p>
          <div
            data-anim="hero"
            className="mt-9 flex flex-wrap items-center gap-x-6 gap-y-3"
          >
            <Link
              href="/docs/quickstart"
              className={`inline-flex h-11 items-center rounded-full bg-brand px-6 text-sm font-medium text-brand-ink transition-colors duration-200 hover:bg-brand/90 active:translate-y-px ${ring}`}
            >
              Start the quickstart
            </Link>
            <Link
              href="/docs/api-reference/payments"
              className={`text-sm font-medium underline decoration-line underline-offset-4 transition-colors duration-200 hover:decoration-ink ${ring}`}
            >
              Read the API reference
            </Link>
          </div>
        </div>

        <div
          data-anim="card"
          data-ui
          className="overflow-hidden rounded-2xl bg-panel"
        >
          <div className="flex items-center justify-between gap-3 px-5 pt-4 pb-3">
            <code className="flex items-center gap-2 font-mono text-[13px]">
              <span className="font-semibold text-brand">POST</span>
              <span className="text-ink">/v1/payments</span>
            </code>
            <code className="hidden font-mono text-[13px] text-soft sm:block">
              api.zapihq.com
            </code>
          </div>

          <pre className="overflow-x-auto px-5 pb-5 font-mono text-[13px] leading-[1.7]">
            <code>{request}</code>
          </pre>

          <div className="bg-panel-2 px-5 pt-4 pb-5">
            <p className="flex items-center gap-2.5 text-[13px]">
              <span
                className="size-1.5 rounded-full bg-ok"
                aria-hidden="true"
              />
              <code className="font-mono text-[13px]">200</code>
              <code className="font-mono text-[13px] text-soft">
                pay_9f2c1a
              </code>
              <span className="ml-auto text-soft">initiated</span>
            </p>
            <pre className="mt-3 overflow-x-auto font-mono text-[13px] leading-[1.65] text-soft">
              <code>{response}</code>
            </pre>
          </div>
        </div>
      </section>

      <section
        data-anim="start"
        aria-labelledby="start-heading"
        className="mx-auto w-full max-w-6xl px-4 pb-20 lg:pb-28"
      >
        <div className="flex flex-wrap items-end justify-between gap-3">
          <h2
            id="start-heading"
            data-anim="head"
            className="text-2xl font-semibold tracking-[-0.02em]"
          >
            Start here
          </h2>
          <Link
            href="/docs"
            data-anim="head"
            className={`text-sm text-soft transition-colors duration-200 hover:text-ink ${ring}`}
          >
            Browse all docs
          </Link>
        </div>

        <div className="mt-8 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {cards.map((card) => (
            <Link
              key={card.title}
              href={card.href}
              data-anim="tile"
              className={`group flex flex-col rounded-2xl bg-panel p-5 transition-colors duration-200 hover:bg-panel-2 ${ring} ${
                "wide" in card ? "sm:col-span-2" : ""
              }`}
            >
              <code className="font-mono text-[13px] text-soft">
                {card.hint}
              </code>
              <span className="mt-3 text-[15px] font-medium transition-colors duration-200 group-hover:text-brand">
                {card.title}
              </span>
              <span className="mt-1.5 text-sm leading-[1.55] text-soft">
                {card.description}
              </span>
            </Link>
          ))}
        </div>
      </section>

      <footer className="bg-panel">
        <div
          data-anim="foot"
          className="mx-auto flex w-full max-w-6xl flex-col gap-6 px-4 py-10 sm:flex-row sm:items-center sm:justify-between"
        >
          <div>
            <p className="text-sm font-medium">Zapi Docs</p>
            <p className="mt-1 text-sm text-soft">
              Payments for Ethiopian merchants.
            </p>
          </div>
          <nav
            aria-label="Footer"
            className="flex flex-wrap items-center gap-x-6 gap-y-2 text-sm"
          >
            <Link
              href="/changelog"
              className={`text-soft transition-colors duration-200 hover:text-ink ${ring}`}
            >
              Changelog
            </Link>
            <a
              href="https://www.zapihq.com"
              className={`text-soft transition-colors duration-200 hover:text-ink ${ring}`}
            >
              zapihq.com
            </a>
            <a
              href="https://github.com/zapihq/docs.zapihq.com"
              className={`text-soft transition-colors duration-200 hover:text-ink ${ring}`}
            >
              GitHub
            </a>
            <a
              href="https://www.zapihq.com/legal/privacy"
              className={`text-soft transition-colors duration-200 hover:text-ink ${ring}`}
            >
              Privacy
            </a>
          </nav>
        </div>
      </footer>
    </main>
  );
}

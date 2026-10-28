# Zapi docs

The shared vocabulary of docs.zapihq.com — what each word means when Zapi
documents its own payments API. Usage rules live in `WRITING.md`.

## People

**Merchant**:
An organization that contracts with Zapi to accept payments.
_Avoid_: client, vendor, business account

**Payer**:
The person or organization that pays a merchant through Zapi.
_Avoid_: customer, user, buyer

**Recipient**:
A party a merchant sends money to through a payout — a seller, creator,
vendor, or the merchant itself — onboarded once and referenced by each
payout.
_Avoid_: payee, beneficiary

## Moving money

**Payment**:
A request to move money from a payer to a merchant, tracked through its own
lifecycle.
_Avoid_: transaction, charge, order

**Payment method**:
The instrument a payer pays with — a telebirr wallet, a bank account, or a
card — named in the API by `payment_method`: `telebirr`, `cbe`, `awash`,
`boa`, `dashen`, or `card`.
_Avoid_: channel, rail, option

**Payment gateway**:
A company that fronts many providers behind a single API, so a merchant
integrates once and accepts every payment method the gateway supports. Zapi is
a payment gateway.
_Avoid_: processor, aggregator, switch

**Provider**:
The institution that operates a payment method, such as telebirr or a bank.
EthSwitch is an interbank switch, not a payment method. A provider is not a
payment gateway.
_Avoid_: operator, PSP

**Refund**:
Money returned to a payer, in full or in part, after a payment succeeds.
_Avoid_: reversal, credit

**Payout**:
Money a merchant sends out of its Zapi balance to a recipient, tracked
through its own lifecycle.
_Avoid_: withdrawal, disbursement, cash-out

**Settlement**:
The process that makes captured funds available as a merchant balance.
_Avoid_: clearing, payout

**Virtual account**:
An account identifier that routes inbound funds to a single merchant.
_Avoid_: sub-account, wallet

## Collecting

**Checkout session**:
A hosted flow that collects one payment from a payer.
_Avoid_: checkout page, pay link

**Payment link**:
A shareable URL that opens a checkout session.
_Avoid_: pay link, checkout URL

## Events & delivery

**Event**:
A record that something happened, delivered to a merchant's webhook endpoint,
such as `payment.success`.
_Avoid_: notification, message, trigger

**Webhook endpoint**:
The merchant-owned URL registered to receive events.
_Avoid_: listener, callback URL

**Idempotency key**:
A key sent with a mutating request that makes retries of that request safe and
effective once.
_Avoid_: request ID, dedup key

## Modes

**test mode**:
The mode in which payments run with simulated funds and mock failures, no real
money involved.
_Avoid_: sandbox, staging

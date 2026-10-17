# Founding Keeper checkout boundary · $14.99 once

An **optional** one-time supporter purchase. Core animal records, journaling, camera shortcuts, reminders and backup/export remain free regardless of supporter status.

`supabase/migrations/20261017_03_supporter_entitlements.sql` prepares a read-only owner-scoped entitlement record and a private event-deduplication ledger. It does **not** charge cards, grant premium access, create a payment button, or decide which provider to use. During beta, the four themes and printable previews remain visible as clearly labeled samples.

To activate **later**, select a real billing provider, configure its $14.99 USD *one-time* product on the provider's dashboard, create checkout sessions server-side bound to an authenticated `auth.uid()`, and verify signed webhook events using a server-only signing secret. Verify the provider's **actual** transaction status, amount 1499 cents and currency USD server-side. Apply grants/refunds/revocations using a service-only operation and dedupe unique provider event IDs. The app can then query its **own** `keeper_entitlements` row; never unlock from a client `localStorage` boolean, query-string flag, theme selection or checkout redirect alone. Restore purchases on re-login from the same owner row. Test tampered amount, replayed webhook, refund, chargeback and a second keeper. Confirm billing taxes, receipts, support and refund policy before checkout goes live.

There is intentionally no provider secret, checkout URL or payment link in this package.

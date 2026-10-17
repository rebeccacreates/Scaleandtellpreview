# Scale & Tell · V3.18 release gates (October 17, 2026)

## Locally completed in this package
- [x] Preserve approved visual assets and free-core / one-time optional $14.99 pack language
- [x] Add backend source for authenticated push enrollment/opt-out, test alert, due-only batch, local-hour and daily deduplication
- [x] Add separate cron activation SQL, privacy-first generic notification, and keep paid preview disabled
- [x] Harden failed opt-out, sign-out and category sync in web client
- [x] Add provider-neutral, owner-readable, server-writable supporter entitlement schema (checkout remains inactive)
- [x] Run JS syntax and in-memory UI regression tests (see `TEST_STATUS.md`)

## Staging validation still required; NOT remotely verified
- [ ] Review and run the appropriate database migrations against **staging only**; verify RLS for account A/account B, private photos, and RPC grants
- [ ] Deploy `care-push`, set VAPID keypair and 32-byte+ cron secret privately; test unauthorized config/test/dispatch; confirm `config` is `ready:true` only when configured
- [ ] Test opt-in/out, category changes, expired provider endpoint, rate-limited test, due vs completed item filtering, timezones and 5 PM default in staging
- [ ] Create Vault secrets, activate pg_cron + pg_net using `ACTIVATE_CRON_AFTER_TESTS.sql` only after tests pass; check job/log/error monitoring
- [ ] Test signed-in mobile PWA (Home Screen iPhone, Android) with browser closed; verify notification permission and deep link
- [ ] Independently export originals; test two accounts, cross-device photos, stale-revision conflict, offline pending changes, manual restore and merge review
- [ ] Test imports, add/edit/delete, photos and all printable layouts on actual phone with blank/populated journal
- [ ] Finalize data retention/privacy/minors/provider disclosures and deletion verification/end-to-end removal, including private bucket objects
- [ ] Connect real, server-verified one-time purchase provider and refund/restore entitlements; pack beta previews are not a sale
- [ ] Confirm support routing, uptime/quotas, operational costs, error tracking, rollback, official preview URL and owner approval
- [ ] Public GitHub repository remains untouched until an explicit go/no-go after staging tests

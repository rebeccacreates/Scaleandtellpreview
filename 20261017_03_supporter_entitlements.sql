-- Staging foundation for OPTIONAL one-time Founding Keeper Pack. No checkout or access is activated.
-- Run only after reviewing the existing project schema. A payment webhook must verify
-- provider signatures/server-side charge currency, amount and refund state BEFORE writing.
begin;
create table public.keeper_entitlements (
 user_id uuid not null references auth.users(id) on delete cascade,
 sku text not null check (sku in ('founding_keeper')),
 status text not null check (status in ('active','refunded','revoked')),
 provider text not null check (length(provider) between 2 and 40),
 provider_purchase_id text not null check (length(provider_purchase_id) between 6 and 200),
 verified_at timestamptz not null,
 updated_at timestamptz not null default now(),
 primary key(user_id,sku),
 unique(provider,provider_purchase_id)
);
alter table public.keeper_entitlements enable row level security;
revoke all on public.keeper_entitlements from public,anon,authenticated;
grant select on public.keeper_entitlements to authenticated;
create policy keeper_entitlements_read_own on public.keeper_entitlements
 for select to authenticated using ((select auth.uid())=user_id);

create table public.supporter_billing_events (
 provider text not null,
 event_id text not null,
 user_id uuid references auth.users(id) on delete set null,
 handled_at timestamptz not null default now(),
 primary key(provider,event_id)
);
alter table public.supporter_billing_events enable row level security;
revoke all on public.supporter_billing_events from public,anon,authenticated;
-- SERVER ONLY: service/secret backend handles signed, idempotent provider events.
commit;

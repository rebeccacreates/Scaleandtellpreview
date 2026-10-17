-- STAGING ONLY. Apply AFTER 01_keeper_state.sql. Requires pgcrypto for gen_random_uuid (available by default on hosted Supabase).
-- No scheduled delivery is enabled merely by applying this migration.
begin;
create table public.care_push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null unique check (length(endpoint) between 32 and 2048),
  p256dh text not null check (length(p256dh) between 70 and 200),
  auth_secret text not null check (length(auth_secret) between 10 and 100),
  timezone text not null default 'UTC',
  categories text[] not null default array['feeding','shed','enclosure','other']::text[],
  reminder_hour smallint not null default 17 check (reminder_hour between 0 and 23),
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint valid_categories check (categories <@ array['feeding','shed','enclosure','other']::text[])
);
create index care_push_enabled_idx on public.care_push_subscriptions (enabled, reminder_hour) where enabled;
alter table public.care_push_subscriptions enable row level security;
revoke all on public.care_push_subscriptions from public, anon, authenticated;
-- No client SELECT, INSERT, UPDATE or DELETE. Owner writes only via validated RPC.

create table public.care_push_deliveries (
  id uuid primary key default gen_random_uuid(),
  subscription_id uuid not null references public.care_push_subscriptions(id) on delete cascade,
  local_date date not null,
  status text not null default 'claimed' check (status in ('claimed','sent','retry')),
  attempts smallint not null default 1 check (attempts between 1 and 3),
  claimed_at timestamptz not null default now(),
  sent_at timestamptz,
  last_error text,
  unique (subscription_id,local_date)
);
alter table public.care_push_deliveries enable row level security;
revoke all on public.care_push_deliveries from public, anon, authenticated;

create table public.care_push_test_limits (
  user_id uuid primary key references auth.users(id) on delete cascade,
  last_sent_at timestamptz not null default now()
);
alter table public.care_push_test_limits enable row level security;
revoke all on public.care_push_test_limits from public, anon, authenticated;

create or replace function public.care_push_register(
  p_endpoint text, p_p256dh text, p_auth text, p_timezone text,
  p_categories text[], p_reminder_hour integer
) returns void language plpgsql security definer set search_path='' as $$
declare v_host text; v_record uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required' using errcode='28000'; end if;
  -- Validate push-service destination to avoid an authenticated user's endpoint being an SSRF primitive.
  if p_endpoint is null or length(p_endpoint) not between 32 and 2048
     or p_endpoint !~ '^https://[A-Za-z0-9.-]+/' or (p_endpoint ~ '[@#[:space:]]' or strpos(p_endpoint, chr(92)) > 0) then
    raise exception 'Invalid push endpoint' using errcode='22023';
  end if;
  v_host := lower(substring(p_endpoint from '^https://([A-Za-z0-9.-]+)/'));
  if not (v_host in ('fcm.googleapis.com','updates.push.services.mozilla.com')
      or v_host ~ '(^|\.)push\.apple\.com$'
      or v_host ~ '(^|\.)notify\.windows\.com$') then
    raise exception 'Push provider is not supported in this staging build' using errcode='22023';
  end if;
  if p_p256dh !~ '^[A-Za-z0-9_-]{70,200}$' or p_auth !~ '^[A-Za-z0-9_-]{10,100}$'
     or p_timezone is null or not exists (select 1 from pg_catalog.pg_timezone_names where name = p_timezone)
     or p_reminder_hour is null or p_reminder_hour not between 0 and 23
     or p_categories is null or not (p_categories <@ array['feeding','shed','enclosure','other']::text[])
  then raise exception 'Invalid reminder settings' using errcode='22023'; end if;
  -- A subscription may not be silently transferred to another keeper account.
  if exists (select 1 from public.care_push_subscriptions where endpoint=p_endpoint and user_id<>auth.uid())
  then raise exception 'This device subscription belongs to another account. Unsubscribe on that account first.' using errcode='23505'; end if;
  insert into public.care_push_subscriptions(user_id,endpoint,p256dh,auth_secret,timezone,categories,reminder_hour)
  values(auth.uid(),p_endpoint,p_p256dh,p_auth,p_timezone,p_categories,p_reminder_hour)
  on conflict(endpoint) do update set p256dh=excluded.p256dh, auth_secret=excluded.auth_secret,
    timezone=excluded.timezone,categories=excluded.categories,reminder_hour=excluded.reminder_hour,
    enabled=true,updated_at=now()
  where public.care_push_subscriptions.user_id=auth.uid()
  returning id into v_record;
  if v_record is null then raise exception 'Device registration was not saved' using errcode='23505'; end if;
end $$;
revoke all on function public.care_push_register(text,text,text,text,text[],integer) from public, anon;
grant execute on function public.care_push_register(text,text,text,text,text[],integer) to authenticated;

create or replace function public.care_push_unregister(p_endpoint text)
returns void language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null then raise exception 'Sign in required' using errcode='28000'; end if;
  delete from public.care_push_subscriptions where user_id=auth.uid() and endpoint=p_endpoint;
end $$;
revoke all on function public.care_push_unregister(text) from public, anon;
grant execute on function public.care_push_unregister(text) to authenticated;

-- Maximum one test push per keeper per minute, regardless of device or browser.
create or replace function public.care_push_claim_test(p_endpoint text)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_ok boolean;
begin
  if auth.uid() is null or not exists(select 1 from public.care_push_subscriptions
    where user_id=auth.uid() and endpoint=p_endpoint and enabled) then return false; end if;
  insert into public.care_push_test_limits(user_id,last_sent_at) values(auth.uid(),now())
  on conflict(user_id) do update set last_sent_at=now()
  where public.care_push_test_limits.last_sent_at < now()-interval '60 seconds'
  returning true into v_ok;
  return coalesce(v_ok,false);
end $$;
revoke all on function public.care_push_claim_test(text) from public, anon;
grant execute on function public.care_push_claim_test(text) to authenticated;

-- Called with SERVICE ROLE, never from the browser. Return only active, unfinished, due tasks;
-- one private GENERIC summary per device per local day (no animal names in lock-screen alerts).
create or replace function public.care_push_claim_due(p_limit integer default 100)
returns table(delivery_id uuid, subscription_id uuid, endpoint text, p256dh text, auth_secret text,
              local_date date, due_count bigint)
language sql security definer set search_path='' as $$
  with eligible as (
    select s.id subscription_id,s.endpoint,s.p256dh,s.auth_secret,
      (now() at time zone s.timezone)::date as local_date,
      (select count(*) from pg_catalog.jsonb_array_elements(
        case when pg_catalog.jsonb_typeof(k.payload->'entries')='array'
          then k.payload->'entries' else '[]'::jsonb end) as task(item)
       where task.item->>'section'='Calendar'
         and coalesce(task.item->>'done','false') <> 'true'
         and task.item->>'date' ~ '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$'
         and task.item->>'date' <= ((now() at time zone s.timezone)::date)::text
         and (case
           when lower(task.item->>'detail') ~ '(feed|prey)' then 'feeding'
           when lower(task.item->>'detail') ~ '(shed|molt)' then 'shed'
           when lower(task.item->>'detail') ~ '(enclosure|humidity|temperature|clean)' then 'enclosure'
           else 'other' end) = any(s.categories)
      ) as due_count
    from public.care_push_subscriptions s
    join public.keeper_state k on k.user_id=s.user_id
    where s.enabled and extract(hour from now() at time zone s.timezone)=s.reminder_hour
    order by s.id
  ), claimed as (
    insert into public.care_push_deliveries(subscription_id,local_date)
    select e.subscription_id,e.local_date from eligible e
    where e.due_count > 0 and not exists (
      select 1 from public.care_push_deliveries d
      where d.subscription_id=e.subscription_id and d.local_date=e.local_date
      and (d.status='sent' or d.attempts>=3
           or d.status='retry' and d.claimed_at >= now()-interval '10 minutes'
           or d.status='claimed' and d.claimed_at >= now()-interval '15 minutes')
    )
    order by e.subscription_id limit least(greatest(p_limit,1),100)
    on conflict(subscription_id,local_date) do update
      set status='claimed', attempts=public.care_push_deliveries.attempts+1,claimed_at=now(),last_error=null
    where (public.care_push_deliveries.status='retry' and public.care_push_deliveries.claimed_at < now()-interval '10 minutes'
           or public.care_push_deliveries.status='claimed' and public.care_push_deliveries.claimed_at < now()-interval '15 minutes')
      and public.care_push_deliveries.attempts<3
    returning id,subscription_id,local_date
  )
  select c.id,e.subscription_id,e.endpoint,e.p256dh,e.auth_secret,e.local_date,e.due_count
  from claimed c join eligible e on e.subscription_id=c.subscription_id and e.local_date=c.local_date;
$$;
revoke all on function public.care_push_claim_due(integer) from public, anon, authenticated;
grant execute on function public.care_push_claim_due(integer) to service_role;

create or replace function public.care_push_finish(p_delivery_id uuid,p_sent boolean,p_gone boolean default false,p_error text default null)
returns void language plpgsql security definer set search_path='' as $$
declare v_sub uuid;
begin
  update public.care_push_deliveries set status=case when p_sent then 'sent' else 'retry' end,
    sent_at=case when p_sent then now() else null end,last_error=left(p_error,200), claimed_at=now()
  where id=p_delivery_id and status='claimed' returning subscription_id into v_sub;
  if p_gone and v_sub is not null then
    update public.care_push_subscriptions set enabled=false,updated_at=now() where id=v_sub;
  end if;
end $$;
revoke all on function public.care_push_finish(uuid,boolean,boolean,text) from public, anon, authenticated;
grant execute on function public.care_push_finish(uuid,boolean,boolean,text) to service_role;
commit;

-- Scale & Tell Cloud Foundation: first migration for a NEW Supabase project.
-- Run in your own Supabase project's SQL Editor AFTER reviewing it.
-- No service-role key is needed or safe to embed in the web application.
-- Designed to run ONCE on a new, empty staging project.

begin;

create table if not exists public.keeper_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  schema_version integer not null default 1 check (schema_version between 1 and 1000),
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload) = 'object'),
  revision bigint not null default 1 check (revision > 0),
  updated_at timestamptz not null default now()
);

-- Reject public/anonymous access and enable owner-only row permissions.
revoke all on public.keeper_state from public, anon;
-- Browsers can READ their own row, but must use the revision-checked RPC to write.
-- This prevents direct updates from bypassing conflict protection.
revoke insert, update, delete on public.keeper_state from authenticated;
grant select on public.keeper_state to authenticated;
alter table public.keeper_state enable row level security;

create policy "keeper_state_read_own" on public.keeper_state
  for select to authenticated using ((select auth.uid()) = user_id);
-- One atomic, revision-checked SECURITY DEFINER operation.
-- Only signed-in users may execute it; the function uses auth.uid() and
-- NEVER accepts an arbitrary account ID. The owner must be trusted.
-- The account ID is ALWAYS
-- taken from auth.uid(), never supplied by the browser.
create or replace function public.save_keeper_state(
  p_expected_revision bigint,
  p_schema_version integer,
  p_payload jsonb
)
returns table(saved boolean, new_revision bigint)
language plpgsql
security definer
set search_path = ''
as $$
declare v_revision bigint;
begin
  if auth.uid() is null then
    raise exception 'Sign in required' using errcode = '28000';
  end if;
  if p_schema_version is null or p_schema_version not between 1 and 1000
     or p_payload is null or jsonb_typeof(p_payload) <> 'object'
     or octet_length(p_payload::text) > 5000000 then
    raise exception 'Invalid snapshot. Photos belong in private object storage.' using errcode = '22023';
  end if;

  if p_expected_revision = 0 then
    insert into public.keeper_state (user_id, schema_version, payload, revision, updated_at)
      values (auth.uid(), p_schema_version, p_payload, 1, now())
    on conflict (user_id) do nothing
    returning revision into v_revision;
  elsif p_expected_revision > 0 then
    update public.keeper_state
       set schema_version = p_schema_version,
           payload = p_payload,
           revision = revision + 1,
           updated_at = now()
     where user_id = auth.uid() and revision = p_expected_revision
    returning revision into v_revision;
  else
    raise exception 'Expected revision must be zero or greater' using errcode = '22023';
  end if;

  return query select v_revision is not null, v_revision;
end;
$$;
revoke all on function public.save_keeper_state(bigint, integer, jsonb) from public, anon;
grant execute on function public.save_keeper_state(bigint, integer, jsonb) to authenticated;

-- Private photo bucket: individual user ID is the FIRST folder in every path.
-- Example: <auth-user-uuid>/<photo-uuid>.webp
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('scale-tell-private', 'scale-tell-private', false, 5242880,
        array['image/webp','image/jpeg','image/png'])
on conflict (id) do nothing;

create policy "scale_tell_photos_read_own" on storage.objects
  for select to authenticated
  using (bucket_id = 'scale-tell-private'
    and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "scale_tell_photos_insert_own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'scale-tell-private'
    and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "scale_tell_photos_update_own" on storage.objects
  for update to authenticated
  using (bucket_id = 'scale-tell-private'
    and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'scale-tell-private'
    and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "scale_tell_photos_delete_own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'scale-tell-private'
    and (storage.foldername(name))[1] = (select auth.uid())::text);

-- This script intentionally has no public read policies for keeper data or photos.

commit;

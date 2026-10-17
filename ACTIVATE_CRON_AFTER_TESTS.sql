-- Do not run until staging's care-push config/test paths and VAPID secrets are verified.
-- Enable pg_cron and pg_net in the Supabase Dashboard and create these three Vault secrets first:
-- scale_push_project_url = staging API URL, e.g. https://<staging-project-ref>.supabase.co
-- scale_push_publishable_key = staging project's public publishable key
-- scale_push_cron_secret = EXACT SAME long random value as SCALE_PUSH_CRON_SECRET in Edge Function secrets
-- Create secrets in Dashboard > Database > Vault; never paste a secret directly into this SQL file.
-- This 5-minute trigger supports each keeper's selected LOCAL hour, default 5 PM.
select cron.schedule(
  'scale-tell-staging-care-push',
  '*/5 * * * *',
  $$
    select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name='scale_push_project_url') || '/functions/v1/care-push',
      headers := jsonb_build_object(
        'Content-Type','application/json',
        'apikey',(select decrypted_secret from vault.decrypted_secrets where name='scale_push_publishable_key'),
        'Authorization','Bearer '||(select decrypted_secret from vault.decrypted_secrets where name='scale_push_cron_secret')
      ),
      body := '{"action":"dispatch"}'::jsonb,
      timeout_milliseconds := 15000
    ) as request_id;
  $$
);
-- To PAUSE the staging scheduler: select cron.unschedule('scale-tell-staging-care-push');

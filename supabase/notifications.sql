-- Schema + RLS + realtime for the notifications table (PORTAL-OWNED)
-- =================================================================
-- This is the canonical, **target-based** schema the admin portal writes to and
-- the `send-push` Edge Function fans out over FCM topics. The app reads these
-- rows back to populate its in-app inbox (lib/services/notification_service.dart).
--
-- The portal/admin inserts a row choosing a target:
--   target = 'all'                      -> broadcast (FCM topic "all")
--   target = 'user',  target_value = <auth-uid>  -> one user (topic "user_<uid>")
--   target = 'group', target_value = <group key> -> a group
-- e.g.
--   insert into public.notifications (title, body, target)
--   values ('New badge!', 'You earned the Painter badge', 'all');
--
-- Run the whole block in the Supabase Dashboard -> SQL Editor. It DROPS and
-- recreates the table, so only run it when the table is empty / being (re)set up.
--
-- NOTE: there is NO per-recipient row and NO read flag. The app filters by
-- `target` client-side (broadcasts + rows addressed to the signed-in user) and
-- tracks "seen" locally (a per-user watermark file) for its unread bell badge.

-- 1) Table (drop first so a stale/incompatible shape is replaced cleanly) -----
drop table if exists public.notifications cascade;

create table public.notifications (
  id           uuid primary key default gen_random_uuid(),
  title        text not null,
  body         text not null,
  target       text not null default 'all'  check (target in ('all', 'user', 'group')),
  target_value text not null default '',
  status       text not null default 'sent' check (status in ('sent', 'failed', 'scheduled')),
  sent_at      timestamptz not null default now()
);

-- 2) Row Level Security ----------------------------------------------
-- The portal grants full access to any signed-in user (a SELECT policy is
-- required or the list comes back empty). NOTE: `using (true)` lets any
-- authenticated client read/write every row — including other users' `target =
-- user` notifications. That's the portal's current design; the app compensates
-- by only showing `all` + its own rows. Tighten here if stronger isolation is
-- needed (would require coordinating with the portal's insert path).
alter table public.notifications enable row level security;

drop policy if exists "authenticated full access" on public.notifications;
create policy "authenticated full access"
  on public.notifications
  for all
  to authenticated
  using (true)
  with check (true);

-- 3) Realtime (the portal's notification list subscribes via .stream()) -------
alter publication supabase_realtime add table public.notifications;

-- 4) Refresh the PostgREST schema cache (clears any cached PGRST204/42703) -----
notify pgrst, 'reload schema';

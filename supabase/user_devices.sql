-- Schema + RLS for device push tokens (Firebase Cloud Messaging)
-- =================================================================
-- The app (lib/services/push_notification_service.dart) upserts one row per
-- device on login / token refresh and deletes it on sign-out. The `send-push`
-- Edge Function reads these tokens (service role) to deliver a notification to
-- every device a user is signed in on.
--
-- Run this in the Supabase Dashboard -> SQL Editor. It is idempotent.

-- 1) Table -----------------------------------------------------------
create table if not exists public.user_devices (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid()
               references auth.users (id) on delete cascade,
  -- The FCM registration token is globally unique; the unique constraint lets
  -- the client upsert with `onConflict: 'fcm_token'` so re-registering the same
  -- device updates in place instead of piling up duplicate rows.
  fcm_token  text not null unique,
  platform   text not null check (platform in ('ios', 'android', 'web')),
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists user_devices_user_id_idx
  on public.user_devices (user_id);

-- 2) Row Level Security: each user manages only their own devices ----
alter table public.user_devices enable row level security;

drop policy if exists "user_devices_select_own" on public.user_devices;
create policy "user_devices_select_own"
  on public.user_devices
  for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "user_devices_insert_own" on public.user_devices;
create policy "user_devices_insert_own"
  on public.user_devices
  for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "user_devices_update_own" on public.user_devices;
create policy "user_devices_update_own"
  on public.user_devices
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "user_devices_delete_own" on public.user_devices;
create policy "user_devices_delete_own"
  on public.user_devices
  for delete
  to authenticated
  using (auth.uid() = user_id);

-- Note: the `send-push` function uses the service-role key, which bypasses RLS,
-- so it can read every target user's tokens regardless of these policies.

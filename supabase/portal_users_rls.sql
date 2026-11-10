-- Row Level Security for public.portal_users
-- =================================================================
-- The app (lib/services/auth_service.dart -> _syncPortalUser) upserts
--   { id, email, full_name }  keyed on id (= the Supabase auth user's UUID)
-- on every login. For that write to succeed once RLS is on, each authenticated
-- user must be allowed to create and update ONLY their own row.
--
-- Run this in the Supabase Dashboard -> SQL Editor. It is idempotent.
--
-- NOTE: enabling RLS locks the table down to the policies below. If anything
-- currently reads portal_users with the anon/publishable key, add an explicit
-- anon SELECT policy too — by default this setup allows reads of one's OWN row
-- only.

alter table public.portal_users enable row level security;

-- Create / refresh own row on login (id must equal the caller's auth uid).
drop policy if exists "portal_users_insert_own" on public.portal_users;
create policy "portal_users_insert_own"
  on public.portal_users
  for insert
  to authenticated
  with check (auth.uid() = id);

-- Update own row on subsequent logins.
drop policy if exists "portal_users_update_own" on public.portal_users;
create policy "portal_users_update_own"
  on public.portal_users
  for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- Read back own row (needed if you later chain .select() on the upsert,
-- or read the profile in the Account screen).
drop policy if exists "portal_users_select_own" on public.portal_users;
create policy "portal_users_select_own"
  on public.portal_users
  for select
  to authenticated
  using (auth.uid() = id);

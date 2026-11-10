-- Schema + RLS for in-app user feedback
-- =================================================================
-- The app inserts a row when a user sends feedback — from Account -> "Send
-- feedback", or from the contextual sentiment prompt shown after a positive
-- moment (a saved drawing / a solved puzzle). The portal/admin reads them with
-- the service-role key. Run in the Supabase Dashboard -> SQL Editor (idempotent).

-- 1) Table -----------------------------------------------------------
create table if not exists public.feedback (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  category    text not null default 'other'
                check (category in ('bug', 'suggestion', 'praise', 'other')),
  -- Optional quick sentiment from the gate prompt (😍/😐/😞). Null for feedback
  -- sent straight from the Account form.
  sentiment   text check (sentiment in ('happy', 'neutral', 'sad')),
  message     text not null default '',
  platform    text,                   -- ios / android / web / ...
  app_version text,                   -- reserved for later (package_info)
  created_at  timestamptz not null default now()
);

create index if not exists feedback_created_idx
  on public.feedback (created_at desc);

-- 2) Row Level Security ----------------------------------------------
-- A signed-in user may INSERT their own feedback (and only their own). There is
-- deliberately NO select policy: rows are read by the portal/admin via the
-- service-role key (which bypasses RLS), so one user can't read another's.
alter table public.feedback enable row level security;

drop policy if exists "feedback_insert_own" on public.feedback;
create policy "feedback_insert_own"
  on public.feedback
  for insert
  to authenticated
  with check (auth.uid() = user_id);

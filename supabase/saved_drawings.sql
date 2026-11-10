-- Schema + RLS + Storage for user-saved drawings
-- =================================================================
-- The app (lib/services/saved_drawing_service.dart -> SavedDrawingService.save)
-- uploads the finished PNG to the `saved_drawings` storage bucket under
--   <auth-uid>/<timestamp>.png
-- and inserts one row per save into public.saved_drawings.
--
-- Run this in the Supabase Dashboard -> SQL Editor. It is idempotent.

-- 1) Table -----------------------------------------------------------
create table if not exists public.saved_drawings (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid()
                  references auth.users (id) on delete cascade,
  name          text,
  image_url     text not null,
  file_path     text not null,
  template_name text,
  created_at    timestamptz not null default now()
);

create index if not exists saved_drawings_user_created_idx
  on public.saved_drawings (user_id, created_at desc);

-- 2) Row Level Security: each user owns only their own rows ----------
alter table public.saved_drawings enable row level security;

drop policy if exists "saved_drawings_insert_own" on public.saved_drawings;
create policy "saved_drawings_insert_own"
  on public.saved_drawings
  for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "saved_drawings_select_own" on public.saved_drawings;
create policy "saved_drawings_select_own"
  on public.saved_drawings
  for select
  to authenticated
  using (auth.uid() = user_id);

-- Editing a saved drawing in place (Repaint -> Save) repoints the row at a new
-- render. Without this UPDATE policy the change is silently blocked by RLS.
drop policy if exists "saved_drawings_update_own" on public.saved_drawings;
create policy "saved_drawings_update_own"
  on public.saved_drawings
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "saved_drawings_delete_own" on public.saved_drawings;
create policy "saved_drawings_delete_own"
  on public.saved_drawings
  for delete
  to authenticated
  using (auth.uid() = user_id);

-- 3) Storage bucket --------------------------------------------------
-- Public bucket so getPublicUrl() works for sharing. Flip `public` to false and
-- switch the app to createSignedUrl() if you want private artwork.
insert into storage.buckets (id, name, public)
values ('saved_drawings', 'saved_drawings', true)
on conflict (id) do update set public = excluded.public;

-- Each user may write / update / delete only inside their own <auth-uid>/ folder.
drop policy if exists "saved_drawings_storage_insert_own" on storage.objects;
create policy "saved_drawings_storage_insert_own"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'saved_drawings'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "saved_drawings_storage_update_own" on storage.objects;
create policy "saved_drawings_storage_update_own"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'saved_drawings'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "saved_drawings_storage_delete_own" on storage.objects;
create policy "saved_drawings_storage_delete_own"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'saved_drawings'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Public read of objects in this bucket (so getPublicUrl / shared links work).
drop policy if exists "saved_drawings_storage_read_public" on storage.objects;
create policy "saved_drawings_storage_read_public"
  on storage.objects
  for select
  to public
  using (bucket_id = 'saved_drawings');

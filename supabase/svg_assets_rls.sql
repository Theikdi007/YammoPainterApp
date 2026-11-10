-- Row Level Security for public.svg_assets
-- =================================================================
-- The app reads this table (SvgAssetService.fetch) to populate AR overlay
-- presets, painting templates, and puzzle sample photos. The galleries show
-- INACTIVE rows as locked (and block opening them in the app), so signed-in
-- users need SELECT on *all* rows — active and inactive. The active/locked
-- distinction is enforced in the UI, not by RLS.
--
-- Run this in the Supabase Dashboard -> SQL Editor. Idempotent. Writes stay
-- restricted to the portal (service role), which bypasses RLS.

alter table public.svg_assets enable row level security;

-- Any signed-in user can read all assets (active = free, inactive = locked).
-- Replaces the older active-only policy.
drop policy if exists "svg_assets_read_active" on public.svg_assets;
drop policy if exists "svg_assets_read_all" on public.svg_assets;
create policy "svg_assets_read_all"
  on public.svg_assets
  for select
  to authenticated
  using (true);

-- OPTIONAL: also expose assets to anonymous (not-signed-in) users, e.g. if you
-- ever show templates before login. Uncomment to enable.
-- drop policy if exists "svg_assets_read_all_anon" on public.svg_assets;
-- create policy "svg_assets_read_all_anon"
--   on public.svg_assets
--   for select
--   to anon
--   using (true);

-- Supabase Realtime for public.svg_assets
-- =================================================================
-- The app subscribes to this table (SvgAssetService.watch) so the Painting,
-- AR preset, and Puzzle galleries update live when the portal adds a row or
-- flips `is_active`. For that, the table must be in the `supabase_realtime`
-- publication.
--
-- Run this in the Supabase Dashboard -> SQL Editor (or toggle the table on under
-- Database -> Replication -> supabase_realtime). Safe to re-run.
--
-- Realtime respects RLS, so subscribers only receive rows they may SELECT —
-- with svg_assets_read_all (using (true)) that's every row. See
-- supabase/svg_assets_rls.sql.

do $$
begin
  alter publication supabase_realtime add table public.svg_assets;
exception
  when others then
    -- Already a member (or publication owned elsewhere) — nothing to do.
    raise notice 'svg_assets realtime: %', sqlerrm;
end $$;

-- Optional but recommended so UPDATE/DELETE events carry enough identity for
-- the client stream to match rows reliably:
alter table public.svg_assets replica identity full;

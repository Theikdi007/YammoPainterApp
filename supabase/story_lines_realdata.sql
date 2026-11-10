-- Portal-managed "real data" columns for story_lines, so the grid card shows a
-- REAL "NEW" flag and a REAL view/paint count instead of client-derived values.
-- =================================================================
--
-- Run in the Supabase Dashboard -> SQL Editor. Idempotent (safe to re-run).
--
-- After running:
--   * is_new (boolean, default false) — the portal flips this true on stories it
--     wants badged. Until it's true, no NEW badge shows on that card.
--   * view_count (integer, nullable) — set per story; the card renders it as the
--     fire chip (e.g. 1200 -> "1.2k"). Leave NULL to hide the chip for a story.

alter table public.story_lines
  add column if not exists is_new     boolean not null default false,
  add column if not exists view_count integer;

comment on column public.story_lines.is_new     is 'Portal-controlled NEW badge shown on the grid card.';
comment on column public.story_lines.view_count is 'Real popularity count shown as the card fire chip; NULL hides it.';

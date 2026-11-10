-- Story Lines for the creative app — each story groups related "photos"
-- (svg_assets rows in the same category) under a title + description.
-- =================================================================
--
-- Run this in the Supabase Dashboard -> SQL Editor. Idempotent.
-- 1. Creates the story_lines table.
-- 2. Enables RLS so signed-in users have full access.
-- 3. Adds it to the supabase_realtime publication so the app gets live updates.
-- 4. Adds story_line_id → story_lines FK to the existing svg_assets table.

-- ---- 1. Table ------------------------------------------------------------

create table if not exists public.story_lines (
  id          uuid primary key default gen_random_uuid(),
  title       text not null,
  description text not null default '',
  category    text not null check (category in ('Drawing', 'Painting', 'Puzzle')),
  target_app  text not null,
  image_path  text not null,
  image_url   text not null default '',
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

alter table public.story_lines enable row level security;

-- ---- 2. RLS policy -------------------------------------------------------

drop policy if exists "authenticated full access" on public.story_lines;
create policy "authenticated full access"
  on public.story_lines
  for all
  to authenticated
  using (true)
  with check (true);

-- ---- 3. Realtime ---------------------------------------------------------

do $$
begin
  alter publication supabase_realtime add table public.story_lines;
exception
  when others then
    raise notice 'story_lines realtime: %', sqlerrm;
end $$;

alter table public.story_lines replica identity full;

-- ---- 4. Link svg_assets to story_lines -----------------------------------

alter table public.svg_assets
add column if not exists story_line_id uuid references public.story_lines(id) on delete set null;

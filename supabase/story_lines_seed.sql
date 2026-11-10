-- Seed story_lines + LINK existing svg_assets to them.
-- =================================================================
-- The app's story flow is:  Stories list  ->  tap a story  ->  its
-- photos (svg_assets linked via story_line_id)  ->  tap a photo  ->
-- the canvas (Painting / AR / Puzzle). For that last-but-one step to
-- show anything, each svg_assets row must point at a story_lines row
-- through `story_line_id`. That column is service-role-writable only
-- (see svg_assets_rls.sql), so set it here in the SQL Editor — not the app.
--
-- Run in the Supabase Dashboard -> SQL Editor. Idempotent: safe to re-run.
-- It will:
--   1. Ensure ONE story exists per category (Drawing / Painting / Puzzle),
--      creating it with a sensible title/description if missing.
--   2. Give each story a cover image from the first asset in its category.
--   3. Link every still-unlinked svg_assets row in each category to that
--      category's story (only rows where story_line_id IS NULL are touched,
--      so anything you've linked by hand in the portal is left alone).

do $$
declare
    cats text[] := array['Drawing', 'Painting', 'Puzzle'];
    cat  text;
    story_id uuid;
    cover    text;
    titles jsonb := jsonb_build_object(
        'Drawing',  'Trace & Draw',
        'Painting', 'Coloring Fun',
        'Puzzle',   'Puzzle Photos'
    );
    descs jsonb := jsonb_build_object(
        'Drawing',  'Project these photos over your camera and trace them by hand.',
        'Painting', 'Tap a picture to color it your way.',
        'Puzzle',   'Turn these photos into jigsaw puzzles.'
    );
begin
    foreach cat in array cats loop
        -- Cover image: first (active-first, then by name) asset URL in category.
        select public_url into cover
        from svg_assets
        where category = cat and coalesce(public_url, '') <> ''
        order by is_active desc, name
        limit 1;

        -- Reuse an existing story for this category, or create one.
        select id into story_id
        from story_lines
        where category = cat
        order by created_at
        limit 1;

        if story_id is null then
            insert into story_lines
                (title, description, category, target_app, image_path, image_url)
            values (
                titles->>cat,
                descs->>cat,
                cat,
                cat,                       -- target_app (unused by the app; category is fine)
                coalesce(cover, ''),       -- image_path (NOT NULL)
                coalesce(cover, '')        -- image_url (preferred cover)
            )
            returning id into story_id;
        else
            -- Backfill cover / target_app only where empty (don't clobber portal edits).
            update story_lines
            set image_url  = coalesce(nullif(image_url, ''), cover),
                image_path = case when image_path = '' then coalesce(cover, '') else image_path end,
                target_app = case when target_app = '' then cat else target_app end
            where id = story_id;
        end if;

        -- Link every unlinked asset in this category to the story.
        update svg_assets
        set story_line_id = story_id
        where category = cat and story_line_id is null;
    end loop;
end $$;

-- ---- Verify (run separately, or after the block above) --------------------
-- How many assets are linked vs unlinked per category, and how many stories:
--   select category,
--          count(*) filter (where story_line_id is null)     as unlinked,
--          count(*) filter (where story_line_id is not null) as linked
--   from svg_assets group by category order by category;
--   select category, count(*) from story_lines group by category order by category;

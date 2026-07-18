-- ══════════════════════════════════════════════════════════════
-- Task 9: Supabase Storage for product images
-- Run once in the Supabase SQL editor. Safe to re-run.
-- ══════════════════════════════════════════════════════════════

-- 1. Create the bucket (public read).
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'product-images',
  'product-images',
  true,
  5242880, -- 5 MB per file (client compresses to ~1600px JPEG ~80% first)
  ARRAY['image/jpeg','image/png','image/webp']
)
ON CONFLICT (id) DO UPDATE
  SET public = true,
      file_size_limit = 5242880,
      allowed_mime_types = ARRAY['image/jpeg','image/png','image/webp'];

-- 2. RLS policies on storage.objects for this bucket.
--    Public read; authenticated (logged-in admin) write/update/delete.

DROP POLICY IF EXISTS "product-images public read"  ON storage.objects;
DROP POLICY IF EXISTS "product-images admin insert" ON storage.objects;
DROP POLICY IF EXISTS "product-images admin update" ON storage.objects;
DROP POLICY IF EXISTS "product-images admin delete" ON storage.objects;

CREATE POLICY "product-images public read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'product-images');

CREATE POLICY "product-images admin insert"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'product-images' AND auth.role() = 'authenticated');

CREATE POLICY "product-images admin update"
  ON storage.objects FOR UPDATE
  USING     (bucket_id = 'product-images' AND auth.role() = 'authenticated')
  WITH CHECK(bucket_id = 'product-images' AND auth.role() = 'authenticated');

CREATE POLICY "product-images admin delete"
  ON storage.objects FOR DELETE
  USING (bucket_id = 'product-images' AND auth.role() = 'authenticated');

-- 3. Verify: the bucket should appear and be public.
SELECT id, name, public, file_size_limit FROM storage.buckets WHERE id='product-images';

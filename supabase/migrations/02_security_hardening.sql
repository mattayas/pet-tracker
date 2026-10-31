-- ==========================================
-- 1. TRIGGER FUNCTION HARDENING
-- ==========================================

-- SECURITY DEFINER functions must pin search_path to avoid
-- object hijacking through a user-controlled schema.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    INSERT INTO public.profiles (id, first_name)
    VALUES (
        new.id,
        new.raw_user_meta_data->>'first_name'
    );
    RETURN new;
END;
$$;

-- ==========================================
-- 2. CONSTRAINTS & INDEXES
-- ==========================================

-- Cascade deletes so removing a user or a pet cleans up
-- dependent rows instead of failing.
ALTER TABLE profiles DROP CONSTRAINT profiles_id_fkey;
ALTER TABLE profiles ADD CONSTRAINT profiles_id_fkey
FOREIGN KEY (id) REFERENCES auth.users (id) ON DELETE CASCADE;

ALTER TABLE pets DROP CONSTRAINT pets_owner_id_fkey;
ALTER TABLE pets ADD CONSTRAINT pets_owner_id_fkey
FOREIGN KEY (owner_id) REFERENCES profiles (id) ON DELETE CASCADE;

ALTER TABLE scans DROP CONSTRAINT scans_pet_id_fkey;
ALTER TABLE scans ADD CONSTRAINT scans_pet_id_fkey
FOREIGN KEY (pet_id) REFERENCES pets (id) ON DELETE CASCADE;

-- Reject impossible coordinates, and half-filled positions.
ALTER TABLE scans ADD CONSTRAINT scans_latitude_range
CHECK (latitude BETWEEN -90 AND 90);
ALTER TABLE scans ADD CONSTRAINT scans_longitude_range
CHECK (longitude BETWEEN -180 AND 180);
ALTER TABLE scans ADD CONSTRAINT scans_position_complete
CHECK ((latitude IS NULL) = (longitude IS NULL));

CREATE INDEX pets_owner_id_idx ON pets (owner_id);
CREATE INDEX scans_pet_id_scanned_at_idx ON scans (pet_id, scanned_at DESC);

-- ==========================================
-- 3. POLICIES
-- ==========================================

-- Pets were readable by anyone, which exposed every pet and
-- its owner_id. Public access now goes through get_pet_public.
-- Both names are dropped: the remote database was created by hand
-- with a different policy name than 01_init_schema.sql.
DROP POLICY IF EXISTS anyone_can_view_pets ON pets;
DROP POLICY IF EXISTS "Anyone can view pets" ON pets; -- noqa: RF05

-- Scans were readable by anyone on the remote database, which
-- exposed every GPS position. Owners keep owners_can_view_pet_scans.
DROP POLICY IF EXISTS "Anyone can view scans" ON scans; -- noqa: RF05

-- Scans were insertable by anyone without limits. Public
-- inserts now go through record_scan.
DROP POLICY IF EXISTS anyone_can_create_scans ON scans;

CREATE POLICY users_can_view_own_profile ON profiles
FOR SELECT USING (id = auth.uid());

CREATE POLICY users_can_update_own_profile ON profiles
FOR UPDATE USING (id = auth.uid()) WITH CHECK (id = auth.uid());

CREATE POLICY owners_can_view_own_pets ON pets
FOR SELECT USING (owner_id = auth.uid());

CREATE POLICY owners_can_create_own_pets ON pets
FOR INSERT WITH CHECK (owner_id = auth.uid());

CREATE POLICY owners_can_update_own_pets ON pets
FOR UPDATE USING (owner_id = auth.uid()) WITH CHECK (owner_id = auth.uid());

CREATE POLICY owners_can_delete_own_pets ON pets
FOR DELETE USING (owner_id = auth.uid());

-- ==========================================
-- 4. PUBLIC RPC (used by the scan page)
-- ==========================================

-- Returns only what a finder needs to see for a given pet.
CREATE OR REPLACE FUNCTION public.get_pet_public(p_pet_id UUID)
RETURNS TABLE (name TEXT, is_lost BOOLEAN)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT pets.name, pets.is_lost
    FROM public.pets
    WHERE pets.id = p_pet_id;
$$;

-- Records a scan after validating the pet and applying a
-- per-pet rate limit to prevent flooding.
CREATE OR REPLACE FUNCTION public.record_scan(
    p_pet_id UUID,
    p_latitude NUMERIC,
    p_longitude NUMERIC
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    recent_scans INTEGER;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.pets WHERE id = p_pet_id) THEN
        RAISE EXCEPTION 'pet not found' USING ERRCODE = 'P0002';
    END IF;

    SELECT count(*) INTO recent_scans
    FROM public.scans
    WHERE
        pet_id = p_pet_id
        AND scanned_at > now() - INTERVAL '10 minutes';

    IF recent_scans >= 10 THEN
        RAISE EXCEPTION 'too many scans' USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO public.scans (pet_id, latitude, longitude)
    VALUES (p_pet_id, p_latitude, p_longitude);
END;
$$;

REVOKE ALL ON FUNCTION public.get_pet_public(UUID) FROM public;
REVOKE ALL ON FUNCTION public.record_scan(UUID, NUMERIC, NUMERIC) FROM public;
GRANT EXECUTE ON FUNCTION public.get_pet_public(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_scan(
    UUID, NUMERIC, NUMERIC
) TO anon, authenticated;

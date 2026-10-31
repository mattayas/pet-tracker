-- ==========================================
-- 1. TRIGGER FUNCTION NOT CALLABLE THROUGH THE API
-- ==========================================

-- handle_new_user is only meant to run from the auth.users
-- trigger, never through /rest/v1/rpc.
REVOKE EXECUTE ON FUNCTION public.handle_new_user()
FROM public, anon, authenticated;

-- ==========================================
-- 2. POLICIES: EVALUATE auth.uid() ONCE PER QUERY
-- ==========================================

-- Wrapping auth.uid() in a sub-select lets Postgres cache it
-- instead of calling it for every row.

DROP POLICY users_can_view_own_profile ON profiles;
CREATE POLICY users_can_view_own_profile ON profiles
FOR SELECT USING (id = (SELECT auth.uid()));

DROP POLICY users_can_update_own_profile ON profiles;
CREATE POLICY users_can_update_own_profile ON profiles
FOR UPDATE USING (id = (SELECT auth.uid()))
WITH CHECK (id = (SELECT auth.uid()));

DROP POLICY owners_can_view_own_pets ON pets;
CREATE POLICY owners_can_view_own_pets ON pets
FOR SELECT USING (owner_id = (SELECT auth.uid()));

DROP POLICY owners_can_create_own_pets ON pets;
CREATE POLICY owners_can_create_own_pets ON pets
FOR INSERT WITH CHECK (owner_id = (SELECT auth.uid()));

DROP POLICY owners_can_update_own_pets ON pets;
CREATE POLICY owners_can_update_own_pets ON pets
FOR UPDATE USING (owner_id = (SELECT auth.uid()))
WITH CHECK (owner_id = (SELECT auth.uid()));

DROP POLICY owners_can_delete_own_pets ON pets;
CREATE POLICY owners_can_delete_own_pets ON pets
FOR DELETE USING (owner_id = (SELECT auth.uid()));

DROP POLICY owners_can_view_pet_scans ON scans;
CREATE POLICY owners_can_view_pet_scans ON scans
FOR SELECT USING (
    EXISTS (
        SELECT 1 FROM pets
        WHERE
            pets.id = scans.pet_id -- noqa: RF01
            AND pets.owner_id = (SELECT auth.uid())
    )
);

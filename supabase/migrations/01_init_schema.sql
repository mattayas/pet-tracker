-- ==========================================
-- 1. TABLES CREATION
-- ==========================================

-- Profiles table: Extends Supabase auth.users to store
-- public user data.
CREATE TABLE profiles (
    id UUID REFERENCES auth.users NOT NULL PRIMARY KEY,
    first_name TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone(
        'utc'::TEXT, now()
    ) NOT NULL
);

-- Pets table: Stores animal details and links them to
-- their owners.
CREATE TABLE pets (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    owner_id UUID REFERENCES profiles (id) NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    photo_url TEXT,
    is_lost BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone(
        'utc'::TEXT, now()
    ) NOT NULL
);

-- Scans table: Records the GPS history when a pet's QR
-- code is scanned.
CREATE TABLE scans (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    pet_id UUID REFERENCES pets (id) NOT NULL,
    latitude NUMERIC,
    longitude NUMERIC,
    scanned_at TIMESTAMP WITH TIME ZONE DEFAULT timezone(
        'utc'::TEXT, now()
    ) NOT NULL
);

-- ==========================================
-- 2. ROW LEVEL SECURITY (RLS)
-- ==========================================

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE pets ENABLE ROW LEVEL SECURITY;
ALTER TABLE scans ENABLE ROW LEVEL SECURITY;

-- ==========================================
-- 3. AUTOMATION & TRIGGERS
-- ==========================================

-- Create a function to automatically insert a row into
-- 'profiles' upon registration. Retrieves the ID and metadata.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, first_name)
    VALUES (
        new.id,
        new.raw_user_meta_data->>'first_name'
    );
    RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger automatically after each INSERT on auth.users
CREATE OR REPLACE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- ==========================================
-- 4. SECURITY POLICIES
-- ==========================================

-- Allow anyone on the internet to insert a scan
CREATE POLICY anyone_can_create_scans ON scans FOR INSERT WITH CHECK (true);

-- Allow only the pet owner to view the scan history
CREATE POLICY owners_can_view_pet_scans ON scans FOR SELECT USING (
    EXISTS (
        SELECT 1 FROM pets
        WHERE
            pets.id = scans.pet_id -- noqa: RF01
            AND pets.owner_id = auth.uid()
    )
);
-- Allow reading pets infos (to show pets name while scanning)
CREATE POLICY anyone_can_view_pets ON pets FOR SELECT USING (true);

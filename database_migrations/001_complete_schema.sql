-- ============================================================================
-- CHUMBUCKET COMPLETE DATABASE SCHEMA
-- Version: 1.0 - MWA (Mobile Wallet Adapter) Compatible
-- Created: 2026-01-25
-- ============================================================================
-- 
-- This is the COMPLETE schema for a fresh Supabase project.
-- Primary user identifier: wallet_address (Solana wallet)
-- 
-- Tables:
--   1. users           - User profiles (wallet-based identity)
--   2. friends         - Friend relationships (bidirectional)
--   3. challenges      - Challenge/bet records
--   4. challenge_transactions - On-chain transaction history
--   5. platform_fees   - Platform fee collection records
--
-- ============================================================================

-- ============================================================================
-- ENABLE REQUIRED EXTENSIONS
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- TABLE 1: USERS
-- ============================================================================
-- Primary table for user identity
-- wallet_address is the primary identifier (MWA-based auth)
-- privy_id kept for backward compatibility during migration

CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Primary identifier (MWA wallet address)
    wallet_address TEXT UNIQUE,
    
    -- Legacy identifier (Privy) - for migration compatibility
    privy_id TEXT UNIQUE,
    email TEXT,
    
    -- Profile information
    full_name TEXT,
    bio TEXT,
    profile_picture TEXT,               -- Path to profile image asset
    profile_image_id INTEGER DEFAULT 1, -- Image ID (1-5 for preset images)
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for fast lookups
CREATE INDEX IF NOT EXISTS idx_users_wallet_address ON public.users(wallet_address);
CREATE INDEX IF NOT EXISTS idx_users_privy_id ON public.users(privy_id);
CREATE INDEX IF NOT EXISTS idx_users_email ON public.users(email);

-- Comments
COMMENT ON TABLE public.users IS 'User accounts - identified by wallet_address (MWA) or privy_id (legacy)';
COMMENT ON COLUMN public.users.wallet_address IS 'Solana wallet address (base58 encoded) - primary identifier for MWA auth';
COMMENT ON COLUMN public.users.privy_id IS 'Legacy Privy user ID - for backward compatibility';
COMMENT ON COLUMN public.users.profile_image_id IS 'Preset profile image (1-5), maps to assets/images/ai_gen/profile_images/{id}.png';

-- ============================================================================
-- TABLE 2: FRIENDS
-- ============================================================================
-- Bidirectional friend relationships
-- When user A adds user B, two rows are created (A→B and B→A)

CREATE TABLE IF NOT EXISTS public.friends (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Relationship
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    friend_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    
    -- Status: 'pending', 'accepted', 'blocked'
    status TEXT NOT NULL DEFAULT 'accepted',
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Prevent duplicate friendships
    UNIQUE(user_id, friend_id),
    
    -- Prevent self-friendship
    CONSTRAINT no_self_friendship CHECK (user_id != friend_id)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_friends_user_id ON public.friends(user_id);
CREATE INDEX IF NOT EXISTS idx_friends_friend_id ON public.friends(friend_id);
CREATE INDEX IF NOT EXISTS idx_friends_status ON public.friends(status);

-- Comments
COMMENT ON TABLE public.friends IS 'Bidirectional friend relationships between users';
COMMENT ON COLUMN public.friends.status IS 'Friendship status: pending, accepted, blocked';

-- ============================================================================
-- TABLE 3: CHALLENGES
-- ============================================================================
-- Core challenge/bet records
-- Links to Pinocchio program on-chain escrow

CREATE TABLE IF NOT EXISTS public.challenges (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Challenge details
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    
    -- Amounts (in SOL)
    amount NUMERIC(20, 9) NOT NULL,        -- Legacy column (required)
    amount_in_sol NUMERIC(20, 9),          -- Total stake amount
    platform_fee NUMERIC(20, 9),           -- Fee taken by platform
    platform_fee_sol NUMERIC(20, 9),       -- Alias for clarity
    winner_amount NUMERIC(20, 9),          -- Amount winner receives
    winner_amount_sol NUMERIC(20, 9),      -- Alias for clarity
    
    -- Participants (User IDs - internal database references)
    creator_id UUID REFERENCES public.users(id),
    participant_id UUID REFERENCES public.users(id),
    witness_id UUID REFERENCES public.users(id),
    
    -- Participant identifiers (wallet addresses or privy_ids)
    creator_wallet_address TEXT,           -- Creator's wallet (MWA)
    creator_privy_id TEXT,                 -- Creator's privy ID (legacy)
    participant_privy_id TEXT,             -- Participant's privy ID (legacy)
    participant_email TEXT,                -- Email for invites
    winner_privy_id TEXT,                  -- Winner's privy ID (legacy)
    winner_id TEXT,                        -- Winner identifier (wallet or privy)
    
    -- On-chain wallet addresses
    member1_address TEXT,                  -- Initiator wallet address
    member2_address TEXT,                  -- Witness wallet address
    
    -- On-chain addresses (Pinocchio program)
    escrow_address TEXT,                   -- Challenge account address
    vault_address TEXT,                    -- Vault PDA address
    multisig_address TEXT,                 -- Legacy: alias for escrow_address
    blockchain_id TEXT,                    -- On-chain challenge identifier
    
    -- Status tracking
    -- Values: 'pending', 'active', 'accepted', 'funded', 'completed', 'failed', 'cancelled', 'expired'
    status TEXT NOT NULL DEFAULT 'pending',
    
    -- Transaction signatures
    transaction_signature TEXT,            -- Creation transaction
    resolution_tx TEXT,                    -- Resolution transaction
    fee_transaction_signature TEXT,        -- Fee collection transaction
    
    -- Metadata (JSON for additional data)
    metadata JSONB,
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_challenges_creator_id ON public.challenges(creator_id);
CREATE INDEX IF NOT EXISTS idx_challenges_participant_id ON public.challenges(participant_id);
CREATE INDEX IF NOT EXISTS idx_challenges_creator_wallet ON public.challenges(creator_wallet_address);
CREATE INDEX IF NOT EXISTS idx_challenges_member1 ON public.challenges(member1_address);
CREATE INDEX IF NOT EXISTS idx_challenges_member2 ON public.challenges(member2_address);
CREATE INDEX IF NOT EXISTS idx_challenges_escrow ON public.challenges(escrow_address);
CREATE INDEX IF NOT EXISTS idx_challenges_status ON public.challenges(status);
CREATE INDEX IF NOT EXISTS idx_challenges_created_at ON public.challenges(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_challenges_expires_at ON public.challenges(expires_at);

-- Comments
COMMENT ON TABLE public.challenges IS 'Challenge/bet records with on-chain escrow integration';
COMMENT ON COLUMN public.challenges.escrow_address IS 'Pinocchio program challenge account address';
COMMENT ON COLUMN public.challenges.member1_address IS 'Initiator wallet address (stakes funds)';
COMMENT ON COLUMN public.challenges.member2_address IS 'Witness wallet address (resolves challenge)';

-- ============================================================================
-- TABLE 4: CHALLENGE_TRANSACTIONS
-- ============================================================================
-- Tracks all on-chain transactions related to challenges

CREATE TABLE IF NOT EXISTS public.challenge_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- References
    challenge_id UUID NOT NULL REFERENCES public.challenges(id) ON DELETE CASCADE,
    
    -- Transaction details
    transaction_signature TEXT NOT NULL UNIQUE,
    transaction_type TEXT NOT NULL,        -- 'create', 'deposit', 'resolve', 'cancel', 'refund', 'platform_fee'
    
    -- Amount (optional, for transfers)
    amount_sol NUMERIC(20, 9),
    
    -- Addresses
    from_address TEXT,
    to_address TEXT,
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_challenge_tx_challenge_id ON public.challenge_transactions(challenge_id);
CREATE INDEX IF NOT EXISTS idx_challenge_tx_type ON public.challenge_transactions(transaction_type);
CREATE INDEX IF NOT EXISTS idx_challenge_tx_signature ON public.challenge_transactions(transaction_signature);

-- Comments
COMMENT ON TABLE public.challenge_transactions IS 'On-chain transaction history for challenges';
COMMENT ON COLUMN public.challenge_transactions.transaction_type IS 'Type: create, deposit, resolve, cancel, refund, platform_fee';

-- ============================================================================
-- TABLE 5: PLATFORM_FEES
-- ============================================================================
-- Tracks platform fee collections for accounting

CREATE TABLE IF NOT EXISTS public.platform_fees (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Reference
    challenge_id UUID NOT NULL REFERENCES public.challenges(id) ON DELETE CASCADE,
    
    -- Fee details
    amount_sol NUMERIC(20, 9) NOT NULL,
    fee_percentage NUMERIC(5, 2) NOT NULL,  -- e.g., 10.00 for 10%
    
    -- Transaction
    transaction_signature TEXT NOT NULL UNIQUE,
    
    -- Platform wallet that received the fee
    platform_wallet_address TEXT NOT NULL,
    
    -- Timestamp
    collected_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_platform_fees_challenge_id ON public.platform_fees(challenge_id);
CREATE INDEX IF NOT EXISTS idx_platform_fees_collected_at ON public.platform_fees(collected_at DESC);

-- Comments
COMMENT ON TABLE public.platform_fees IS 'Platform fee collection records for accounting';

-- ============================================================================
-- TABLE 6: CHALLENGE_PARTICIPANTS (Optional - for multi-party challenges)
-- ============================================================================
-- For future expansion to support >2 participants

CREATE TABLE IF NOT EXISTS public.challenge_participants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- References
    challenge_id UUID NOT NULL REFERENCES public.challenges(id) ON DELETE CASCADE,
    user_privy_id TEXT,
    
    -- Participant details
    role TEXT NOT NULL,                    -- 'creator', 'participant', 'witness'
    wallet_address TEXT NOT NULL,
    
    -- Status
    has_deposited BOOLEAN DEFAULT FALSE,
    
    -- Timestamps
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Prevent duplicate participants
    UNIQUE(challenge_id, wallet_address)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_challenge_participants_challenge ON public.challenge_participants(challenge_id);
CREATE INDEX IF NOT EXISTS idx_challenge_participants_wallet ON public.challenge_participants(wallet_address);

-- ============================================================================
-- FUNCTIONS
-- ============================================================================

-- Function: Sync user by wallet address (MWA authentication)
CREATE OR REPLACE FUNCTION sync_user_by_wallet(p_wallet_address TEXT)
RETURNS VOID AS $$
DECLARE
    v_user_id UUID;
BEGIN
    -- Check if user exists
    SELECT id INTO v_user_id 
    FROM public.users 
    WHERE wallet_address = p_wallet_address;
    
    IF v_user_id IS NULL THEN
        -- Create new user with wallet address
        INSERT INTO public.users (
            wallet_address,
            created_at,
            updated_at
        ) VALUES (
            p_wallet_address,
            NOW(),
            NOW()
        );
        
        RAISE NOTICE 'Created new user with wallet: %', p_wallet_address;
    ELSE
        -- Update existing user's last activity
        UPDATE public.users
        SET updated_at = NOW()
        WHERE wallet_address = p_wallet_address;
        
        RAISE NOTICE 'Updated existing user with wallet: %', p_wallet_address;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Function: Fetch user profile
CREATE OR REPLACE FUNCTION fetch_user_profile(p_privy_id TEXT)
RETURNS TABLE(
    id UUID,
    wallet_address TEXT,
    privy_id TEXT,
    email TEXT,
    full_name TEXT,
    bio TEXT,
    profile_picture TEXT,
    profile_image_id INTEGER,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        u.id,
        u.wallet_address,
        u.privy_id,
        u.email,
        u.full_name,
        u.bio,
        u.profile_picture,
        u.profile_image_id,
        u.created_at,
        u.updated_at
    FROM public.users u
    WHERE u.privy_id = p_privy_id OR u.wallet_address = p_privy_id;
END;
$$ LANGUAGE plpgsql;

-- Function: Update user profile
CREATE OR REPLACE FUNCTION update_user_profile(
    p_privy_id TEXT,
    p_full_name TEXT,
    p_bio TEXT
)
RETURNS VOID AS $$
BEGIN
    UPDATE public.users
    SET 
        full_name = p_full_name,
        bio = p_bio,
        updated_at = NOW()
    WHERE privy_id = p_privy_id OR wallet_address = p_privy_id;
END;
$$ LANGUAGE plpgsql;

-- Function: Update user profile with PFP
CREATE OR REPLACE FUNCTION update_user_profile_with_pfp(
    p_privy_id TEXT,
    p_full_name TEXT,
    p_bio TEXT,
    p_pfp_path TEXT
)
RETURNS VOID AS $$
BEGIN
    UPDATE public.users
    SET 
        full_name = p_full_name,
        bio = p_bio,
        profile_picture = p_pfp_path,
        updated_at = NOW()
    WHERE privy_id = p_privy_id OR wallet_address = p_privy_id;
END;
$$ LANGUAGE plpgsql;

-- Function: Get user by wallet address
CREATE OR REPLACE FUNCTION get_user_by_wallet(p_wallet_address TEXT)
RETURNS TABLE(
    id UUID,
    wallet_address TEXT,
    full_name TEXT,
    bio TEXT,
    profile_picture TEXT,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        u.id,
        u.wallet_address,
        u.full_name,
        u.bio,
        u.profile_picture,
        u.created_at,
        u.updated_at
    FROM public.users u
    WHERE u.wallet_address = p_wallet_address;
END;
$$ LANGUAGE plpgsql;

-- Function: Get challenges for wallet address
CREATE OR REPLACE FUNCTION get_challenges_for_wallet(p_wallet_address TEXT)
RETURNS TABLE(
    id UUID,
    title TEXT,
    description TEXT,
    amount_in_sol NUMERIC,
    status TEXT,
    member1_address TEXT,
    member2_address TEXT,
    escrow_address TEXT,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        c.id,
        c.title,
        c.description,
        c.amount_in_sol,
        c.status,
        c.member1_address,
        c.member2_address,
        c.escrow_address,
        c.expires_at,
        c.created_at
    FROM public.challenges c
    WHERE c.member1_address = p_wallet_address
       OR c.member2_address = p_wallet_address
       OR c.creator_wallet_address = p_wallet_address
    ORDER BY c.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================================================

-- Enable RLS on all tables
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.friends ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.challenges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.challenge_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.challenge_participants ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- RLS POLICIES - USERS
-- ============================================================================

-- Allow anyone to insert users (for registration)
DROP POLICY IF EXISTS users_insert ON public.users;
CREATE POLICY users_insert ON public.users
    FOR INSERT
    WITH CHECK (true);

-- Allow users to read all users (for friend search)
DROP POLICY IF EXISTS users_select ON public.users;
CREATE POLICY users_select ON public.users
    FOR SELECT
    USING (true);

-- Allow users to update their own profile
-- Note: In production, use auth.uid() or custom JWT claim
DROP POLICY IF EXISTS users_update ON public.users;
CREATE POLICY users_update ON public.users
    FOR UPDATE
    USING (true); -- Simplified for development

-- ============================================================================
-- RLS POLICIES - FRIENDS
-- ============================================================================

-- Allow authenticated users to manage friends
DROP POLICY IF EXISTS friends_all ON public.friends;
CREATE POLICY friends_all ON public.friends
    FOR ALL
    USING (true);

-- ============================================================================
-- RLS POLICIES - CHALLENGES
-- ============================================================================

-- Allow anyone to insert challenges
DROP POLICY IF EXISTS challenges_insert ON public.challenges;
CREATE POLICY challenges_insert ON public.challenges
    FOR INSERT
    WITH CHECK (true);

-- Allow anyone to read challenges (for public challenge viewing)
DROP POLICY IF EXISTS challenges_select ON public.challenges;
CREATE POLICY challenges_select ON public.challenges
    FOR SELECT
    USING (true);

-- Allow challenge participants to update
DROP POLICY IF EXISTS challenges_update ON public.challenges;
CREATE POLICY challenges_update ON public.challenges
    FOR UPDATE
    USING (true); -- Simplified for development

-- ============================================================================
-- RLS POLICIES - CHALLENGE_TRANSACTIONS
-- ============================================================================

DROP POLICY IF EXISTS challenge_tx_all ON public.challenge_transactions;
CREATE POLICY challenge_tx_all ON public.challenge_transactions
    FOR ALL
    USING (true);

-- ============================================================================
-- RLS POLICIES - PLATFORM_FEES
-- ============================================================================

DROP POLICY IF EXISTS platform_fees_insert ON public.platform_fees;
CREATE POLICY platform_fees_insert ON public.platform_fees
    FOR INSERT
    WITH CHECK (true);

DROP POLICY IF EXISTS platform_fees_select ON public.platform_fees;
CREATE POLICY platform_fees_select ON public.platform_fees
    FOR SELECT
    USING (true);

-- ============================================================================
-- RLS POLICIES - CHALLENGE_PARTICIPANTS
-- ============================================================================

DROP POLICY IF EXISTS challenge_participants_all ON public.challenge_participants;
CREATE POLICY challenge_participants_all ON public.challenge_participants
    FOR ALL
    USING (true);

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Trigger: Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION trigger_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply trigger to users table
DROP TRIGGER IF EXISTS set_updated_at_users ON public.users;
CREATE TRIGGER set_updated_at_users
    BEFORE UPDATE ON public.users
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_updated_at();

-- Apply trigger to challenges table
DROP TRIGGER IF EXISTS set_updated_at_challenges ON public.challenges;
CREATE TRIGGER set_updated_at_challenges
    BEFORE UPDATE ON public.challenges
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_updated_at();

-- ============================================================================
-- COMMENTS ON FUNCTIONS
-- ============================================================================

COMMENT ON FUNCTION sync_user_by_wallet(TEXT) IS 'Syncs user record for MWA authentication by wallet address';
COMMENT ON FUNCTION fetch_user_profile(TEXT) IS 'Fetches user profile by privy_id or wallet_address';
COMMENT ON FUNCTION update_user_profile(TEXT, TEXT, TEXT) IS 'Updates user profile name and bio';
COMMENT ON FUNCTION get_user_by_wallet(TEXT) IS 'Gets user record by wallet address';
COMMENT ON FUNCTION get_challenges_for_wallet(TEXT) IS 'Gets all challenges for a wallet address';

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

-- Grant permissions to authenticated users (Supabase role)
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated;

-- ============================================================================
-- INITIAL DATA (Optional - Platform wallet for fee collection)
-- ============================================================================

-- Insert platform configuration (uncomment and modify as needed)
-- INSERT INTO public.users (wallet_address, full_name, bio)
-- VALUES (
--     '3yHQosvdAhoFZHs66iFcdfRuT2aApAu6Yst2yoeDNjZm',
--     'Chumbucket Platform',
--     'Official Chumbucket platform wallet for fee collection'
-- )
-- ON CONFLICT (wallet_address) DO NOTHING;

-- ============================================================================
-- SCHEMA VERSION TRACKING
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.schema_versions (
    version TEXT PRIMARY KEY,
    applied_at TIMESTAMPTZ DEFAULT NOW(),
    description TEXT
);

INSERT INTO public.schema_versions (version, description)
VALUES ('1.0.0', 'Initial complete schema with MWA support')
ON CONFLICT (version) DO NOTHING;

-- ============================================================================
-- END OF SCHEMA
-- ============================================================================

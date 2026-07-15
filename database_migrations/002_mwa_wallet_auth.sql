-- Migration: Add wallet_address support for MWA authentication
-- Replaces privy_id with wallet_address as the primary user identifier

-- ============================================================================
-- USERS TABLE: Add wallet_address column
-- ============================================================================

-- Add wallet_address column if it doesn't exist
ALTER TABLE public.users 
ADD COLUMN IF NOT EXISTS wallet_address TEXT UNIQUE;

-- Create index for wallet_address lookups
CREATE INDEX IF NOT EXISTS idx_users_wallet_address 
ON public.users(wallet_address);

-- ============================================================================
-- SYNC USER BY WALLET ADDRESS FUNCTION
-- Called from MWA auth provider after wallet connection
-- ============================================================================

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
    -- Update existing user's last login
    UPDATE public.users
    SET updated_at = NOW()
    WHERE wallet_address = p_wallet_address;
    
    RAISE NOTICE 'Updated existing user with wallet: %', p_wallet_address;
  END IF;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- CHALLENGES TABLE: Update to use wallet_address
-- ============================================================================

-- Add creator_wallet_address if it doesn't exist
ALTER TABLE public.challenges
ADD COLUMN IF NOT EXISTS creator_wallet_address TEXT;

-- Create index for creator wallet lookups
CREATE INDEX IF NOT EXISTS idx_challenges_creator_wallet 
ON public.challenges(creator_wallet_address);

-- ============================================================================
-- MIGRATE EXISTING DATA (Optional - run once if needed)
-- ============================================================================

-- Migrate privy users to wallet-based identity
-- This assumes there's a relationship between privy_id and wallet address in linked_accounts
-- Run this only if you have existing privy-based users to migrate

-- UPDATE public.users u
-- SET wallet_address = (
--   SELECT address 
--   FROM public.linked_accounts la 
--   WHERE la.user_id = u.id 
--   AND la.type = 'solana_wallet'
--   LIMIT 1
-- )
-- WHERE u.wallet_address IS NULL 
-- AND EXISTS (
--   SELECT 1 FROM public.linked_accounts la 
--   WHERE la.user_id = u.id 
--   AND la.type = 'solana_wallet'
-- );

-- ============================================================================
-- RLS POLICIES: Wallet-based access control
-- ============================================================================

-- Users can read their own data (by wallet)
CREATE POLICY IF NOT EXISTS users_read_own_wallet ON public.users
FOR SELECT
USING (wallet_address = current_setting('app.current_wallet', true));

-- Users can update their own data (by wallet)
CREATE POLICY IF NOT EXISTS users_update_own_wallet ON public.users
FOR UPDATE
USING (wallet_address = current_setting('app.current_wallet', true));

-- Challenge access: users involved in the challenge
CREATE POLICY IF NOT EXISTS challenges_access_by_wallet ON public.challenges
FOR ALL
USING (
  member1_address = current_setting('app.current_wallet', true)
  OR member2_address = current_setting('app.current_wallet', true)
  OR creator_wallet_address = current_setting('app.current_wallet', true)
);

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Get user by wallet address
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

-- Get challenges for wallet address
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
  ORDER BY c.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON COLUMN public.users.wallet_address IS 'Solana wallet address (base58 encoded) - primary identifier for MWA auth';
COMMENT ON COLUMN public.challenges.creator_wallet_address IS 'Wallet address of challenge creator';
COMMENT ON FUNCTION sync_user_by_wallet(TEXT) IS 'Syncs user record for MWA authentication by wallet address';

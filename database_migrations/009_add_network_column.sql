-- Migration: Add network column for devnet/mainnet separation
-- This ensures devnet test data is never shown on mainnet and vice versa

-- Add network column to challenges table
ALTER TABLE challenges ADD COLUMN IF NOT EXISTS network TEXT DEFAULT 'devnet' CHECK (network IN ('devnet', 'mainnet-beta'));

-- Create index for efficient filtering by network
CREATE INDEX IF NOT EXISTS idx_challenges_network ON challenges(network);

-- Add comment for documentation
COMMENT ON COLUMN challenges.network IS 'Solana network: devnet or mainnet-beta. Separates test data from production.';

-- Add network column to fcm_tokens table (optional, for future use)
ALTER TABLE fcm_tokens ADD COLUMN IF NOT EXISTS network TEXT DEFAULT 'devnet' CHECK (network IN ('devnet', 'mainnet-beta'));

-- Update RLS policies to filter by network (optional enhancement)
-- Users should only see challenges on their current network

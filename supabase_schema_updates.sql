-- Chumbucket Database Schema Updates for Multisig and Fee Support
-- Execute these SQL statements in your Supabase SQL Editor

-- Drop existing challenges table if it exists (be careful in production!)
-- DROP TABLE IF EXISTS challenges CASCADE;

-- Updated challenges table with fee and multisig support
CREATE TABLE IF NOT EXISTS challenges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    creator_privy_id TEXT NOT NULL,
    participant_privy_id TEXT,
    participant_email TEXT,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    amount_sol DECIMAL(10, 9) NOT NULL CHECK (amount_sol > 0),
    platform_fee_sol DECIMAL(10, 9) NOT NULL DEFAULT 0,
    winner_amount_sol DECIMAL(10, 9) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'funded', 'completed', 'failed', 'cancelled', 'expired')),
    multisig_address TEXT,
    vault_address TEXT,
    winner_privy_id TEXT,
    transaction_signature TEXT,
    fee_transaction_signature TEXT,
    metadata JSONB DEFAULT '{}'::jsonb
);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_challenges_creator ON challenges(creator_privy_id);
CREATE INDEX IF NOT EXISTS idx_challenges_participant ON challenges(participant_privy_id);
CREATE INDEX IF NOT EXISTS idx_challenges_status ON challenges(status);
CREATE INDEX IF NOT EXISTS idx_challenges_created_at ON challenges(created_at);
CREATE INDEX IF NOT EXISTS idx_challenges_expires_at ON challenges(expires_at);

-- Platform fees tracking table
CREATE TABLE IF NOT EXISTS platform_fees (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    challenge_id UUID NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
    amount_sol DECIMAL(10, 9) NOT NULL,
    transaction_signature TEXT NOT NULL UNIQUE,
    collected_at TIMESTAMPTZ DEFAULT NOW(),
    fee_percentage DECIMAL(5, 4) NOT NULL DEFAULT 0.01, -- 1%
    platform_wallet_address TEXT NOT NULL
);

-- Create indexes for platform fees
CREATE INDEX IF NOT EXISTS idx_platform_fees_challenge ON platform_fees(challenge_id);
CREATE INDEX IF NOT EXISTS idx_platform_fees_collected_at ON platform_fees(collected_at);
CREATE INDEX IF NOT EXISTS idx_platform_fees_signature ON platform_fees(transaction_signature);

-- Challenge transactions tracking table (optional, for detailed transaction history)
CREATE TABLE IF NOT EXISTS challenge_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    challenge_id UUID NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
    transaction_type TEXT NOT NULL CHECK (transaction_type IN ('deposit', 'withdrawal', 'fee_collection')),
    amount_sol DECIMAL(10, 9) NOT NULL,
    from_address TEXT,
    to_address TEXT,
    transaction_signature TEXT NOT NULL UNIQUE,
    block_time TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

-- Create indexes for challenge transactions
CREATE INDEX IF NOT EXISTS idx_challenge_transactions_challenge ON challenge_transactions(challenge_id);
CREATE INDEX IF NOT EXISTS idx_challenge_transactions_type ON challenge_transactions(transaction_type);
CREATE INDEX IF NOT EXISTS idx_challenge_transactions_signature ON challenge_transactions(transaction_signature);

-- Challenge participants table (for tracking participant details)
CREATE TABLE IF NOT EXISTS challenge_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    challenge_id UUID NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
    participant_privy_id TEXT NOT NULL,
    participant_email TEXT,
    wallet_address TEXT,
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    status TEXT NOT NULL DEFAULT 'invited' CHECK (status IN ('invited', 'joined', 'declined', 'removed'))
);

-- Create indexes for challenge participants
CREATE INDEX IF NOT EXISTS idx_challenge_participants_challenge ON challenge_participants(challenge_id);
CREATE INDEX IF NOT EXISTS idx_challenge_participants_privy ON challenge_participants(participant_privy_id);

-- Enable Row Level Security (RLS) for all tables
ALTER TABLE challenges ENABLE ROW LEVEL SECURITY;
ALTER TABLE platform_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE challenge_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE challenge_participants ENABLE ROW LEVEL SECURITY;

-- RLS Policies for challenges table
-- Users can see challenges they created or are participating in
CREATE POLICY "Users can view their own challenges" ON challenges
    FOR SELECT USING (
        creator_privy_id = auth.jwt() ->> 'sub' OR 
        participant_privy_id = auth.jwt() ->> 'sub'
    );

-- Users can create challenges
CREATE POLICY "Users can create challenges" ON challenges
    FOR INSERT WITH CHECK (creator_privy_id = auth.jwt() ->> 'sub');

-- Users can update challenges they created
CREATE POLICY "Users can update their own challenges" ON challenges
    FOR UPDATE USING (creator_privy_id = auth.jwt() ->> 'sub');

-- RLS Policies for platform_fees table
-- Only allow viewing platform fees (no direct modification)
CREATE POLICY "Platform fees are viewable" ON platform_fees
    FOR SELECT USING (true);

-- RLS Policies for challenge_transactions table
-- Users can view transactions for their challenges
CREATE POLICY "Users can view challenge transactions" ON challenge_transactions
    FOR SELECT USING (
        challenge_id IN (
            SELECT id FROM challenges 
            WHERE creator_privy_id = auth.jwt() ->> 'sub' 
            OR participant_privy_id = auth.jwt() ->> 'sub'
        )
    );

-- RLS Policies for challenge_participants table
-- Users can view participants of their challenges
CREATE POLICY "Users can view challenge participants" ON challenge_participants
    FOR SELECT USING (
        challenge_id IN (
            SELECT id FROM challenges 
            WHERE creator_privy_id = auth.jwt() ->> 'sub' 
            OR participant_privy_id = auth.jwt() ->> 'sub'
        )
    );

-- Create a function to automatically update winner_amount_sol when amount_sol or platform_fee_sol changes
CREATE OR REPLACE FUNCTION update_winner_amount()
RETURNS TRIGGER AS $$
BEGIN
    NEW.winner_amount_sol = NEW.amount_sol - NEW.platform_fee_sol;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for automatic winner amount calculation
CREATE TRIGGER trigger_update_winner_amount
    BEFORE INSERT OR UPDATE OF amount_sol, platform_fee_sol ON challenges
    FOR EACH ROW
    EXECUTE FUNCTION update_winner_amount();

-- Create a function to automatically create platform_fee record when challenge is completed
CREATE OR REPLACE FUNCTION create_platform_fee_record()
RETURNS TRIGGER AS $$
BEGIN
    -- Only create fee record when status changes to completed and fee transaction signature is set
    IF NEW.status = 'completed' AND NEW.fee_transaction_signature IS NOT NULL 
       AND (OLD.status != 'completed' OR OLD.fee_transaction_signature IS NULL) THEN
        
        INSERT INTO platform_fees (
            challenge_id,
            amount_sol,
            transaction_signature,
            fee_percentage,
            platform_wallet_address
        ) VALUES (
            NEW.id,
            NEW.platform_fee_sol,
            NEW.fee_transaction_signature,
            0.01, -- 1% fee
            COALESCE(NEW.metadata ->> 'platform_wallet', 'CHANGEME_YourActualPlatformWalletAddress')
        );
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for automatic platform fee record creation
CREATE TRIGGER trigger_create_platform_fee_record
    AFTER UPDATE ON challenges
    FOR EACH ROW
    EXECUTE FUNCTION create_platform_fee_record();

-- Sample data (optional, for testing)
/*
INSERT INTO challenges (
    creator_privy_id,
    participant_email,
    title,
    description,
    amount_sol,
    platform_fee_sol,
    winner_amount_sol,
    expires_at,
    status
) VALUES (
    'sample_privy_user_id',
    'friend@example.com',
    'Daily Workout Challenge',
    'Complete 30 minutes of exercise every day for a week',
    0.1,
    0.001,
    0.099,
    NOW() + INTERVAL '7 days',
    'pending'
);
*/

-- Views for easier querying

-- View for challenge statistics
CREATE OR REPLACE VIEW challenge_stats AS
SELECT 
    status,
    COUNT(*) as count,
    SUM(amount_sol) as total_amount,
    SUM(platform_fee_sol) as total_fees,
    AVG(amount_sol) as avg_amount,
    MIN(amount_sol) as min_amount,
    MAX(amount_sol) as max_amount
FROM challenges 
GROUP BY status;

-- View for user challenge summary
CREATE OR REPLACE VIEW user_challenge_summary AS
SELECT 
    creator_privy_id as user_privy_id,
    'creator' as role,
    COUNT(*) as challenge_count,
    SUM(amount_sol) as total_amount,
    SUM(CASE WHEN status = 'completed' AND winner_privy_id = creator_privy_id THEN winner_amount_sol ELSE 0 END) as total_winnings
FROM challenges 
GROUP BY creator_privy_id

UNION ALL

SELECT 
    participant_privy_id as user_privy_id,
    'participant' as role,
    COUNT(*) as challenge_count,
    SUM(amount_sol) as total_amount,
    SUM(CASE WHEN status = 'completed' AND winner_privy_id = participant_privy_id THEN winner_amount_sol ELSE 0 END) as total_winnings
FROM challenges 
WHERE participant_privy_id IS NOT NULL
GROUP BY participant_privy_id;

-- Comments for documentation
COMMENT ON TABLE challenges IS 'Main challenges table with multisig and fee support';
COMMENT ON TABLE platform_fees IS 'Tracks platform fees collected from completed challenges';
COMMENT ON TABLE challenge_transactions IS 'Detailed transaction history for challenges';
COMMENT ON TABLE challenge_participants IS 'Tracks challenge participants and their status';

COMMENT ON COLUMN challenges.multisig_address IS 'Squads Protocol multisig address for this challenge';
COMMENT ON COLUMN challenges.vault_address IS 'Address where challenge funds are stored';
COMMENT ON COLUMN challenges.platform_fee_sol IS 'Platform fee in SOL (typically 1% of amount)';
COMMENT ON COLUMN challenges.winner_amount_sol IS 'Amount winner receives (amount - platform fee)';
COMMENT ON COLUMN challenges.fee_transaction_signature IS 'Transaction signature for platform fee collection';

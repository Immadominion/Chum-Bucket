-- ============================================================================
-- LINKED WALLETS — admit 'privy': the Chumbucket wallet that follows the account.
-- Owner: fleet/wallet   Created: 2026-10-04
-- Spec: fleet/money-v1.md, "One balance that follows the account"
-- ============================================================================
--
-- The Chumbucket wallet is a Privy embedded Solana wallet: non-custodial, tied
-- to the Supabase login (Privy custom auth), the same address on iPhone,
-- Android and the web. It joins the account exactly like every other wallet:
-- the BFF issues a single-use Sign-in-with-Solana challenge
-- (`auth.requestWalletNonce`), the wallet signs it, and `auth.linkWallet` ->
-- `attach_verified_wallet_v1` attaches it. Only the label is new.
--
-- `wallet_type` is a label, never an authorisation input: ownership is the
-- signature either way. The label lets the BFF pick the account's trading
-- wallet (`wallet.balance`) and lets the apps show which wallet is which.
--
-- Widening only. Every value accepted before is still accepted, so no row can
-- become invalid; nothing is rewritten or deleted. The BFF refuses the 'privy'
-- label until CHUMBUCKET_WALLET_ENABLED=true, which is set only after this
-- migration is applied.
-- ============================================================================

-- PostgreSQL has no ALTER CONSTRAINT for a CHECK expression, so it is dropped
-- and re-added in one transaction (a migration runs in one). The add is
-- guarded so a re-run cannot duplicate it.
ALTER TABLE public.linked_wallets DROP CONSTRAINT IF EXISTS linked_wallets_wallet_type_check;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint
     WHERE conrelid = 'public.linked_wallets'::regclass
       AND conname = 'linked_wallets_wallet_type_check'
  ) THEN
    ALTER TABLE public.linked_wallets
      ADD CONSTRAINT linked_wallets_wallet_type_check
      CHECK (wallet_type IN ('mwa', 'embedded', 'imported', 'privy'));
  END IF;
END
$$;

COMMENT ON COLUMN public.linked_wallets.wallet_type IS
  'How the person holds the key. Label only, never authorisation: mwa (a wallet app), embedded (a key the app made on one phone), imported, privy (the Chumbucket wallet: Privy embedded, follows the account).';

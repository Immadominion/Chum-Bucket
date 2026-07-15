# Chumbucket Database Schema Reference

## Quick Setup

1. Create a new Supabase project at <https://supabase.com>
2. Go to **SQL Editor** in the Supabase dashboard
3. Copy contents of `001_complete_schema.sql`
4. Run the SQL
5. Update your `.env` file with the new Supabase credentials

## Tables Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                          CHUMBUCKET DATABASE                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────┐         ┌──────────────┐                          │
│  │    USERS     │◄───────►│   FRIENDS    │                          │
│  │              │         │              │                          │
│  │ wallet_addr  │         │ user_id      │                          │
│  │ privy_id     │         │ friend_id    │                          │
│  │ full_name    │         │ status       │                          │
│  │ bio          │         └──────────────┘                          │
│  │ profile_pic  │                                                   │
│  └──────────────┘                                                   │
│         │                                                           │
│         │ creator_id                                                │
│         ▼                                                           │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                        CHALLENGES                              │  │
│  │                                                                │  │
│  │  id │ title │ description │ amount │ status │ escrow_address  │  │
│  │  member1_address (initiator) │ member2_address (witness)      │  │
│  │  created_at │ expires_at │ completed_at                       │  │
│  └──────────────────────────────────────────────────────────────┘  │
│         │                           │                               │
│         │                           │                               │
│         ▼                           ▼                               │
│  ┌──────────────┐         ┌──────────────────┐                     │
│  │CHALLENGE_TXS │         │  PLATFORM_FEES   │                     │
│  │              │         │                  │                     │
│  │ tx_signature │         │ amount_sol       │                     │
│  │ tx_type      │         │ fee_percentage   │                     │
│  │ amount_sol   │         │ tx_signature     │                     │
│  └──────────────┘         └──────────────────┘                     │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Table Details

### 1. `users`

Primary user identity table.

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `wallet_address` | TEXT | **Primary identifier (MWA)** - Solana wallet |
| `privy_id` | TEXT | Legacy identifier (for migration) |
| `email` | TEXT | Optional email |
| `full_name` | TEXT | Display name |
| `bio` | TEXT | User bio |
| `profile_picture` | TEXT | Asset path for profile image |
| `profile_image_id` | INT | Preset image ID (1-5) |
| `created_at` | TIMESTAMP | Account creation |
| `updated_at` | TIMESTAMP | Last update |

### 2. `friends`

Bidirectional friend relationships.

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `user_id` | UUID | FK to users |
| `friend_id` | UUID | FK to users |
| `status` | TEXT | `pending`, `accepted`, `blocked` |
| `created_at` | TIMESTAMP | When added |

**Note:** When user A adds B, create TWO rows: A→B and B→A

### 3. `challenges`

Core challenge/bet records.

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `title` | TEXT | Challenge title |
| `description` | TEXT | Challenge description |
| `amount` | NUMERIC | Stake amount (SOL) - required |
| `amount_in_sol` | NUMERIC | Alias for clarity |
| `platform_fee` | NUMERIC | Fee taken (SOL) |
| `winner_amount` | NUMERIC | Winner receives (SOL) |
| `creator_id` | UUID | FK to users (creator) |
| `creator_wallet_address` | TEXT | Creator's wallet |
| `member1_address` | TEXT | Initiator wallet (stakes) |
| `member2_address` | TEXT | Witness wallet (resolves) |
| `escrow_address` | TEXT | On-chain challenge account |
| `status` | TEXT | See statuses below |
| `expires_at` | TIMESTAMP | Deadline |
| `completed_at` | TIMESTAMP | When resolved |

**Challenge Statuses:**

- `pending` - Created, awaiting action
- `active` - On-chain, in progress
- `accepted` - Participant accepted
- `funded` - Funds deposited
- `completed` - Challenge succeeded
- `failed` - Challenge failed
- `cancelled` - Cancelled by creator
- `expired` - Deadline passed

### 4. `challenge_transactions`

On-chain transaction history.

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `challenge_id` | UUID | FK to challenges |
| `transaction_signature` | TEXT | Solana tx signature |
| `transaction_type` | TEXT | `create`, `resolve`, `cancel`, `refund` |
| `amount_sol` | NUMERIC | Transfer amount |
| `from_address` | TEXT | Source wallet |
| `to_address` | TEXT | Destination wallet |

### 5. `platform_fees`

Fee collection tracking.

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `challenge_id` | UUID | FK to challenges |
| `amount_sol` | NUMERIC | Fee collected |
| `fee_percentage` | NUMERIC | e.g., 10.00 for 10% |
| `transaction_signature` | TEXT | Collection tx |
| `platform_wallet_address` | TEXT | Receiving wallet |
| `collected_at` | TIMESTAMP | When collected |

## Key Functions

### `sync_user_by_wallet(wallet_address)`

Called after MWA wallet connect. Creates user if new, updates timestamp if existing.

```sql
SELECT sync_user_by_wallet('5yHQ...abc');
```

### `fetch_user_profile(identifier)`

Fetch profile by wallet_address OR privy_id.

```sql
SELECT * FROM fetch_user_profile('5yHQ...abc');
```

### `get_challenges_for_wallet(wallet_address)`

Get all challenges for a wallet.

```sql
SELECT * FROM get_challenges_for_wallet('5yHQ...abc');
```

## Flutter ↔ Supabase Mapping

### User Authentication (MWA)

```dart
// After wallet connect in MwaAuthProvider
await supabase.rpc('sync_user_by_wallet', params: {
  'p_wallet_address': walletAddress
});
```

### Create Challenge

```dart
await supabase.from('challenges').insert({
  'title': title,
  'description': description,
  'amount': amountInSol,  // Required NOT NULL
  'amount_in_sol': amountInSol,
  'creator_wallet_address': creatorWallet,
  'member1_address': creatorWallet,
  'member2_address': witnessWallet,
  'escrow_address': onChainAddress,
  'platform_fee': fee,
  'winner_amount': winnerAmount,
  'status': 'active',
  'expires_at': expiresAt.toIso8601String(),
});
```

### Get User Challenges

```dart
final challenges = await supabase
  .from('challenges')
  .select()
  .or('member1_address.eq.$wallet,member2_address.eq.$wallet')
  .order('created_at', ascending: false);
```

### Add Friend

```dart
// 1. Find or create friend user
final friend = await supabase.from('users')
  .upsert({'wallet_address': friendWallet, 'full_name': name})
  .select().single();

// 2. Create bidirectional friendship
await supabase.from('friends').insert([
  {'user_id': myUserId, 'friend_id': friend['id'], 'status': 'accepted'},
  {'user_id': friend['id'], 'friend_id': myUserId, 'status': 'accepted'},
]);
```

## Environment Variables

After creating Supabase project, update `.env`:

```env
SUPABASE_URL=https://xxxxx.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

## Pinocchio Program Integration

The `challenges` table syncs with on-chain data:

| DB Column | On-Chain Field |
|-----------|----------------|
| `escrow_address` | Challenge account address |
| `member1_address` | `initiator` pubkey |
| `member2_address` | `witness` pubkey |
| `amount_in_sol` | `amount` (lamports ÷ 1e9) |
| `platform_fee` | `platform_fee` (lamports ÷ 1e9) |

**Program ID:** `D6mjMGW1fX8oH3UcwZDh3teWcHEWvghUqaR2aeWD9sF1`

## Migration from Privy

The schema supports both `wallet_address` (MWA) and `privy_id` (legacy) identifiers:

- New users: Only `wallet_address` is set
- Legacy users: Both `privy_id` and `wallet_address` may exist
- Functions check both fields for backward compatibility

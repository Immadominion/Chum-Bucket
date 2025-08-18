# Chumbucket Development Roadmap

## Current State Analysis

### ✅ What's Working
- **Authentication**: Privy SDK integration with email/OTP login
- **UI/UX**: Complete onboarding flow, profile management, and challenge creation screens
- **Backend**: Supabase integration for user data and syncing
- **Wallet Integration**: Embedded Solana wallets via Privy SDK
- **State Management**: Provider pattern with proper loading states
- **Design System**: Consistent theming with glassmorphism and modern UI patterns

### 🔄 Current Implementation
- **Architecture**: Flutter frontend + Supabase backend + Privy auth + Solana devnet
- **Challenge Flow**: UI complete but no actual escrow/fund locking mechanism
- **Wallet**: Embedded wallets created but placeholder transaction logic
- **Data Models**: Basic challenge and friend models defined
- **Dependencies**: Modern stack with proper package management

---

## Smart Contract-Less Solutions for Escrow

### 1. **Squads Protocol Multisig (RECOMMENDED)**
**Implementation**: Use Squads V4 for programmatic multisig wallets
- **How it works**: Create a 2-of-2 multisig wallet for each challenge
- **Participants**: Challenge creator and participant both become signers
- **Escrow Logic**: Funds locked in multisig, requires both parties to release
- **Platform Fee**: Small percentage deducted during fund release to winner
- **Cost**: Only transaction fees (~0.00025 SOL per transaction)
- **Security**: Battle-tested protocol with $3B+ assets secured

**Integration Steps**:
```typescript
// 1. Install Squads SDK
npm install @sqds/multisig

// 2. Create multisig vault for each challenge
const multisig = await Multisig.create({
  members: [challengerPubkey, participantPubkey],
  threshold: 2,
  timeLock: 0
});

// 3. Transfer challenge amount to multisig vault
// 4. Winner approval transfers funds with platform fee deduction
const platformFee = challengeAmount * 0.01; // 1% fee
const winnerAmount = challengeAmount - platformFee;
// Send winnerAmount to winner, platformFee to platform wallet
```

### 2. **Program Derived Addresses (PDA) with Native Escrow**
**Implementation**: Use Solana's native account system without custom programs
- **How it works**: Create PDA accounts that can only be accessed with specific signatures
- **Escrow Logic**: Funds sent to PDA, requires both participants' signatures to withdraw
- **Cost**: Only transaction fees
- **Limitation**: Requires complex signature coordination

### 3. **Temporal Escrow with Timelock**
**Implementation**: Combine multisig with time-based release mechanisms
- **How it works**: Funds locked in multisig with automatic release after time limit
- **Dispute Resolution**: Manual intervention before timeout
- **Fallback**: Automatic return to sender after expiration

---

## Recommended Architecture

### Phase 1: MVP with Squads Multisig

#### Backend Services (Supabase)
```sql
-- Enhanced challenge table
CREATE TABLE challenges (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  creator_privy_id TEXT NOT NULL,
  participant_privy_id TEXT,
  participant_email TEXT,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  amount_sol DECIMAL(18,9) NOT NULL,
  platform_fee_sol DECIMAL(18,9) NOT NULL, -- Calculated platform fee
  winner_amount_sol DECIMAL(18,9) NOT NULL, -- Amount after fee deduction
  status challenge_status DEFAULT 'pending',
  multisig_address TEXT, -- Squads multisig address
  vault_address TEXT,    -- Actual vault address
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  expires_at TIMESTAMP WITH TIME ZONE,
  completed_at TIMESTAMP WITH TIME ZONE,
  winner_privy_id TEXT,
  transaction_signature TEXT,
  fee_transaction_signature TEXT, -- Transaction for fee payment
  metadata JSONB
);

-- Transaction tracking
CREATE TABLE challenge_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  challenge_id UUID REFERENCES challenges(id),
  transaction_signature TEXT NOT NULL,
  transaction_type TEXT NOT NULL, -- 'deposit', 'release', 'refund', 'platform_fee'
  amount_sol DECIMAL(18,9),
  from_address TEXT,
  to_address TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Platform fee tracking
CREATE TABLE platform_fees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  challenge_id UUID REFERENCES challenges(id),
  amount_sol DECIMAL(18,9) NOT NULL,
  transaction_signature TEXT NOT NULL,
  collected_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  fee_percentage DECIMAL(5,4) NOT NULL -- Store the fee percentage used
);

-- Challenge participants
CREATE TABLE challenge_participants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  challenge_id UUID REFERENCES challenges(id),
  user_privy_id TEXT NOT NULL,
  role TEXT NOT NULL, -- 'creator', 'participant'
  wallet_address TEXT NOT NULL,
  joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  has_deposited BOOLEAN DEFAULT FALSE
);
```

#### Smart Contract Alternative - Service Layer
```dart
// lib/services/challenge_service.dart
class ChallengeService {
  final SquadsMultisig _squads;
  final SupabaseClient _supabase;
  
  // Platform configuration
  static const double PLATFORM_FEE_PERCENTAGE = 0.01; // 1%
  static const double MIN_FEE_SOL = 0.001; // Minimum fee in SOL
  static const double MAX_FEE_SOL = 0.1; // Maximum fee in SOL (~$10 at $100/SOL)
  static const String PLATFORM_WALLET_ADDRESS = "YourPlatformWalletAddress";
  
  Future<Challenge> createChallenge({
    required String participantEmail,
    required String title,
    required double amount,
    required int durationDays,
  }) async {
    // Calculate platform fee
    final platformFee = _calculatePlatformFee(amount);
    final winnerAmount = amount - platformFee;
    
    // 1. Create multisig vault
    final multisig = await _createSquadsVault(
      members: [currentUser.walletAddress, participantWalletAddress],
      threshold: 2,
    );
    
    // 2. Store challenge in Supabase
    final challenge = await _supabase
      .from('challenges')
      .insert({
        'creator_privy_id': currentUser.id,
        'participant_email': participantEmail,
        'title': title,
        'amount_sol': amount,
        'platform_fee_sol': platformFee,
        'winner_amount_sol': winnerAmount,
        'multisig_address': multisig.publicKey.toString(),
        'expires_at': DateTime.now().add(Duration(days: durationDays)),
      })
      .select()
      .single();
    
    // 3. Send deposit transaction
    await _depositToVault(multisig.vault, amount);
    
    return Challenge.fromJson(challenge);
  }
  
  Future<void> completeChallenge(String challengeId, String winnerId) async {
    // 1. Get challenge details
    final challenge = await _getChallenge(challengeId);
    
    // 2. Create withdrawal transactions
    final winner = await _getUser(winnerId);
    
    // Transfer winner amount to winner
    final winnerTxSignature = await _withdrawFromVault(
      challenge.multisigAddress,
      winner.walletAddress,
      challenge.winnerAmountSol,
    );
    
    // Transfer platform fee to platform wallet
    final feeTxSignature = await _withdrawFromVault(
      challenge.multisigAddress,
      PLATFORM_WALLET_ADDRESS,
      challenge.platformFeeSol,
    );
    
    // 3. Record fee collection
    await _supabase.from('platform_fees').insert({
      'challenge_id': challengeId,
      'amount_sol': challenge.platformFeeSol,
      'transaction_signature': feeTxSignature,
      'fee_percentage': PLATFORM_FEE_PERCENTAGE,
    });
    
    // 4. Update challenge status
    await _supabase
      .from('challenges')
      .update({
        'status': 'completed',
        'winner_privy_id': winnerId,
        'completed_at': DateTime.now().toIso8601String(),
        'transaction_signature': winnerTxSignature,
        'fee_transaction_signature': feeTxSignature,
      })
      .eq('id', challengeId);
  }
  
  double _calculatePlatformFee(double amount) {
    final calculatedFee = amount * PLATFORM_FEE_PERCENTAGE;
    
    // Apply minimum and maximum fee limits
    if (calculatedFee < MIN_FEE_SOL) return MIN_FEE_SOL;
    if (calculatedFee > MAX_FEE_SOL) return MAX_FEE_SOL;
    
    return calculatedFee;
  }
}
```

### Phase 2: Enhanced Features

#### Real-time Updates
```dart
// lib/services/realtime_service.dart
class RealtimeService {
  void subscribeToChallenge(String challengeId) {
    _supabase
      .from('challenges')
      .stream(primaryKey: ['id'])
      .eq('id', challengeId)
      .listen((data) {
        // Update UI with real-time challenge status
        _updateChallengeState(data);
      });
  }
  
  void subscribeToUserChallenges(String userId) {
    _supabase
      .from('challenges')
      .stream(primaryKey: ['id'])
      .or('creator_privy_id.eq.$userId,participant_privy_id.eq.$userId')
      .listen((data) {
        // Update user's challenge list
        _updateUserChallenges(data);
      });
  }
}
```

#### Push Notifications
```dart
// lib/services/notification_service.dart
class NotificationService {
  Future<void> sendChallengeInvite(String recipientEmail, Challenge challenge) async {
    await _supabase.functions.invoke('send-challenge-notification', body: {
      'type': 'challenge_invite',
      'recipient_email': recipientEmail,
      'challenge_id': challenge.id,
      'challenger_name': challenge.creatorName,
      'amount': challenge.amount,
    });
  }
  
  Future<void> sendChallengeUpdate(Challenge challenge, String updateType) async {
    final participants = await _getParticipants(challenge.id);
    
    for (final participant in participants) {
      await _supabase.functions.invoke('send-push-notification', body: {
        'user_id': participant.privyId,
        'title': 'Challenge Update',
        'body': _getUpdateMessage(updateType, challenge),
        'data': {'challenge_id': challenge.id, 'type': updateType},
      });
    }
  }
}
```

---

## Implementation Timeline

### Week 1-2: Foundation
- [ ] Install and configure Squads SDK
- [ ] Update Supabase schema with enhanced tables
- [ ] Create ChallengeService with basic multisig integration
- [ ] Test multisig creation and basic transactions on devnet

### Week 3-4: Core Functionality
- [ ] Implement challenge creation with actual fund locking
- [ ] Build challenge acceptance flow for participants
- [ ] Add transaction tracking and status updates
- [ ] Implement challenge completion with fund release
- [ ] **Integrate platform fee collection mechanism**
- [ ] **Add fee transparency in UI (show winner amount vs. total amount)**

### Week 5-6: User Experience
- [ ] Add real-time updates for challenge status
- [ ] Implement push notifications
- [ ] Add transaction history and receipts
- [ ] Build dispute resolution flow
- [ ] **Create platform fee dashboard for transparency**
- [ ] **Add fee breakdown in challenge details**

### Week 7-8: Polish & Testing
- [ ] Comprehensive testing on devnet
- [ ] Error handling and edge cases
- [ ] UI/UX improvements based on testing
- [ ] Security audit of transaction flows

### Week 9-10: Production Preparation
- [ ] Mainnet testing with small amounts
- [ ] Performance optimization
- [ ] Final security review
- [ ] App store submission preparation

---

## Technical Dependencies

### Required Packages
```yaml
dependencies:
  # Existing packages...
  
  # New additions for multisig
  squads_multisig: ^1.0.0  # Custom package wrapper
  web3dart: ^2.7.3        # Additional Web3 functionality
  
  # Enhanced networking
  dio: ^5.4.0             # Better HTTP client
  retry: ^3.1.2           # Retry failed transactions
  
  # Real-time features
  pusher_client: ^2.0.0   # Real-time notifications
  flutter_local_notifications: ^17.2.3
  
  # Enhanced crypto utilities
  bip32: ^2.0.0          # HD wallet derivation
  hex: ^0.2.0            # Hex encoding utilities
```

### Environment Variables
```env
# .env additions
SQUADS_PROGRAM_ID=SQDS4ep65T869zMMBKyuUq6aD6EgTu8psMjkvj52pCf
SOLANA_RPC_URL=https://api.devnet.solana.com
SOLANA_WS_URL=wss://api.devnet.solana.com

# Platform fee configuration
PLATFORM_WALLET_ADDRESS=YourPlatformWalletPublicKey
PLATFORM_FEE_PERCENTAGE=0.01
MIN_FEE_SOL=0.001
MAX_FEE_SOL=0.1

# Supabase Edge Functions
SUPABASE_ANON_KEY=your_anon_key
SUPABASE_SERVICE_KEY=your_service_key

# Push notifications (if using FCM)
FCM_SERVER_KEY=your_fcm_server_key
```

---

## Security Considerations

### Fund Safety
- **Multisig Protection**: All funds secured by 2-of-2 multisig requirement
- **Time Locks**: Optional expiration for automatic refunds
- **Transaction Limits**: Maximum challenge amounts to limit exposure
- **Audit Trail**: All transactions recorded and verifiable on-chain
- **Fee Transparency**: Platform fees clearly displayed upfront and on-chain
- **Dual Transactions**: Separate transactions for winner payout and fee collection

### User Protection
- **Email Verification**: Ensure challenge participants are legitimate
- **Wallet Verification**: Confirm wallet ownership before fund release
- **Dispute Window**: Time buffer for challenging results
- **Support Escalation**: Manual intervention capability for edge cases

### Technical Security
- **Input Validation**: Sanitize all user inputs
- **Rate Limiting**: Prevent spam and abuse
- **Encryption**: Sensitive data encrypted at rest
- **Access Control**: Role-based permissions in Supabase

---

## Platform Fee Implementation

### Fee Structure Details
- **Base Fee**: 1% of challenge amount
- **Minimum Fee**: 0.001 SOL (~$0.10 at $100/SOL)
- **Maximum Fee**: 0.1 SOL (~$10.00 at $100/SOL)
- **Collection Method**: Automatically deducted during challenge completion
- **Transparency**: All fees displayed upfront and recorded on-chain

### Technical Implementation
```dart
// Fee calculation example
double calculatePlatformFee(double challengeAmount) {
  const feePercentage = 0.01; // 1%
  const minFee = 0.001; // SOL
  const maxFee = 0.1; // SOL
  
  double calculatedFee = challengeAmount * feePercentage;
  
  if (calculatedFee < minFee) return minFee;
  if (calculatedFee > maxFee) return maxFee;
  
  return calculatedFee;
}

// UI Display
String formatFeeDisplay(double challengeAmount) {
  final fee = calculatePlatformFee(challengeAmount);
  final winnerAmount = challengeAmount - fee;
  
  return "Winner receives: ${winnerAmount.toStringAsFixed(3)} SOL\n"
         "Platform fee: ${fee.toStringAsFixed(3)} SOL (${(fee/challengeAmount*100).toStringAsFixed(1)}%)";
}
```

### Fee Collection Flow
1. **Challenge Creation**: Display total amount and winner amount after fee
2. **Fund Locking**: Full amount deposited to multisig vault
3. **Challenge Completion**: Two separate transactions:
   - Winner receives (amount - fee)
   - Platform receives fee
4. **Transparency**: Both transactions recorded and visible on-chain

### Revenue Distribution (As Planned)
- **50% Team Operations**: Development, maintenance, support
- **50% Community Airdrops**: Distributed to Solana/Seeker/Warpcast users

### Fee Analytics Dashboard
```dart
// Admin dashboard for fee tracking
class FeeAnalytics {
  Future<Map<String, dynamic>> getFeeMetrics(DateTime startDate, DateTime endDate) async {
    final result = await supabase
      .from('platform_fees')
      .select('amount_sol, collected_at, challenge_id')
      .gte('collected_at', startDate.toIso8601String())
      .lte('collected_at', endDate.toIso8601String());
    
    return {
      'total_fees_collected': result.fold(0.0, (sum, fee) => sum + fee['amount_sol']),
      'total_challenges': result.length,
      'average_fee': result.length > 0 ? 
        result.fold(0.0, (sum, fee) => sum + fee['amount_sol']) / result.length : 0,
      'daily_breakdown': _groupFeesByDay(result),
    };
  }
}
```

---

## Monetization Strategy

### Fee Structure
- **Platform Fee**: 1% of challenge amount (minimum $0.10, maximum $10.00)
- **Distribution**: 50% team, 50% community airdrops (as planned)
- **Payment**: Automatically deducted during fund release
- **Transparency**: Fees clearly displayed, all transactions on-chain

### Revenue Projections
```
Conservative Estimate (Year 1):
- 1,000 active users
- Average 2 challenges/month per user
- Average challenge amount: $50
- Monthly volume: $100,000
- Platform revenue: $1,000/month (1%)
- Annual revenue: $12,000

Growth Scenario (Year 2):
- 10,000 active users
- Average 3 challenges/month per user
- Average challenge amount: $75
- Monthly volume: $2,250,000
- Platform revenue: $22,500/month
- Annual revenue: $270,000
```

---

## Risk Mitigation

### Technical Risks
- **Solana Network Issues**: Implement retry logic and fallback RPC endpoints
- **Multisig Failures**: Comprehensive testing and fallback recovery mechanisms
- **Wallet Integration Issues**: Multiple wallet support and recovery flows

### Business Risks
- **Low Adoption**: Focus on viral features and referral incentives
- **Regulatory Concerns**: Clearly position as gaming/entertainment, not gambling
- **Competition**: Emphasize social aspects and user experience differentiation

### Operational Risks
- **Customer Support**: Build comprehensive FAQ and dispute resolution system
- **Scaling Issues**: Design for horizontal scaling from day one
- **Security Incidents**: Implement monitoring, alerting, and incident response procedures

---

## Success Metrics

### Technical KPIs
- Challenge completion rate > 85%
- Transaction success rate > 99%
- Average response time < 2 seconds
- App crash rate < 0.1%

### Business KPIs
- Monthly active users growth > 20%
- Average challenge amount > $25
- User retention (30-day) > 40%
- Net Promoter Score > 50

### User Experience KPIs
- Time to create challenge < 2 minutes
- Challenge invitation acceptance rate > 60%
- Support ticket resolution < 24 hours
- App store rating > 4.5 stars

---

This roadmap provides a comprehensive path to completing Chumbucket as a production-ready application without requiring custom smart contract deployment, leveraging battle-tested infrastructure while maintaining the core betting/challenge functionality.

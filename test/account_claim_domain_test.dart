// The account-claim and wallet-link proofs name the owner's live domain.
//
// chumbucket.app was never registered, so a proof naming it could be asked
// for by whoever registered it. The app, Supabase's Sign in with Solana and
// the BFF's allowlist (src/auth/AuthIdentityRuntime.ts) all name
// chumbucket.fun; the BFF side has its own test that reads this pin.
import 'package:chumbucket/features/authentication/session/existing_account_proof.dart';
import 'package:chumbucket/features/authentication/session/solana_sign_in.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the claim proof names chumbucket.fun, the same as Sign in with Solana', () {
    expect(accountClaimDomain, 'chumbucket.fun');
    expect(accountClaimUri, 'https://chumbucket.fun');
    expect(accountClaimDomain, kSolanaSignInDomain);
    expect(accountClaimUri, kSolanaSignInUri);
  });
}

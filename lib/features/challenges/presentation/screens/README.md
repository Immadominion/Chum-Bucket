# Earlier SOL escrow challenges (read-only)

Friend challenges that locked SOL in the escrow program
`D6mjMGW1fX8oH3UcwZDh3teWcHEWvghUqaR2aeWD9sF1` came before calls. Creating one
is retired: no screen, button, link or notification in the app can start a new
escrow, and the code that built the create instruction and wrote the
`challenges` row is gone. Calls and Back / Fade / Dare replace it.

What stays, under Settings → History → Escrow challenges:

- `challenge_history_screen.dart` lists the signed-in wallet's challenges
  (`ChallengeStateProvider`, network-filtered by `get_challenges_for_wallet`).
- An open challenge (anything not `completed`, `failed` or `cancelled`;
  `expired` included, because the program enforces no deadline) opens the
  settle sheet (`shared/screens/home/widgets/resolve_challenge_sheet.dart`).
  Only the witness can settle it, with their wallet: "completed" returns the
  stake to the challenger, "not completed" sends it to the witness, and the
  program takes its 2.5% fee (max 0.1 SOL) either way. Before the wallet
  opens, the app reads the escrow account on Solana
  (`shared/screens/home/widgets/escrow_settle.dart`): a closed one is "Already
  settled", one the program does not own or whose stored witness is another
  wallet stops there, and the resolve uses the challenger the program stored.
- The challenger can only wait; the app has never offered the program's
  cancel instruction (it splits the stake 50/50 with the witness).
- `widgets/receipt_*` is the old share receipt, kept for the sheet-system
  tests.

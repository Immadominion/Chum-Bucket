/** Local test-only stdio adapter to the actual sibling BFF router/service.
 * No HTTP listener, environment credentials, real wallet approval, or network.
 * All ledger/venue/chain/identity boundaries are synthetic and explicitly injected.
 * This file is not exported by the mobile feature.
 */
import { createRequire } from "node:module";
import { createHash } from "node:crypto";
import { pathToFileURL } from "node:url";
import { createInterface } from "node:readline";

globalThis.fetch = Object.assign(async () => {
  throw new Error("Network is disabled in this contract harness");
}, { preconnect() {} }) as typeof fetch;

const root = `${process.argv[2].replace(/\/$/, "")}/`;
const require = createRequire(`${root}package.json`);
const fromBff = (file: string) => import(pathToFileURL(`${root}${file}`).href);
const { fetchRequestHandler } = await import(require.resolve("@trpc/server/adapters/fetch"));
const { Keypair, PublicKey, VersionedTransaction } = await import(require.resolve("@solana/web3.js"));
const { router } = await fromBff("src/api/trpc.ts");
const { pantaTradingRouter } = await fromBff("src/api/pantaTrading.ts");
const { loadConfig } = await fromBff("src/config.ts");
const { primeAuthIdentityRuntime, resolveAuthIdentityPolicy } = await fromBff("src/auth/AuthIdentityRuntime.ts");
const { PantaExecution } = await fromBff("src/prediction/PantaExecution.ts");
const { PantaTradingService } = await fromBff("src/prediction/PantaTradingService.ts");
const { setPantaTradingRuntime, setPantaLifecycle, PANTA_MAINNET_PROGRAM_ID } = await fromBff("src/prediction/PantaTradingRuntime.ts");
const { PantaClaimExecution } = await fromBff("src/prediction/PantaClaims.ts");
const { PantaClaimService } = await fromBff("src/prediction/PantaClaimService.ts");
const { PantaPositionsService } = await fromBff("src/prediction/PantaPositions.ts");
const { PantaFundingIndex } = await fromBff("src/prediction/PantaFunding.ts");
// The BFF refuses a funded prepare until the 18+ / jurisdiction / venue-terms
// attestation is on record (src/trust). Older API checkouts have no such gate.
const trustModule = await fromBff("src/trust/runtime.ts").catch(() => null);
const trustStoreModule = await fromBff("src/trust/store.ts").catch(() => null);

// Public, deterministic fixture seed. This is not a user's key or MWA approval.
const owner = Keypair.fromSeed(new Uint8Array(32).fill(9));
const wallet = owner.publicKey.toBase58();
const market = new PublicKey(new Uint8Array(32).fill(3)).toBase58();
const program = PANTA_MAINNET_PROGRAM_ID;
const blockhash = new PublicKey(new Uint8Array(32).fill(4)).toBase58();
const callId = "30000000-0000-4000-8000-000000000001";
const marketId = "20000000-0000-4000-8000-000000000001";
const userId = "10000000-0000-4000-8000-000000000001";
let now = 1790686800000;
let confirms = false;
let quoteCount = 0;
let broadcastCount = 0;
let resolved = false;
let paid = false;
let claimBuilds = 0;

const memoProgram = "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr";
const tokenProgram = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA";
const ataProgram = "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL";
const usdcMint = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v";
const addressByte = (byte: number) => new PublicKey(new Uint8Array(32).fill(byte)).toBase58();
const ata = PublicKey.findProgramAddressSync([owner.publicKey.toBuffer(),
  new PublicKey(tokenProgram).toBuffer(), new PublicKey(usdcMint).toBuffer()],
  new PublicKey(ataProgram))[0].toBase58();
const derived = { userPosition: addressByte(5), marketConfig: addressByte(6),
  userTokenAccount: ata, vaultTokenAccount: addressByte(7),
  treasuryTokenAccount: addressByte(8), vaultAuthority: addressByte(10) };
const account = (pubkey: string, isWritable = false, isSigner = false) =>
  ({ pubkey, isWritable, isSigner });
// Synthetic bytes matching the actual BFF's bounded observed-v1 profile.
// Constructing these bytes does not establish venue execution or live evidence.
function syntheticInstructions(quoteId: string, orderId: string) {
  const data = Buffer.alloc(17);
  createHash("sha256").update("global:primary_order_usdc").digest().copy(data, 0, 0, 8);
  data[8] = 0;
  data.writeBigUInt64LE(1000000n, 9);
  return [
    { programId: program, data: data.toString("base64"), accounts: [
      account(wallet, true, true), account(market, true), account(derived.marketConfig),
      account(derived.vaultAuthority), account(derived.vaultTokenAccount, true),
      account(derived.userPosition, true), account(usdcMint), account(ata, true),
      account(derived.treasuryTokenAccount, true), account(tokenProgram),
      account(ataProgram), account("11111111111111111111111111111111"),
    ] },
    { programId: memoProgram, data: Buffer.from(`panta:v1:usr_synthetic_partner:${quoteId}:${orderId}`)
      .toString("base64"), accounts: [account(wallet, false, true)] },
  ];
}

const config = loadConfig({
  FUNDED_POSITIONS: "true", PANTA_API_KEY: "pk_live_synthetic_contract_only",
  PANTA_PROGRAM_ID: program, PANTA_SCHEMA_READY: "true", PANTA_PARTNER_USER_ID: "usr_synthetic_partner",
  SUPABASE_URL: "https://synthetic.invalid", SUPABASE_SERVICE_ROLE_KEY: "synthetic-only",
  SOLANA_NETWORK: "mainnet-beta", PANTA_MAX_AMOUNT_BASE_UNITS: "100000000",
});
const app = { config };
primeAuthIdentityRuntime(config, {
  store: { enabled: true, async userIdForAuthUser(id: string) {
    return id === "synthetic-auth-user" ? userId : null;
  } },
  verifier: { async verify(token: string) {
    return token === "synthetic-session" ? { authUserId: "synthetic-auth-user" } : null;
  } },
  policy: resolveAuthIdentityPolicy(config),
});

const rows = new Map<string, any>();
const ledger = {
  async callIntent(user: string, id: string) {
    return user === userId && id === callId
      ? { callId, marketId, venueMarketId: market, side: "YES" } : null;
  },
  async find(user: string, key: string) {
    return [...rows.values()].find(row => row.user_id === user && row.idempotency_key === key) ?? null;
  },
  async byOrder(user: string, id: string) {
    return [...rows.values()].find(row => row.user_id === user && row.provider_order_id === id) ?? null;
  },
  async activeForCall(user: string, id: string, address: string) {
    return [...rows.values()].find(row => row.user_id === user &&
      row.call_id === id && row.wallet_address === address &&
      ["SUBMITTED", "FILLED"].includes(row.state)) ?? null;
  },
  async reserve(input: any) {
    if (await this.find(input.user_id, input.idempotency_key)) return null;
    const row = { ...input, state: "PREPARING", provider_order_id: null,
      prepared: null, signed_transaction: null, signature: null, fill_evidence: null,
      created_at: new Date(now).toISOString(), updated_at: new Date(now).toISOString() };
    rows.set(row.id, row);
    return row;
  },
  async update(id: string, state: string, patch: any) {
    const row = rows.get(id);
    if (!row || row.state !== state) return null;
    const next = { ...row, ...patch, updated_at: new Date(now).toISOString() };
    rows.set(id, next);
    return next;
  },
  async listForUser(user: string) {
    return [...rows.values()].filter(row => row.user_id === user && row.signature &&
      ["SUBMITTED", "FILLED", "FAILED"].includes(row.state));
  },
  async latestForCall(user: string, id: string) {
    return [...rows.values()].filter(row => row.user_id === user && row.call_id === id && row.signature)
      .at(-1) ?? null;
  },
};
// Synthetic win-claim ledger mirroring panta_claim_sessions' rules in memory.
const claimRows = new Map<string, any>();
const claimStore = {
  async find(user: string, key: string) { return [...claimRows.values()].find(r => r.user_id === user && r.idempotency_key === key) ?? null; },
  async byId(user: string, id: string) { const r = claimRows.get(id); return r && r.user_id === user ? r : null; },
  async activeFor(user: string, w: string, m: string) {
    return [...claimRows.values()].find(r => r.user_id === user && r.wallet_address === w && r.venue_market_id === m &&
      ["SUBMITTED", "CONFIRMED"].includes(r.state)) ?? null;
  },
  async listForUser(user: string) { return [...claimRows.values()].filter(r => r.user_id === user && r.state !== "PREPARING" && r.state !== "BUILT"); },
  async submitted() { return [...claimRows.values()].filter(r => r.state === "SUBMITTED"); },
  async reserve(input: any) {
    if (await this.find(input.user_id, input.idempotency_key)) return null;
    const row = { ...input, state: "PREPARING", prepared: null, signed_transaction: null, signature: null,
      confirm_evidence: null, created_at: new Date(now).toISOString(), updated_at: new Date(now).toISOString() };
    claimRows.set(row.id, row); return row;
  },
  async update(id: string, state: string, patch: any) {
    const row = claimRows.get(id);
    if (!row || row.state !== state) return null;
    const next = { ...row, ...patch, updated_at: new Date(now).toISOString() };
    claimRows.set(id, next); return next;
  },
};
// Synthetic bytes following the BFF's doc-derived claim profile. Not live evidence.
function syntheticClaimBuild(body: any) {
  claimBuilds++;
  const data = createHash("sha256").update("global:claim_win_usdc").digest().subarray(0, 8);
  return { wallet: body.wallet, marketId: body.marketId, outcome: "YES", winningShares: "0.792",
    instructions: [{ programId: program, data: Buffer.from(data).toString("base64"), accounts: [
      account(wallet, true, true), account(market, true), account(addressByte(11), true), account(addressByte(12), true),
      account(addressByte(13)), account(addressByte(14), true), account(ata, true), account(usdcMint), account(tokenProgram),
    ] }],
    derived: { winClaim: addressByte(11), positionPda: addressByte(12), vaultAuthority: addressByte(13) },
    recentBlockhash: blockhash, lastValidBlockHeight: 456 };
}
const execution = new PantaExecution({ programId: program, providerUserId: "usr_synthetic_partner", clock: { now: () => now },
  verifyTransaction: async () => confirms,
  request: async (path: string, body: any) => {
    const expiresAt = new Date(now + 60000).toISOString();
    if (path === "/primaryorderquote/") {
      quoteCount++;
      return { quoteId: `qt_synthetic_${quoteCount}`, marketId: market, side: "yes",
        amountUsdc: body.amountUsdc, shares: "0.792", avgPrice: "1.25", feeUsdc: "0.01", expiresAt };
    }
    if (path === "/primaryorderbuild/") return {
      orderId: `ord_synthetic_${quoteCount}`, quoteId: body.quoteId, wallet,
      marketId: market, side: "yes", amountUsdc: "1.000000", expectedShares: "0.792",
      feeUsdc: "0.01", status: "built", recentBlockhash: blockhash, lastValidBlockHeight: 123,
      expiresAt, derived, instructions: syntheticInstructions(body.quoteId, `ord_synthetic_${quoteCount}`),
    };
    if (path === "/primaryordersubmit/") return {
      orderId: body.orderId, status: "submitted", signature: body.signature,
    };
    if (path === "/primaryorderverify/") return {
      orderId: body.orderId, status: confirms ? "confirmed" : "submitted", signature: body.signature,
      marketId: market, side: "yes", amountUsdc: 1000000,
    };
    if (path === "/trades/") return { signature: body.signature, status: "processed",
      wallet, marketId: market, side: "yes", kind: "buy" };
    if (path === "/claim/build/") return syntheticClaimBuild(body);
    throw new Error("Unexpected synthetic venue operation");
  },
});
const service = new PantaTradingService({ store: ledger, execution,
  maxAmountBaseUnits: "100000000", now: () => now,
  // The BFF quotes a buy only for the account's own proven wallets; here the
  // one synthetic wallet is the synthetic person's only link.
  wallets: { async status(id: string, address: string) { return address !== wallet ? "none" : id === userId ? "active" : "other"; } },
  venue: { async getMarket() { return { venue: "panta", status: "OPEN", opensAt: now - 1000 }; } },
  chain: { async broadcast() { broadcastCount++; } }, // Counter, no RPC/broadcast.
});
setPantaTradingRuntime(config, service);
if (setPantaLifecycle) {
  const claims = new PantaClaimService({ claims: claimStore, trades: ledger, now: () => now,
    execution: new PantaClaimExecution({ programId: program, clock: { now: () => now },
      request: async (path: string, body: any) => {
        if (path !== "/claim/build/") throw new Error("Unexpected synthetic claim operation");
        return syntheticClaimBuild(body);
      } }),
    chain: { async broadcast() { broadcastCount++; }, async failed() { return false; }, async neverLanded() { return false; },
      async verifyClaim() { return paid ? { payoutBaseUnits: "792000", slot: 1 } : null; } } });
  const positions = new PantaPositionsService({ ledger, claims: claimStore, now: () => now,
    markets: {
      getMarket: (id: string) => id === marketId ? { id, question: "Synthetic contract question?", status: "OPEN", closesAt: now + 3600000 } : undefined,
      latestSharePrice: () => ({ yesPrice: "0.75", noPrice: "0.3", observedAt: now }),
      getResolution: () => resolved ? { resolution: "YES" } : undefined,
    },
    holdings: { async holdings() {
      return resolved ? [{ venueMarketId: market, side: "YES", shares: "0.792", phase: "resolved",
        claimable: !paid, claimed: paid, outcome: "YES" }] : [];
    } } });
  setPantaLifecycle(config, { trading: service, claims, positions, holdings: null, ledger: null, claimStore,
    funding: new PantaFundingIndex(null) });
}
if (trustModule && trustStoreModule) {
  const trust = trustModule.buildTrustRuntime(config, {
    store: new trustStoreModule.InMemoryTrustStore(),
    authAdmin: new trustStoreModule.RecordingAuthUserAdmin(),
  });
  trustModule.setTrustRuntime(config, trust);
  await trust.service.acceptFundedTrading(userId, trust.config.termsVersion);
}
const actualRouter = router({ pantaTrading: pantaTradingRouter });

async function dispatch(input: any) {
  if (input.op === "meta") return { wallet, venueMarketId: market, callId, marketId, now };
  if (input.op === "advance") { now += input.millis; return { now }; }
  if (input.op === "confirm") { confirms = true; return {}; }
  if (input.op === "metrics") return { quoteCount, broadcastCount, claimBuilds };
  if (input.op === "resolve") { resolved = true; return {}; }
  if (input.op === "pay") { paid = true; return {}; }
  if (input.op === "sign") {
    const tx = VersionedTransaction.deserialize(Buffer.from(input.payload, "base64"));
    tx.sign([owner]);
    return { payload: Buffer.from(tx.serialize()).toString("base64") };
  }
  const headers = new Headers(input.headers);
  const bearer = headers.get("authorization")?.replace(/^Bearer /, "");
  const response = await fetchRequestHandler({
    endpoint: "/trpc", router: actualRouter,
    req: new Request(`https://synthetic.invalid${input.path}`, {
      method: input.method, headers, ...(input.method === "POST" ? { body: input.body } : {}),
    }),
    createContext: () => ({ app, ...(bearer ? { supabaseAccessToken: bearer } : {}) }),
  });
  return { status: response.status, body: await response.text() };
}

for await (const line of createInterface({ input: process.stdin })) {
  const input = JSON.parse(line);
  try { process.stdout.write(`${JSON.stringify({ id: input.id, result: await dispatch(input) })}\n`); }
  catch { process.stdout.write(`${JSON.stringify({ id: input.id, failed: true })}\n`); }
}

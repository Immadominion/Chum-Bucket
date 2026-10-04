/** Local test-only stdio adapter to the actual sibling BFF's people layer.
 * The real calls/people/markets routers and the real CallsService, over an
 * in-memory store seeded with synthetic people, markets and venue results.
 * No HTTP listener, no environment credentials, no database, no network.
 * Run by test/people_layer_contract_test.dart; not part of the app.
 */
import { createRequire } from "node:module";
import { pathToFileURL } from "node:url";
import { createInterface } from "node:readline";

globalThis.fetch = Object.assign(async () => {
  throw new Error("Network is disabled in this contract harness");
}, { preconnect() {} }) as typeof fetch;

const root = `${process.argv[2].replace(/\/$/, "")}/`;
const require = createRequire(`${root}package.json`);
const fromBff = (file: string) => import(pathToFileURL(`${root}${file}`).href);
const { fetchRequestHandler } = await import(require.resolve("@trpc/server/adapters/fetch"));
const { router } = await fromBff("src/api/trpc.ts");
const { socialCallsRouter, socialMarketsRouter, socialPeopleRouter } = await fromBff("src/api/calls.ts");
const { loadConfig } = await fromBff("src/config.ts");
const { buildCallsRuntime, setCallsRuntime } = await fromBff("src/calls/runtime.ts");
const { InMemoryCallsStore } = await fromBff("src/calls/store.ts");
const { predictionStoreReader } = await fromBff("src/calls/markets.ts");
const { InMemoryPredictionStore } = await fromBff("src/prediction/store.ts");

const DAY = 24 * 60 * 60 * 1000;
let now = 1790686800000;
const clock = { now: () => now, sleep: async (ms: number) => { now += ms; } };

// Synthetic sessions: a bearer token names one synthetic person. Nothing else
// resolves, so an unknown token is a signed-out caller.
const sessions: Record<string, string> = {
  "synthetic-ann": "user-ann",
  "synthetic-bob": "user-bob",
  "synthetic-cid": "user-cid",
};

const calls = new InMemoryCallsStore();
const venue = new InMemoryPredictionStore();
for (const [id, handle, name] of [
  ["user-ann", "ann", "Ann Caller"],
  ["user-bob", "bob", "Bob Builder"],
  ["user-cid", "cid", "Cid Newcomer"],
]) {
  calls.upsertPerson({
    id, handle, displayName: name, avatarUrl: null, walletAddress: null,
    settledCalls: 0, correctCalls: 0, bio: `${name} calls crypto.`, joinedAt: now - 90 * DAY,
  });
}

function market(id: string) {
  const m = {
    id, venue: "fixture", venueEventId: `ev-${id}`, venueMarketId: `vm-${id}`,
    question: `[DEMO] Will ${id} happen?`, rulesText: "Resolves YES if it happens.",
    category: "crypto", outcomes: [{ side: "YES", label: "Yes" }, { side: "NO", label: "No" }],
    status: "OPEN", rawStatus: "open", opensAt: now - 1000, closesAt: now + 30 * DAY,
    resolvesAt: now + 31 * DAY, resolutionSource: "fixture:oracle", lastSyncedAt: now, payloadVersion: 1,
  };
  venue.upsertMarket(m, null);
  venue.appendSnapshot({ marketId: id, yesProbability: 0.5, observedAt: now, source: "venue" });
  return m;
}

function resolve(id: string, resolution: "YES" | "NO") {
  venue.recordResolution({
    marketId: id, venue: "fixture", venueMarketId: `vm-${id}`, resolution,
    resolvedAt: now, evidenceSource: "fixture:oracle", rawEvidence: { settled: resolution }, demo: true,
  }, now);
}

// Who signed in with which X account, and who holds which wallet — what
// person_x_identities_v1 / person_for_wallet_v1 answer in production.
// Synthetic: Ann signed in with X as @AnnOnX; Bob holds one wallet.
const BOB_WALLET = "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM";
const annX = {
  userId: "user-ann", xHandle: "AnnOnX",
  xAvatarUrl: "https://pbs.twimg.com/profile_images/1/ann_400x400.jpg", seenAt: now,
};
const identities = {
  async byXHandle(handle: string) { return handle === "annonx" ? [annX] : []; },
  async xIdentitiesOf(ids: readonly string[]) { return ids.includes("user-ann") ? [annX] : []; },
  async personForWallet(wallet: string) { return wallet === BOB_WALLET ? "user-bob" : null; },
};
// No network: an X handle nobody here has comes back without a picture.
const xAvatars = { async avatarFor() { return null; } };

let seq = 0;
const rt = buildCallsRuntime(undefined, {
  identities,
  xAvatars,
  store: calls,
  markets: predictionStoreReader(venue),
  clock,
  newId: (kind: string) => `${kind}-${String(++seq).padStart(4, "0")}`,
  viewer: { async resolve(ctx: { supabaseAccessToken?: string }) {
    return (ctx.supabaseAccessToken && sessions[ctx.supabaseAccessToken]) ?? null;
  } },
});

// Ann: twelve decided public calls, ten right — ranked.
for (let i = 0; i < 12; i++) {
  market(`ann-${i}`);
  rt.service.createCall({ marketId: `ann-${i}`, side: "YES" }, "user-ann");
  resolve(`ann-${i}`, i < 10 ? "YES" : "NO");
}
// Bob: three decided, two right — building a record.
for (let i = 0; i < 3; i++) {
  market(`bob-${i}`);
  rt.service.createCall({ marketId: `bob-${i}`, side: "NO" }, "user-bob");
  resolve(`bob-${i}`, i < 2 ? "NO" : "YES");
}
rt.sync.runOnce();
// An open call by Cid that Ann backs and Bob only challenges.
market("open-1");
const open = rt.service.createCall(
  { marketId: "open-1", side: "YES", thesis: "The original reason." },
  "user-cid",
);
rt.service.respond({ targetCallId: open.call.id, kind: "back" }, "user-ann");
rt.service.respond({ targetCallId: open.call.id, kind: "challenge" }, "user-bob");
rt.service.setFollowing({ personRef: "user-ann", following: true }, "user-cid");

const config = loadConfig({});
const app = { config };
setCallsRuntime(config, rt);
const actualRouter = router({
  calls: socialCallsRouter,
  markets: socialMarketsRouter,
  people: socialPeopleRouter,
});

async function dispatch(input: any) {
  if (input.op === "meta") return { openCallId: open.call.id, now };
  if (input.op === "advance") { now += input.millis; return { now }; }
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

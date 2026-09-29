/** Explicit, hash-pinned additive rollout to the existing Chumbucket project.
 * No .env, credentials, user records, anchors or general migration push.
 * bun --no-env-file scripts/apply-panta-production.ts --check|--apply
 */
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { readFileSync, mkdtempSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";

const mode = process.argv[2];
if (process.argv.length !== 3 || !["--check", "--apply"].includes(mode ?? "")) throw new Error("Explicit --check or --apply required");
process.umask(0o077);
const root = resolve(import.meta.dir, "..");
const ref = "odxsineiqquxqiuhxgfq";
const cli = "/Users/mac/.nvm/versions/node/v24.5.0/bin/supabase";
const migrations = [
  { version: "20260928210000", name: "panta_share_price_evidence", hash: "472d2681b6411405c6621a92468a88876aca88b9a98845fdd1d94b943b304f7d" },
  { version: "20260929120000", name: "panta_trade_sessions", hash: "20389e8fd29e01aab441dfd2e5a8c944f0a040c0d7a57f83f36ee3c93c551ec3" },
];
function check(value: unknown, message: string): asserts value { if (!value) throw new Error(message); }
check(readFileSync(join(root, "supabase/.temp/project-ref"), "utf8").trim() === ref, "Linked project differs; refusing any query");
const texts = migrations.map(m => {
  const sql = readFileSync(join(root, `supabase/migrations/${m.version}_${m.name}.sql`), "utf8");
  check(createHash("sha256").update(sql).digest("hex") === m.hash, `Migration ${m.version} differs from reviewed bytes`);
  return sql;
});
function query(sql: string, file?: string): Record<string, unknown>[] {
  const r = spawnSync(cli, ["db", "query", "--linked", "--workdir", root, "--output", "json", "--agent", "no", "--log-level", "none",
    ...(file ? ["--file", file] : [sql])], { encoding: "utf8", timeout: 40000, maxBuffer: 1_048_576 });
  // CLI failures can include connection details. Never echo stderr or raw output.
  check(r.status === 0, "Linked query did not complete; inspect aggregate schema status before retrying");
  let rows: unknown; try { rows = JSON.parse(r.stdout); } catch { throw new Error("Unexpected query result; details suppressed"); }
  check(Array.isArray(rows), "Unexpected linked result shape");
  return rows;
}
const snapshot = `SELECT (SELECT count(*) FROM public.users) AS people,
  (SELECT count(*) FROM public.users WHERE auth_user_id IS NOT NULL) AS linked_people,
  (SELECT count(*) FROM public.calls) AS calls,
  (SELECT count(*) FROM public.venue_markets) AS markets,
  (SELECT count(*) FROM public.market_resolutions) AS resolutions`;
const [before] = query(snapshot);
const [state] = query(`SELECT
  to_regclass('public.market_share_price_snapshots') IS NOT NULL AS prices,
  to_regclass('public.panta_trade_sessions') IS NOT NULL AS ledger,
  (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version IN ('20260928210000','20260929120000')) AS recorded,
  (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid='public.venue_markets'::regclass AND conname='venue_markets_venue_check') AS market_check,
  (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid='public.market_resolutions'::regclass AND conname='market_resolutions_venue_check') AS resolution_check`);
const prior = "CHECK ((venue = ANY (ARRAY['jupiter'::text, 'polymarket'::text, 'fixture'::text])))";
check(state?.prices === false && state.ledger === false && Number(state.recorded) === 0 &&
  state.market_check === prior && state.resolution_check === prior, "Schema is not the audited baseline; stop and inspect, never drop existing objects");
console.log(JSON.stringify({ project: ref, mode, baseline: before, reviewedMigrations: migrations }));
if (mode === "--check") process.exit(0);

const quoted = (value: string) => "'" + value.replaceAll("'", "''") + "'";
const guard = `DO $guard$ BEGIN
  IF to_regclass('public.market_share_price_snapshots') IS NOT NULL OR to_regclass('public.panta_trade_sessions') IS NOT NULL
    OR EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version IN ('20260928210000','20260929120000'))
    OR (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid='public.venue_markets'::regclass AND conname='venue_markets_venue_check') IS DISTINCT FROM ${quoted(prior)}
    OR (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid='public.market_resolutions'::regclass AND conname='market_resolutions_venue_check') IS DISTINCT FROM ${quoted(prior)}
    THEN RAISE EXCEPTION 'Audited Panta baseline changed'; END IF;
END $guard$;`;
const history = migrations.map((m, i) => `INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
 VALUES (${quoted(m.version)},${quoted(m.name)},ARRAY[${quoted(texts[i]!)}]);`).join("\n");
const scratch = mkdtempSync("/private/tmp/chumbucket-panta-prod-migration.");
const file = join(scratch, "reviewed-additions.sql");
writeFileSync(file, `BEGIN; SET LOCAL statement_timeout = '20s'; SET LOCAL lock_timeout = '3s';
SELECT pg_advisory_xact_lock(hashtextextended('chumbucket:panta-schema-v1',0));
${guard}\n${texts.join("\n")}\n${history}\nNOTIFY pgrst, 'reload schema'; COMMIT;\n${snapshot};`, { mode: 0o600 });
query("", file);
const [after] = query(snapshot);
for (const key of ["people", "linked_people", "calls", "markets", "resolutions"]) {
  check(after?.[key] === before?.[key], `Unexpected ${key} count drift; verify before enabling traffic`);
}
const [verified] = query(`SELECT
 (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version IN ('20260928210000','20260929120000')) = 2 AS history_recorded,
 (SELECT relrowsecurity FROM pg_class WHERE oid='public.panta_trade_sessions'::regclass) AS ledger_rls,
 NOT has_table_privilege('anon','public.panta_trade_sessions','SELECT,INSERT,UPDATE,DELETE,TRUNCATE') AS anon_denied,
 NOT has_table_privilege('authenticated','public.panta_trade_sessions','SELECT,INSERT,UPDATE,DELETE,TRUNCATE') AS authenticated_denied,
 (SELECT count(*) FROM pg_policies WHERE tablename='panta_trade_sessions') = 0 AS no_client_policies,
 (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='calls' AND column_name IN ('share_price_snapshot_id','entry_price')) = 2 AS price_pins,
 (SELECT count(*) FROM pg_trigger WHERE tgrelid='public.panta_trade_sessions'::regclass AND NOT tgisinternal) = 2 AS ledger_guards`);
check(verified && Object.values(verified).every(v => v === true), "Post-apply checks failed; do not enable Panta traffic");
console.log(JSON.stringify({ project: ref, applied: migrations.map(m=>m.version), preserved: after, verification: verified, artifact: file,
  fundedFlagChanged: false, anchorsApproved: false, signed: false, broadcast: false }));

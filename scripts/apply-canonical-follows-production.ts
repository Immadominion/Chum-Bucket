/** Exact-project, hash-pinned additive follow rollout. No .env or bulk db push.
 * bun --no-env-file scripts/apply-canonical-follows-production.ts --check|--apply|--verify
 */
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";

const mode = process.argv[2];
if (process.argv.length !== 3 || !["--check", "--apply", "--verify"].includes(mode ?? "")) {
  throw new Error("Explicit --check, --apply or --verify required");
}
process.umask(0o077);
const root = resolve(import.meta.dir, "..");
const ref = "odxsineiqquxqiuhxgfq";
const cli = "/Users/mac/.nvm/versions/node/v24.5.0/bin/supabase";
const version = "20260929220000";
const name = "canonical_person_follows";
const hash = "3287e937fb2864dd5f2da9f97e6db97d86c0f5abf7ce2cfe70c5618d9e3fe8e2";
function check(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}
check(readFileSync(join(root, "supabase/.temp/project-ref"), "utf8").trim() === ref,
  "Linked Supabase project differs; refusing any query");
const sql = readFileSync(join(root, `supabase/migrations/${version}_${name}.sql`), "utf8");
check(createHash("sha256").update(sql).digest("hex") === hash,
  "Canonical follow migration differs from reviewed bytes");

function query(statement: string, file?: string): Record<string, unknown>[] {
  const result = spawnSync(cli, ["db", "query", "--linked", "--workdir", root,
    "--output", "json", "--agent", "no", "--log-level", "none",
    ...(file ? ["--file", file] : [statement])],
  { encoding: "utf8", timeout: 40_000, maxBuffer: 1_048_576 });
  // CLI errors may contain connection information. Never echo raw stderr or
  // stdout, even when a migration or a connectivity check fails.
  check(result.status === 0, "Linked query failed; inspect aggregate schema status before retrying");
  let rows: unknown;
  try { rows = JSON.parse(result.stdout); }
  catch { throw new Error("Unexpected linked query shape; details suppressed"); }
  check(Array.isArray(rows), "Unexpected linked result shape");
  return rows;
}

const snapshot = `SELECT
  (SELECT count(*) FROM public.users) AS people,
  (SELECT count(*) FROM public.follows) AS legacy_follows,
  (SELECT count(*) FROM public.calls) AS calls,
  (SELECT count(*) FROM public.call_results) AS call_results,
  (SELECT count(*) FROM public.panta_trade_sessions) AS native_trade_sessions`;
const [before] = query(snapshot);
const [state] = query(`SELECT
  to_regclass('public.person_follows') IS NOT NULL AS table_exists,
  to_regprocedure('public.current_app_user_id()') IS NOT NULL AS identity_function,
  (SELECT relrowsecurity FROM pg_class WHERE oid='public.calls'::regclass) AS calls_rls,
  (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND tablename='calls' AND policyname='calls_followers_select') = 1 AS legacy_visibility_policy,
  (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='follows' AND column_name IN ('follower_wallet','followee_wallet') AND is_nullable='NO') = 2 AS legacy_wallet_columns,
  (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='${version}') AS recorded`);
check(state?.identity_function === true && state.calls_rls === true &&
  state.legacy_visibility_policy === true && state.legacy_wallet_columns === true,
  "Live schema differs from the reviewed social baseline");

function verify(): Record<string, unknown> {
  const [v] = query(`SELECT
    (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='${version}') = 1 AS history_recorded,
    (SELECT relrowsecurity FROM pg_class WHERE oid='public.person_follows'::regclass) AS follows_rls,
    NOT has_table_privilege('anon','public.person_follows','SELECT,INSERT,UPDATE,DELETE,TRUNCATE') AS anon_denied,
    NOT has_table_privilege('authenticated','public.person_follows','INSERT,UPDATE,DELETE,TRUNCATE') AS client_writes_denied,
    has_table_privilege('authenticated','public.person_follows','SELECT') AS own_reads_granted,
    (has_table_privilege('service_role','public.person_follows','INSERT') AND
     has_table_privilege('service_role','public.person_follows','DELETE')) AS service_writes_granted,
    (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND tablename='person_follows') = 1 AS single_scoped_policy,
    (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND tablename='calls' AND policyname='calls_person_followers_select') = 1 AS private_call_policy,
    (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='person_follows' AND column_name LIKE '%wallet%') = 0 AS walletless_graph`);
  check(v && Object.values(v).every(value => value === true),
    "Post-apply canonical follow checks failed; do not deploy the BFF");
  return v;
}

if (mode === "--verify") {
  check(state?.table_exists === true && Number(state.recorded) === 1,
    "Canonical follow migration is not recorded exactly once");
  console.log(JSON.stringify({ project: ref, mode, counts: before, verified: verify() }));
  process.exit(0);
}
check(state?.table_exists === false && Number(state.recorded) === 0,
  "Canonical follow migration already exists or history differs; stop");
console.log(JSON.stringify({ project: ref, mode, baseline: before, migration: version, sha256: hash }));
if (mode === "--check") process.exit(0);

const quoted = (value: string) => "'" + value.replaceAll("'", "''") + "'";
const guard = `DO $guard$ BEGIN
  IF to_regclass('public.person_follows') IS NOT NULL
    OR EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='${version}')
    OR to_regprocedure('public.current_app_user_id()') IS NULL
    OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.calls'::regclass)
    THEN RAISE EXCEPTION 'Audited canonical-follow baseline changed'; END IF;
END $guard$;`;
const scratch = mkdtempSync("/private/tmp/chumbucket-person-follows-prod.");
const file = join(scratch, "reviewed-addition.sql");
writeFileSync(file, `BEGIN; SET LOCAL statement_timeout='20s'; SET LOCAL lock_timeout='3s';
SELECT pg_advisory_xact_lock(hashtextextended('chumbucket:canonical-person-follows-v1',0));
${guard}
${sql}
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
 VALUES (${quoted(version)},${quoted(name)},ARRAY[${quoted(sql)}]);
NOTIFY pgrst, 'reload schema'; COMMIT;
${snapshot};`, { mode: 0o600 });
query("", file);
const [after] = query(snapshot);
for (const key of ["people", "legacy_follows", "calls", "call_results", "native_trade_sessions"]) {
  check(after?.[key] === before?.[key], `Unexpected ${key} count drift; stop before deploying the BFF`);
}
console.log(JSON.stringify({ project: ref, applied: version, preserved: after,
  verified: verify(), artifact: file, signed: false, broadcast: false }));

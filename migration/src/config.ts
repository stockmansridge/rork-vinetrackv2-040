import dotenv from "dotenv";
import path from "node:path";
import { fileURLToPath } from "node:url";
import type { Stage } from "./types.js";

const dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.resolve(dirname, "../.env") });

export type MigrationConfig = {
  v1Url: string;
  v1ServiceRoleKey: string;
  v2Url: string;
  v2ServiceRoleKey: string;
  outDir: string;
  stage: Stage;
  vineyardId?: string;
  apply: boolean;
};

const stages = new Set<Stage>(["identity", "vineyards", "invitations", "all"]);

export function loadConfig(argv: string[]): MigrationConfig {
  const args = parseArgs(argv);
  const stageArg = args.stage ?? "all";
  if (!stages.has(stageArg as Stage)) {
    throw new Error(`Unsupported stage "${stageArg}". Use identity, vineyards, invitations, or all.`);
  }
  const apply = args.apply === "true" || args.apply === "1";
  if (apply) {
    throw new Error("apply not implemented in Phase 16B");
  }

  const v1Url = requiredEnv("V1_SUPABASE_URL");
  const v1ServiceRoleKey = requiredEnv("V1_SERVICE_ROLE_KEY");
  const v2Url = requiredEnv("V2_SUPABASE_URL");
  const v2ServiceRoleKey = requiredEnv("V2_SERVICE_ROLE_KEY");

  return {
    v1Url,
    v1ServiceRoleKey,
    v2Url,
    v2ServiceRoleKey,
    outDir: path.resolve(dirname, "../out"),
    stage: stageArg as Stage,
    vineyardId: args.vineyard,
    apply
  };
}

function parseArgs(argv: string[]): Record<string, string> {
  const parsed: Record<string, string> = {};
  for (const arg of argv) {
    if (!arg.startsWith("--")) continue;
    const body = arg.slice(2);
    const [key, ...valueParts] = body.split("=");
    if (!key) continue;
    parsed[key] = valueParts.length === 0 ? "true" : valueParts.join("=");
  }
  return parsed;
}

function requiredEnv(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`Missing ${name}. Copy migration/.env.example to migration/.env and fill in the value.`);
  }
  return value;
}

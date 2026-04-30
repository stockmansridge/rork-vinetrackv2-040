import { loadConfig } from "./config.js";
import { createMigrationClients } from "./clients.js";
import { readV1Snapshot } from "./readers/v1.js";
import { readV2Snapshot } from "./readers/v2.js";
import {
  buildDisclaimerReport,
  buildIdentityReport,
  buildInvitationReport,
  buildMemberReport,
  buildVineyardDataInventory,
  buildVineyardReport
} from "./remap.js";
import { writeJson } from "./report.js";
import type { ReportSummary } from "./types.js";

async function main(): Promise<void> {
  const config = loadConfig(process.argv.slice(2));
  const clients = createMigrationClients(config);
  const [v1, v2] = await Promise.all([readV1Snapshot(clients.v1), readV2Snapshot(clients.v2)]);
  const filesWritten: string[] = [];
  const warnings: string[] = [];

  const { report: identityReport, maps } = buildIdentityReport(v1, v2);
  filesWritten.push(await writeJson(config.outDir, "maps.json", maps));

  if (config.stage === "identity" || config.stage === "all") {
    filesWritten.push(await writeJson(config.outDir, "dry-run-identity.json", identityReport));
  }

  const vineyardReport = buildVineyardReport(v1, maps, config.vineyardId);
  const memberReport = buildMemberReport(v1, maps, config.vineyardId);
  const disclaimerReport = buildDisclaimerReport(v1, maps);

  if (config.stage === "vineyards" || config.stage === "all") {
    filesWritten.push(await writeJson(config.outDir, "dry-run-vineyards.json", {
      vineyards: vineyardReport,
      vineyardMembers: memberReport,
      disclaimerAcceptances: disclaimerReport
    }));
  }

  const invitationReport = buildInvitationReport(v1, maps, config.vineyardId);
  if (config.stage === "invitations" || config.stage === "all") {
    filesWritten.push(await writeJson(config.outDir, "dry-run-invitations.json", invitationReport));
  }

  if (config.stage === "all") {
    const inventory = buildVineyardDataInventory(v1, config.vineyardId);
    filesWritten.push(await writeJson(config.outDir, "vineyard-data-inventory.json", inventory));
  }

  for (const tableResult of [v1.profiles, v1.vineyards, v1.vineyardMembers, v1.invitations, v1.disclaimerAcceptances, v1.vineyardData, v2.profiles]) {
    if (!tableResult.exists) warnings.push(`Optional table missing or inaccessible: ${tableResult.table}${tableResult.error ? ` (${tableResult.error})` : ""}`);
  }
  for (const table of v2.schemaCoverage.tables) {
    if (!table.exists) warnings.push(`V2 destination table missing or inaccessible: ${table.table}${table.error ? ` (${table.error})` : ""}`);
  }

  const summary: ReportSummary = {
    generatedAt: new Date().toISOString(),
    mode: "dry-run",
    stage: config.stage,
    filters: { vineyardId: config.vineyardId },
    filesWritten: filesWritten.map((file) => file.replace(`${config.outDir}/`, "migration/out/")),
    counts: {
      v1AuthUsers: v1.users.length,
      v1Profiles: v1.profiles.rows.length,
      v2AuthUsers: v2.users.length,
      mappedUsers: identityReport.mappedUsers.filter((entry) => entry.v2UserId).length,
      unmappedV1Users: identityReport.unmappedV1Users.length,
      vineyards: vineyardReport.sourceCount,
      mappedVineyards: vineyardReport.mapped.length,
      vineyardMembers: memberReport.sourceCount,
      pendingInvitations: invitationReport.pendingCurrentCount,
      disclaimerAcceptances: disclaimerReport.sourceCount,
      v1VineyardDataRows: v1.vineyardData.rows.length
    },
    warnings,
    schemaCoverage: v2.schemaCoverage
  };

  filesWritten.push(await writeJson(config.outDir, "report-summary.json", summary));
  console.log(`Phase 16B dry-run complete. Wrote ${filesWritten.length} files to migration/out.`);
  if (warnings.length > 0) console.log(`${warnings.length} warning(s) written to report-summary.json.`);
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(message);
  process.exit(1);
});

import type {
  AuthUserRecord,
  DisclaimerAcceptanceRecord,
  DisclaimerDryRunReport,
  DuplicateEmailReport,
  IdentityDryRunReport,
  IdentityMapEntry,
  InvitationDryRunReport,
  InvitationRecord,
  JsonRecord,
  MapsFile,
  MemberMappingReport,
  ProfileRecord,
  SourceSnapshot,
  TargetSnapshot,
  VineyardDataInventoryEntry,
  VineyardDataInventoryReport,
  VineyardMappingReport,
  VineyardMemberRecord,
  VineyardRecord
} from "./types.js";

export const validRoles = new Set(["owner", "manager", "supervisor", "operator"]);

export const vineyardDataKeys = [
  "pins",
  "paddocks",
  "trips",
  "sprayRecords",
  "savedChemicals",
  "savedSprayPresets",
  "savedEquipmentOptions",
  "sprayEquipment",
  "tractors",
  "fuelPurchases",
  "operatorCategories",
  "buttonTemplates",
  "repairButtons",
  "growthButtons",
  "savedCustomPatterns",
  "settings",
  "yieldSessions",
  "damageRecords",
  "historicalYieldRecords",
  "maintenanceLogs",
  "workTasks",
  "grapeVarieties"
];

export function normalizeEmail(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim().toLowerCase();
  return trimmed.length > 0 ? trimmed : null;
}

export function isUuid(value: unknown): value is string {
  return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

export function buildIdentityReport(v1: SourceSnapshot, v2: TargetSnapshot): { report: IdentityDryRunReport; maps: MapsFile } {
  const generatedAt = new Date().toISOString();
  const v1EmailEntries = collectUserEmailEntries(v1.users, v1.profiles.rows);
  const v2EmailEntries = collectUserEmailEntries(v2.users, v2.profiles.rows);
  const v2ByEmail = firstIdByEmail(v2EmailEntries);
  const mappedUsers: IdentityMapEntry[] = [];
  const unmappedV1Users: IdentityMapEntry[] = [];
  const v1UserIdToV2UserId: Record<string, string> = {};

  for (const entry of v1EmailEntries) {
    const v2UserId = entry.email ? v2ByEmail[entry.email] ?? null : null;
    const result: IdentityMapEntry = {
      v1UserId: entry.id,
      v1Email: entry.email,
      v2UserId,
      source: v2UserId ? entry.source : "unmapped"
    };
    mappedUsers.push(result);
    if (v2UserId) v1UserIdToV2UserId[entry.id] = v2UserId;
    else unmappedV1Users.push(result);
  }

  const usersByEmail: Record<string, string> = {};
  for (const [email, id] of Object.entries(v2ByEmail)) usersByEmail[email] = id;

  return {
    report: {
      generatedAt,
      v1AuthUserCount: v1.users.length,
      v1ProfileCount: v1.profiles.rows.length,
      v2AuthUserCount: v2.users.length,
      v2ProfileCount: v2.profiles.rows.length,
      mappedUsers,
      unmappedV1Users,
      duplicateV1Emails: duplicateEmails(v1EmailEntries),
      duplicateV2Emails: duplicateEmails(v2EmailEntries),
      missingOptionalTables: [v1.profiles, v2.profiles].filter((result) => !result.exists).map((result) => result.table)
    },
    maps: {
      generatedAt,
      usersByEmail,
      v1UserIdToV2UserId,
      vineyardsById: {}
    }
  };
}

export function buildVineyardReport(v1: SourceSnapshot, maps: MapsFile, vineyardFilter?: string): VineyardMappingReport {
  const rows = filterByVineyard(v1.vineyards.rows, vineyardFilter);
  const mapped: VineyardMappingReport["mapped"] = [];
  const invalidUuidRecords: JsonRecord[] = [];
  const ownerMappingFailures: VineyardMappingReport["ownerMappingFailures"] = [];

  for (const row of rows) {
    const id = row.id;
    if (!isUuid(id)) {
      invalidUuidRecords.push(row);
      continue;
    }
    const ownerId = asNullableString(row.owner_id ?? row.user_id);
    const v2OwnerId = ownerId ? maps.v1UserIdToV2UserId[ownerId] ?? null : null;
    if (ownerId && !v2OwnerId) {
      ownerMappingFailures.push({ vineyardId: id, name: asNullableString(row.name), ownerId, reason: "owner_id has no V2 user mapping" });
    }
    maps.vineyardsById[id] = id;
    mapped.push({
      v1VineyardId: id,
      targetVineyardId: id,
      name: asNullableString(row.name),
      v1OwnerId: ownerId,
      v2OwnerId,
      ownerMapped: ownerId ? Boolean(v2OwnerId) : false
    });
  }

  return {
    generatedAt: new Date().toISOString(),
    sourceCount: rows.length,
    validUuidCount: mapped.length,
    invalidUuidRecords,
    mapped,
    ownerMappingFailures,
    missingOptionalTables: v1.vineyards.exists ? [] : [v1.vineyards.table]
  };
}

export function buildMemberReport(v1: SourceSnapshot, maps: MapsFile, vineyardFilter?: string): MemberMappingReport {
  const rows = filterByVineyard(v1.vineyardMembers.rows, vineyardFilter);
  const orphanMemberships: JsonRecord[] = [];
  const missingUsers: JsonRecord[] = [];
  const invalidRoles: JsonRecord[] = [];
  let mappedCount = 0;

  for (const row of rows) {
    if (!isUuid(row.vineyard_id) || !maps.vineyardsById[row.vineyard_id]) orphanMemberships.push(row);
    const userId = asNullableString(row.user_id);
    const mappedUserId = userId ? maps.v1UserIdToV2UserId[userId] : null;
    if (!mappedUserId && !normalizeEmail(row.email)) missingUsers.push(row);
    if (!row.role || !validRoles.has(row.role)) invalidRoles.push(row);
    if (isUuid(row.vineyard_id) && (mappedUserId || normalizeEmail(row.email)) && row.role && validRoles.has(row.role)) mappedCount += 1;
  }

  return {
    generatedAt: new Date().toISOString(),
    sourceCount: rows.length,
    mappedCount,
    orphanMemberships,
    missingUsers,
    invalidRoles
  };
}

export function buildInvitationReport(v1: SourceSnapshot, maps: MapsFile, vineyardFilter?: string): InvitationDryRunReport {
  const rows = filterByVineyard(v1.invitations.rows, vineyardFilter);
  const now = Date.now();
  const pendingCurrent: InvitationRecord[] = [];
  const staleOrExpired: InvitationRecord[] = [];
  const invalidRoles: InvitationRecord[] = [];
  const invalidVineyards: InvitationRecord[] = [];

  for (const row of rows) {
    const email = normalizeEmail(row.email);
    const status = typeof row.status === "string" ? row.status.toLowerCase() : "pending";
    const expiresAt = typeof row.expires_at === "string" ? Date.parse(row.expires_at) : Number.NaN;
    const isExpired = Number.isFinite(expiresAt) && expiresAt < now;
    if (!row.role || !validRoles.has(row.role)) invalidRoles.push(row);
    if (!isUuid(row.vineyard_id) || !maps.vineyardsById[row.vineyard_id]) invalidVineyards.push(row);
    if (status === "pending" && !isExpired && email) pendingCurrent.push({ ...row, email });
    else staleOrExpired.push(row);
  }

  return {
    generatedAt: new Date().toISOString(),
    sourceCount: rows.length,
    pendingCurrentCount: pendingCurrent.length,
    staleOrExpiredCount: staleOrExpired.length,
    pendingCurrent,
    staleOrExpired,
    invalidRoles,
    invalidVineyards,
    duplicatePendingEmails: duplicateEmails(pendingCurrent.map((row) => ({ id: asNullableString(row.id) ?? "unknown", email: normalizeEmail(row.email), source: "profile_email" as const })))
  };
}

export function buildDisclaimerReport(v1: SourceSnapshot, maps: MapsFile): DisclaimerDryRunReport {
  const missingUsers: DisclaimerAcceptanceRecord[] = [];
  const missingVersion: DisclaimerAcceptanceRecord[] = [];
  let mappedCount = 0;

  for (const row of v1.disclaimerAcceptances.rows) {
    const userId = asNullableString(row.user_id);
    if (!row.version) missingVersion.push(row);
    if (userId && maps.v1UserIdToV2UserId[userId]) mappedCount += 1;
    else missingUsers.push(row);
  }

  return {
    generatedAt: new Date().toISOString(),
    sourceCount: v1.disclaimerAcceptances.rows.length,
    mappedCount,
    missingUsers,
    missingVersion
  };
}

export function buildVineyardDataInventory(v1: SourceSnapshot, vineyardFilter?: string): VineyardDataInventoryReport {
  const rows = filterByVineyard(v1.vineyardData.rows, vineyardFilter);
  const totalKnownCounts = Object.fromEntries(vineyardDataKeys.map((key) => [key, 0]));
  const allUnknownKeys = new Set<string>();
  const entries: VineyardDataInventoryEntry[] = [];

  for (const row of rows) {
    const data = extractVineyardData(row);
    const vineyardId = asNullableString(row.vineyard_id ?? row.vineyardId ?? getValue(data, "vineyardId") ?? getValue(data, "vineyard_id"));
    const knownCounts: Record<string, number> = {};
    const keysFound = Object.keys(data);
    let estimatedRecordVolume = 0;

    for (const key of vineyardDataKeys) {
      const count = countValue(data[key]);
      knownCounts[key] = count;
      totalKnownCounts[key] = (totalKnownCounts[key] ?? 0) + count;
      estimatedRecordVolume += count;
    }

    const unknownKeys = keysFound.filter((key) => !vineyardDataKeys.includes(key));
    for (const key of unknownKeys) allUnknownKeys.add(key);
    const invalidIds = collectInvalidIds(data);
    const storageReferences = collectStorageReferences(data);
    const likelyTransformBlockers = buildBlockers({ vineyardId, data, unknownKeys, invalidIds });

    entries.push({
      vineyardId,
      rowId: asNullableString(row.id),
      keysFound,
      knownCounts,
      unknownKeys,
      estimatedRecordVolume,
      missingVineyardId: !isUuid(vineyardId),
      invalidIds,
      storageReferences,
      likelyTransformBlockers
    });
  }

  return {
    generatedAt: new Date().toISOString(),
    sourceCount: rows.length,
    keysInspected: vineyardDataKeys,
    totalKnownCounts,
    entries,
    recordsWithMissingVineyardId: entries.filter((entry) => entry.missingVineyardId).length,
    rowsWithInvalidIds: entries.filter((entry) => entry.invalidIds.length > 0).length,
    unknownKeys: Array.from(allUnknownKeys).sort()
  };
}

function collectUserEmailEntries(users: AuthUserRecord[], profiles: ProfileRecord[]): Array<{ id: string; email: string | null; source: "auth_email" | "profile_email" }> {
  const entries = new Map<string, { id: string; email: string | null; source: "auth_email" | "profile_email" }>();
  for (const user of users) entries.set(user.id, { id: user.id, email: normalizeEmail(user.email), source: "auth_email" });
  for (const profile of profiles) {
    const id = asNullableString(profile.id ?? profile.user_id);
    if (!id || entries.has(id)) continue;
    entries.set(id, { id, email: normalizeEmail(profile.email), source: "profile_email" });
  }
  return Array.from(entries.values());
}

function firstIdByEmail(entries: Array<{ id: string; email: string | null }>): Record<string, string> {
  const result: Record<string, string> = {};
  for (const entry of entries) {
    if (entry.email && !result[entry.email]) result[entry.email] = entry.id;
  }
  return result;
}

function duplicateEmails(entries: Array<{ id: string; email: string | null }>): DuplicateEmailReport[] {
  const grouped = new Map<string, string[]>();
  for (const entry of entries) {
    if (!entry.email) continue;
    grouped.set(entry.email, [...(grouped.get(entry.email) ?? []), entry.id]);
  }
  return Array.from(grouped.entries()).filter(([, ids]) => ids.length > 1).map(([email, ids]) => ({ email, ids }));
}

function filterByVineyard<T extends JsonRecord & { vineyard_id?: string | null }>(rows: T[], vineyardId?: string): T[] {
  if (!vineyardId) return rows;
  return rows.filter((row) => row.vineyard_id === vineyardId || row.id === vineyardId);
}

function asNullableString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : null;
}

function extractVineyardData(row: JsonRecord): JsonRecord {
  const candidates = [row.data, row.payload, row.json, row.value, row];
  for (const candidate of candidates) {
    if (candidate && typeof candidate === "object" && !Array.isArray(candidate)) return candidate as JsonRecord;
  }
  return {};
}

function countValue(value: unknown): number {
  if (Array.isArray(value)) return value.length;
  if (value && typeof value === "object") return Object.keys(value).length;
  return value == null ? 0 : 1;
}

function getValue(record: JsonRecord, key: string): unknown {
  return record[key];
}

function collectInvalidIds(value: unknown, path = "root"): string[] {
  const invalid: string[] = [];
  if (Array.isArray(value)) {
    value.forEach((item, index) => invalid.push(...collectInvalidIds(item, `${path}[${index}]`)));
    return invalid;
  }
  if (!value || typeof value !== "object") return invalid;
  for (const [key, child] of Object.entries(value as JsonRecord)) {
    if ((key === "id" || key.endsWith("Id") || key.endsWith("_id")) && typeof child === "string" && child.length > 0 && !isUuid(child)) {
      invalid.push(`${path}.${key}=${child}`);
    }
    invalid.push(...collectInvalidIds(child, `${path}.${key}`));
  }
  return invalid;
}

function collectStorageReferences(value: unknown): string[] {
  const refs = new Set<string>();
  walk(value, (candidate) => {
    if (typeof candidate !== "string") return;
    const lower = candidate.toLowerCase();
    if (lower.includes("storage") || lower.includes(".jpg") || lower.includes(".jpeg") || lower.includes(".png") || lower.includes("el-stage") || lower.includes("growth")) refs.add(candidate);
  });
  return Array.from(refs).slice(0, 100);
}

function buildBlockers(input: { vineyardId: string | null; data: JsonRecord; unknownKeys: string[]; invalidIds: string[] }): string[] {
  const blockers: string[] = [];
  if (!isUuid(input.vineyardId)) blockers.push("missing or invalid vineyard_id");
  if (input.invalidIds.length > 0) blockers.push("invalid nested IDs detected");
  if (input.unknownKeys.length > 0) blockers.push("unknown top-level keys require Phase 16C mapping decision");
  if (countValue(input.data.settings) > 0) blockers.push("settings blob requires explicit V2 ownership/default mapping decision");
  return blockers;
}

function walk(value: unknown, visit: (value: unknown) => void): void {
  visit(value);
  if (Array.isArray(value)) {
    for (const item of value) walk(item, visit);
  } else if (value && typeof value === "object") {
    for (const child of Object.values(value as JsonRecord)) walk(child, visit);
  }
}

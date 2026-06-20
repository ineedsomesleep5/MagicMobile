import type { CommanderGameConfig, CommanderStartupResponse } from "@magicmobile/shared";

export type StartupRecord = CommanderStartupResponse & {
  createdAt: number;
  config?: CommanderGameConfig;
};

const globalForCommanderStartup = globalThis as typeof globalThis & {
  __magicMobileCommanderStartups?: Map<string, StartupRecord>;
};

export function startupStore(): Map<string, StartupRecord> {
  if (!globalForCommanderStartup.__magicMobileCommanderStartups) {
    globalForCommanderStartup.__magicMobileCommanderStartups = new Map();
  }
  return globalForCommanderStartup.__magicMobileCommanderStartups;
}

export function cleanupOldStartups(now = Date.now()): void {
  for (const [startupId, record] of startupStore()) {
    if (now - record.createdAt > 10 * 60 * 1000) {
      startupStore().delete(startupId);
    }
  }
}

export function getCommanderStartup(startupId: string): CommanderStartupResponse | undefined {
  cleanupOldStartups();
  const record = startupStore().get(startupId);
  return record ? toStartupResponse(record) : undefined;
}

export function toStartupResponse(record: StartupRecord): CommanderStartupResponse {
  const response: CommanderStartupResponse = {
    startupId: record.startupId,
    status: record.status
  };

  if (record.snapshot) {
    response.snapshot = record.snapshot;
  }
  if (record.message) {
    response.message = record.message;
  }
  if (record.error) {
    response.error = record.error;
  }

  return response;
}

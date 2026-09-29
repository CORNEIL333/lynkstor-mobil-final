export type SyncTransport = 'cloud' | 'wifi' | 'local';
export interface LynkstorSyncStatusDetail {
  transport: 'cloud' | 'wifi';
  synchronized: boolean;
}

export function resolveSyncTransport(detail: LynkstorSyncStatusDetail | null, online: boolean): SyncTransport {
  if (!detail?.synchronized) return 'local';
  if (detail.transport === 'cloud' && !online) return 'local';
  return detail.transport;
}

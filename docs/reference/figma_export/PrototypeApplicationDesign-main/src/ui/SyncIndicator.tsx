import { useEffect, useState } from 'react';
import { Cloud, Smartphone, Wifi } from 'lucide-react';
import { resolveSyncTransport, type LynkstorSyncStatusDetail, type SyncTransport } from './sync-state';
export type { LynkstorSyncStatusDetail, SyncTransport } from './sync-state';

declare global {
  interface WindowEventMap {
    'lynkstor:sync-status': CustomEvent<LynkstorSyncStatusDetail>;
  }
}

/**
 * Connectivity loss returns to Local. Cloud and Wi-Fi require a positive event
 * from the sync engine; navigator.onLine alone never proves synchronization.
 */
export function useSyncTransport(): SyncTransport {
  const [transport, setTransport] = useState<SyncTransport>('local');
  useEffect(() => {
    const updateConnectivity = () => setTransport('local');
    const updateSync = (event: WindowEventMap['lynkstor:sync-status']) => {
      setTransport(resolveSyncTransport(event.detail, navigator.onLine));
    };
    window.addEventListener('online', updateConnectivity);
    window.addEventListener('offline', updateConnectivity);
    window.addEventListener('lynkstor:sync-status', updateSync);
    return () => {
      window.removeEventListener('online', updateConnectivity);
      window.removeEventListener('offline', updateConnectivity);
      window.removeEventListener('lynkstor:sync-status', updateSync);
    };
  }, []);
  return transport;
}

const content = {
  cloud: { label: 'Cloud', detail: 'Internet accessible · synchronisation cloud active', Icon: Cloud },
  wifi: { label: 'Wi-Fi', detail: 'Synchronisé avec un autre appareil, sans accès Internet', Icon: Wifi },
  local: { label: 'Local', detail: 'Aucune synchronisation active · données conservées sur cet appareil', Icon: Smartphone },
} as const;

export function SyncIndicator({ transport }: { transport: SyncTransport }) {
  const { label, detail, Icon } = content[transport];
  return (
    <span className={`lk-sync-indicator lk-sync-${transport}`} role="status" aria-live="polite" title={detail}>
      <Icon size={12} aria-hidden="true" />
      <span>{label}</span>
      <span className="sr-only"> — {detail}</span>
    </span>
  );
}

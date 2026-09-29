import type { TenantCatalogueEvent, TenantCatalogueProduct } from './tenant-catalogue'

interface TenantCatalogueSnapshot {
  version: 1
  products: TenantCatalogueProduct[]
  events: TenantCatalogueEvent[]
}

const keyFor = (tenantId: string) => `lynkstor:tenant-catalogue:v1:${tenantId}`
const SHOP_SESSION_KEY = 'lynkstor:shop-session:v1'

export interface ShopSession {
  tenantId: string
  shopName: string
  shopCity: string
  sector: string
  categories: string[]
}

function isSnapshot(value: unknown): value is TenantCatalogueSnapshot {
  if (!value || typeof value !== 'object') return false
  const snapshot = value as Partial<TenantCatalogueSnapshot>
  return snapshot.version === 1 && Array.isArray(snapshot.products) && Array.isArray(snapshot.events)
}

export function loadTenantCatalogue(tenantId: string): TenantCatalogueSnapshot | null {
  try {
    const value: unknown = JSON.parse(localStorage.getItem(keyFor(tenantId)) ?? 'null')
    return isSnapshot(value) ? value : null
  } catch { return null }
}

export function saveTenantCatalogue(tenantId: string, products: TenantCatalogueProduct[], events: TenantCatalogueEvent[]): boolean {
  try {
    localStorage.setItem(keyFor(tenantId), JSON.stringify({ version: 1, products, events } satisfies TenantCatalogueSnapshot))
    return true
  } catch { return false }
}

export function loadShopSession(): ShopSession | null {
  try {
    const value: unknown = JSON.parse(localStorage.getItem(SHOP_SESSION_KEY) ?? 'null')
    if (!value || typeof value !== 'object') return null
    const session = value as Partial<ShopSession>
    return typeof session.tenantId === 'string' && typeof session.shopName === 'string' && typeof session.shopCity === 'string' && typeof session.sector === 'string' && Array.isArray(session.categories) && session.categories.every((category) => typeof category === 'string') ? session as ShopSession : null
  } catch { return null }
}

export function saveShopSession(session: ShopSession): boolean {
  try {
    localStorage.setItem(SHOP_SESSION_KEY, JSON.stringify(session))
    return true
  } catch { return false }
}

export function clearShopSession(): void {
  try { localStorage.removeItem(SHOP_SESSION_KEY) } catch { /* L’application reste fonctionnelle dans la session en cours. */ }
}

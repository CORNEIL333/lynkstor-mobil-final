import manifestJson from './generated/manifest.json'
import bakeryUrl from './generated/boulangerie.json?url'
import perfumeryUrl from './generated/parfumerie.json?url'
import electronicsUrl from './generated/telephonie-electromenager.json?url'
import type { CatalogueItem, CatalogueLoadResult, CatalogueManifestEntry } from './types'

export const CATALOGUES = manifestJson as CatalogueManifestEntry[]
const catalogueUrls: Record<string, string> = {
  boulangerie: bakeryUrl,
  parfumerie: perfumeryUrl,
  'telephonie-electromenager': electronicsUrl,
}

export function getSectorCatalogue(sector: string): CatalogueManifestEntry | undefined {
  return CATALOGUES.find((catalogue) => catalogue.sectors.includes(sector))
}

export function normalizeCatalogueSearch(value: string): string {
  return value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase('fr').trim()
}

function validateItems(value: unknown, count: number): value is CatalogueItem[] {
  return Array.isArray(value) && value.length === count && value.every((item) =>
    item && typeof item === 'object' && typeof item.id === 'string' && typeof item.name === 'string' &&
    typeof item.category === 'string' && typeof item.priceStatus === 'string' && typeof item.stockStatus === 'string' &&
    (item.price === null || (Number.isSafeInteger(item.price) && item.price > 1)),
  )
}

function openCache(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open('lynkstor-reference-catalogues', 1)
    request.onupgradeneeded = () => request.result.createObjectStore('catalogues')
    request.onsuccess = () => resolve(request.result)
    request.onerror = () => reject(request.error)
  })
}

async function readCache(key: string): Promise<unknown> {
  const database = await openCache()
  try {
    return await new Promise((resolve, reject) => {
      const request = database.transaction('catalogues').objectStore('catalogues').get(key)
      request.onsuccess = () => resolve(request.result)
      request.onerror = () => reject(request.error)
    })
  } finally { database.close() }
}

async function writeCache(key: string, items: CatalogueItem[]): Promise<void> {
  const database = await openCache()
  try {
    await new Promise<void>((resolve, reject) => {
      const transaction = database.transaction('catalogues', 'readwrite')
      transaction.objectStore('catalogues').put(items, key)
      transaction.oncomplete = () => resolve()
      transaction.onerror = () => reject(transaction.error)
      transaction.onabort = () => reject(transaction.error)
    })
  } finally { database.close() }
}

export async function loadCatalogue(id: string): Promise<CatalogueLoadResult> {
  const catalogue = CATALOGUES.find((entry) => entry.id === id)
  if (!catalogue || !catalogueUrls[id]) return { ok: false, problem: { type: 'catalogue-invalid', title: 'Catalogue inconnu', detail: 'La référence demandée ne fait pas partie des catalogues Lynkstor.' } }
  const cacheKey = `${catalogue.id}:${catalogue.version}`
  try {
    const cached = await readCache(cacheKey)
    if (validateItems(cached, catalogue.count)) return { ok: true, items: cached, offlineReady: true }
  } catch { /* Le fichier intégré reste accessible lorsque le cache navigateur est indisponible. */ }
  try {
    const response = await fetch(catalogueUrls[id])
    if (!response.ok) throw new Error(`HTTP ${response.status}`)
    const items: unknown = await response.json()
    if (!validateItems(items, catalogue.count)) return { ok: false, problem: { type: 'catalogue-invalid', title: 'Catalogue incomplet', detail: 'Les données reçues ne correspondent pas à la version publiée.' } }
    try { await writeCache(cacheKey, items); return { ok: true, items, offlineReady: true } }
    catch { return { ok: true, items, offlineReady: false } }
  } catch {
    return { ok: false, problem: { type: 'catalogue-unavailable', title: 'Catalogue indisponible', detail: 'Reconnectez-vous une fois pour télécharger ce catalogue sur l’appareil.' } }
  }
}

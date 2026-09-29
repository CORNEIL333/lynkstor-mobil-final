/** Projection read-only du catalogue métier. Les prix restent des observations fournisseurs. */
export interface CatalogueItem {
  id: string
  canonicalProductId: string
  offerId: string
  priceObservationId: string
  name: string
  categoryId: string
  category: string
  subcategory: string | null
  brand: string | null
  sku: string | null
  gtin: string | null
  packSize: string | null
  price: number | null
  regularPrice: number | null
  priceStatus: 'published' | 'quote_required' | 'needs_review'
  priceType: string
  promotion: boolean
  stockStatus: 'in_stock' | 'out_of_stock' | 'not_published'
  seller: string
  city: string | null
  sourceName: string
  sourceUrl: string | null
  observedAt: string
  qualityFlags: string[]
  needsReview: boolean
  emoji: string
}

export interface CatalogueCategory {
  id: string
  sourceId: string
  name: string
  description: string
}

export interface CatalogueManifestEntry {
  id: string
  title: string
  sectors: string[]
  emoji: string
  version: string
  observedOn: string
  categories: CatalogueCategory[]
  count: number
  canonicalCount: number
  pricedCount: number
  reviewCount: number
}

export type CatalogueLoadResult =
  | { ok: true; items: CatalogueItem[]; offlineReady: boolean }
  | { ok: false; problem: { type: 'catalogue-unavailable' | 'catalogue-invalid'; title: string; detail: string } }

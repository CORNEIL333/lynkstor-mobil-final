import type { CatalogueItem } from './types'
import { createLocalId } from './local-id.ts'

export type TenantCatalogueStatus = 'draft' | 'active' | 'archived'

export interface TenantCatalogueProduct {
  id: string
  tenantId: string
  centralVariantId: string
  canonicalProductId: string
  offerId: string
  priceObservationId: string
  name: string
  category: string
  sourceName: string
  sourceObservedAt: string
  sourceNeedsReview: boolean
  sourceReviewAcknowledged: boolean
  status: TenantCatalogueStatus
  sellingPrice: number | null
  initialStock: number | null
  stockOnHand: number | null
  salesUnit: string | null
  createdAt: string
  updatedAt: string
}

export interface TenantCatalogueEvent {
  id: string
  tenantId: string
  type: 'CatalogueReferenceSelectionnee' | 'PrixVenteDefini' | 'FicheProduitConfiguree' | 'StockProduitDiminue' | 'FicheProduitArchivee'
  productId: string
  occurredAt: string
}

export interface SelectionResult {
  products: TenantCatalogueProduct[]
  events: TenantCatalogueEvent[]
  added: TenantCatalogueProduct[]
  duplicateCount: number
}

export interface ProductConfiguration {
  sellingPrice: number
  initialStock: number
  salesUnit: string
}

function eventId(): string {
  return createLocalId('tenant-catalogue-event')
}

function validateInteger(value: number, message: string, minimum: number): void {
  if (!Number.isSafeInteger(value) || value < minimum) throw new Error(message)
}

export function productIdFor(item: CatalogueItem): string {
  return `central:${item.id}`
}

export function selectCatalogueReferences(
  tenantId: string,
  existing: TenantCatalogueProduct[],
  items: CatalogueItem[],
  now = new Date().toISOString(),
  reviewAcknowledged = false,
): SelectionResult {
  const existingIds = new Set(existing.map((product) => product.centralVariantId))
  const seen = new Set<string>()
  const added: TenantCatalogueProduct[] = []
  let duplicateCount = 0

  for (const item of items) {
    if (existingIds.has(item.id) || seen.has(item.id)) { duplicateCount += 1; continue }
    if (item.needsReview && !reviewAcknowledged) throw new Error('Certaines références demandent une validation avant leur ajout.')
    seen.add(item.id)
    added.push({
      id: productIdFor(item), tenantId, centralVariantId: item.id, canonicalProductId: item.canonicalProductId,
      offerId: item.offerId, priceObservationId: item.priceObservationId, name: item.name, category: item.category,
      sourceName: item.sourceName, sourceObservedAt: item.observedAt, sourceNeedsReview: item.needsReview,
      sourceReviewAcknowledged: item.needsReview, status: 'draft', sellingPrice: null, initialStock: null, stockOnHand: null,
      salesUnit: null, createdAt: now, updatedAt: now,
    })
  }
  return {
    products: [...existing, ...added], added, duplicateCount,
    events: added.map((product) => ({ id: eventId(), tenantId, type: 'CatalogueReferenceSelectionnee', productId: product.id, occurredAt: now })),
  }
}

export function configureTenantCatalogueProduct(
  product: TenantCatalogueProduct,
  configuration: ProductConfiguration,
  now = new Date().toISOString(),
): { product: TenantCatalogueProduct; event: TenantCatalogueEvent } {
  validateInteger(configuration.sellingPrice, 'Le prix de vente doit être un entier supérieur à zéro.', 1)
  validateInteger(configuration.initialStock, 'La quantité doit être un entier positif ou nul.', 0)
  const salesUnit = configuration.salesUnit.trim()
  if (!salesUnit || salesUnit.length > 80) throw new Error('L’unité de vente est obligatoire et limitée à 80 caractères.')
  const next: TenantCatalogueProduct = { ...product, sellingPrice: configuration.sellingPrice, initialStock: configuration.initialStock, stockOnHand: configuration.initialStock, salesUnit, status: 'active', updatedAt: now }
  return { product: next, event: { id: eventId(), tenantId: product.tenantId, type: 'FicheProduitConfiguree', productId: product.id, occurredAt: now } }
}

/** Le premier prix saisi en caisse reste privé tant que le stock n’est pas initialisé. */
export function setTenantCatalogueSellingPrice(
  product: TenantCatalogueProduct,
  sellingPrice: number,
  now = new Date().toISOString(),
): { product: TenantCatalogueProduct; event: TenantCatalogueEvent } {
  validateInteger(sellingPrice, 'Le prix de vente doit être un entier supérieur à zéro.', 1)
  const next: TenantCatalogueProduct = { ...product, sellingPrice, updatedAt: now }
  return {
    product: next,
    event: { id: eventId(), tenantId: product.tenantId, type: 'PrixVenteDefini', productId: product.id, occurredAt: now },
  }
}

export function deductTenantCatalogueStock(
  product: TenantCatalogueProduct,
  quantity: number,
  now = new Date().toISOString(),
): { product: TenantCatalogueProduct; event: TenantCatalogueEvent } {
  validateInteger(quantity, 'La quantité vendue doit être un entier positif.', 1)
  const stockOnHand = product.stockOnHand ?? product.initialStock
  if (stockOnHand === null || quantity > stockOnHand) throw new Error('Le stock disponible ne permet pas cette vente.')
  const next: TenantCatalogueProduct = { ...product, stockOnHand: stockOnHand - quantity, updatedAt: now }
  return {
    product: next,
    event: { id: eventId(), tenantId: product.tenantId, type: 'StockProduitDiminue', productId: product.id, occurredAt: now },
  }
}

export function archiveTenantCatalogueProduct(product: TenantCatalogueProduct, now = new Date().toISOString()): { product: TenantCatalogueProduct; event: TenantCatalogueEvent } {
  return { product: { ...product, status: 'archived', updatedAt: now }, event: { id: eventId(), tenantId: product.tenantId, type: 'FicheProduitArchivee', productId: product.id, occurredAt: now } }
}

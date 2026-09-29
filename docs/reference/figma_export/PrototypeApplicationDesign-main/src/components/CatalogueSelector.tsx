import { useEffect, useMemo, useState } from 'react'
import { Check, ChevronLeft, Search, ShieldAlert } from 'lucide-react'
import { getSectorCatalogue, loadCatalogue, normalizeCatalogueSearch } from '@/data/catalogue/catalogue'
import type { CatalogueItem } from '@/data/catalogue/types'
import { Button, Input } from '@/ui/primitives'

interface CatalogueSelectorProps {
  sector: string
  initialSelectedIds?: Iterable<string>
  onConfirm: (items: CatalogueItem[], reviewAcknowledged: boolean) => void
  onBack?: () => void
  onSkip?: () => void
  confirmLabel: string
}

const PAGE_SIZE = 48

export function CatalogueSelector({ sector, initialSelectedIds = [], onConfirm, onBack, onSkip, confirmLabel }: CatalogueSelectorProps) {
  const [items, setItems] = useState<CatalogueItem[]>([])
  const [selectedIds, setSelectedIds] = useState(() => new Set(initialSelectedIds))
  const [query, setQuery] = useState('')
  const [category, setCategory] = useState('Toutes')
  const [visibleCount, setVisibleCount] = useState(PAGE_SIZE)
  const [loading, setLoading] = useState(true)
  const [offlineReady, setOfflineReady] = useState(false)
  const [error, setError] = useState('')
  const [reviewAcknowledged, setReviewAcknowledged] = useState(false)
  const catalogue = getSectorCatalogue(sector)

  useEffect(() => {
    let active = true
    setLoading(true)
    setError('')
    setItems([])
    setSelectedIds(new Set(initialSelectedIds))
    setCategory('Toutes')
    setVisibleCount(PAGE_SIZE)
    if (!catalogue) { setLoading(false); setError(`Le catalogue ${sector} sera bientôt disponible. Vous pouvez démarrer avec un catalogue vide.`); return () => { active = false } }
    void loadCatalogue(catalogue.id).then((result) => {
      if (!active) return
      setLoading(false)
      if (!result.ok) { setError(result.problem.detail); return }
      setItems(result.items)
      setOfflineReady(result.offlineReady)
    })
    return () => { active = false }
  }, [catalogue?.id, sector])

  const filteredItems = useMemo(() => {
    const normalizedQuery = normalizeCatalogueSearch(query)
    return items.filter((item) => (category === 'Toutes' || item.category === category) && (!normalizedQuery || normalizeCatalogueSearch(`${item.name} ${item.brand ?? ''} ${item.sku ?? ''}`).includes(normalizedQuery)))
  }, [category, items, query])
  const visibleItems = filteredItems.slice(0, visibleCount)
  const selectedItems = useMemo(() => items.filter((item) => selectedIds.has(item.id)), [items, selectedIds])
  const selectedNeedsReview = selectedItems.some((item) => item.needsReview)

  const toggle = (id: string) => setSelectedIds((previous) => {
    const next = new Set(previous)
    next.has(id) ? next.delete(id) : next.add(id)
    return next
  })

  return (
    <section className="flex min-h-0 flex-1 flex-col bg-slate-50" aria-label="Sélection du catalogue Lynkstor">
      <header className="border-b border-slate-200 bg-white px-5 pb-3 pt-4">
        <div className="flex items-start gap-3">
          {onBack && <Button onClick={onBack} className="mt-0.5 flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-slate-100 text-slate-700" aria-label="Retour"><ChevronLeft size={20} /></Button>}
          <div className="min-w-0 flex-1"><p className="text-xs font-bold uppercase tracking-wide text-emerald-700">Catalogue Lynkstor</p><h2 className="text-lg font-extrabold text-slate-900">Choisissez vos produits de départ</h2><p className="mt-0.5 text-xs leading-5 text-slate-600">Ils seront ajoutés à votre boutique en brouillon. Vous définirez votre prix et votre stock ensuite.</p></div>
        </div>
        {!loading && !error && <div className="mt-3 flex items-center gap-2 rounded-xl bg-slate-100 px-3 py-2"><Search size={17} className="shrink-0 text-slate-500" /><Input value={query} onChange={(event) => { setQuery(event.target.value); setVisibleCount(PAGE_SIZE) }} placeholder="Rechercher un produit" className="min-w-0 flex-1 bg-transparent text-base outline-none" /></div>}
      </header>
      {loading && <div className="flex flex-1 items-center justify-center p-8 text-sm font-medium text-slate-600" aria-live="polite">Préparation du catalogue…</div>}
      {!loading && error && <div className="m-5 rounded-2xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-950"><p className="font-bold">Catalogue indisponible</p><p className="mt-1">{error}</p>{onSkip && <Button onClick={onSkip} className="mt-4 w-full rounded-xl bg-white py-3 font-bold text-slate-800 ring-1 ring-amber-300">Continuer sans produits</Button>}</div>}
      {!loading && !error && <>
        <div className="flex gap-2 overflow-x-auto border-b border-slate-200 bg-white px-5 py-2.5 scrollbar-hide">
          {['Toutes', ...Array.from(new Set(items.map((item) => item.category)))].map((entry) => <Button key={entry} onClick={() => { setCategory(entry); setVisibleCount(PAGE_SIZE) }} className={`shrink-0 rounded-full px-3 py-2 text-xs font-bold ${category === entry ? 'bg-slate-900 text-white' : 'bg-slate-100 text-slate-700'}`}>{entry}</Button>)}
        </div>
        <div className="min-h-0 flex-1 overflow-y-auto px-5 py-3 pb-28">
          <p className="mb-2 text-xs text-slate-600">{filteredItems.length} référence{filteredItems.length > 1 ? 's' : ''} · {offlineReady ? 'disponible hors ligne' : 'disponible cette session'}</p>
          <div className="space-y-2">
            {visibleItems.map((item) => {
              const selected = selectedIds.has(item.id)
              return <Button key={item.id} onClick={() => toggle(item.id)} aria-pressed={selected} className={`flex min-h-16 w-full items-center gap-3 rounded-2xl border p-3 text-left ${selected ? 'border-emerald-500 bg-emerald-50' : 'border-slate-200 bg-white'}`}>
                <span className={`flex h-6 w-6 shrink-0 items-center justify-center rounded-md border ${selected ? 'border-emerald-600 bg-emerald-600 text-white' : 'border-slate-300 bg-white'}`}>{selected && <Check size={15} strokeWidth={3} />}</span>
                <span className="min-w-0 flex-1"><span className="block text-sm font-bold text-slate-900">{item.name}</span><span className="mt-0.5 block truncate text-xs text-slate-600">{item.category}{item.brand ? ` · ${item.brand}` : ''}</span>{item.needsReview && <span className="mt-1 flex items-center gap-1 text-[11px] font-semibold text-amber-800"><ShieldAlert size={13} /> À vérifier</span>}</span>
              </Button>
            })}
          </div>
          {visibleCount < filteredItems.length && <Button onClick={() => setVisibleCount((value) => value + PAGE_SIZE)} className="mt-3 w-full rounded-xl bg-white py-3 text-sm font-bold text-slate-700 ring-1 ring-slate-200">Afficher davantage</Button>}
          {!visibleItems.length && <div className="rounded-2xl bg-white p-6 text-center text-sm text-slate-600">Aucun produit ne correspond à cette recherche.</div>}
        </div>
        <footer className="sticky bottom-0 border-t border-slate-200 bg-white px-5 pb-[max(16px,env(safe-area-inset-bottom))] pt-3 shadow-[0_-6px_18px_rgba(15,23,42,0.06)]">
          {selectedNeedsReview && <label className="mb-3 flex items-start gap-2 text-xs leading-5 text-amber-950"><input type="checkbox" checked={reviewAcknowledged} onChange={(event) => setReviewAcknowledged(event.target.checked)} className="mt-1 h-4 w-4 accent-emerald-600" />J’ai vérifié les références marquées « À vérifier » avant leur ajout.</label>}
          <Button disabled={!selectedItems.length || (selectedNeedsReview && !reviewAcknowledged)} onClick={() => onConfirm(selectedItems, reviewAcknowledged)} className="w-full rounded-2xl bg-emerald-600 py-3.5 text-sm font-extrabold text-white disabled:cursor-not-allowed disabled:opacity-45">{selectedItems.length ? `${confirmLabel} (${selectedItems.length})` : 'Sélectionnez des produits'}</Button>
        </footer>
      </>}
    </section>
  )
}

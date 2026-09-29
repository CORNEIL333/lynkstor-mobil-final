import { useEffect, useState } from 'react'
import { ChevronRight, QrCode, X } from 'lucide-react'
export interface QrClientOrderBannerProps { orderCount: number; onOpen: () => void; onDismiss: () => void; autoDismissMs?: number }
/** Alerte non bloquante pour les commandes QR réellement en attente. */
export function QrClientOrderBanner({ orderCount, onOpen, onDismiss, autoDismissMs = 8000 }: QrClientOrderBannerProps) {
  const [visible, setVisible] = useState(orderCount > 0)
  useEffect(() => { setVisible(orderCount > 0) }, [orderCount])
  useEffect(() => { if (!visible || autoDismissMs <= 0) return; const timer = window.setTimeout(() => { setVisible(false); onDismiss() }, autoDismissMs); return () => window.clearTimeout(timer) }, [autoDismissMs, onDismiss, visible])
  if (!visible || orderCount <= 0) return null
  return <aside className="lk-qr-banner" aria-live="polite" aria-label="Nouvelle commande QR client"><span className="lk-qr-banner-icon"><QrCode size={23} /></span><span className="lk-qr-banner-copy"><strong>Commande QR client détectée</strong><small>{orderCount} nouvelle{orderCount > 1 ? 's' : ''} commande{orderCount > 1 ? 's' : ''} en attente</small></span><button type="button" className="lk-qr-banner-open" onClick={onOpen}>Voir <ChevronRight size={18} /></button><button type="button" className="lk-qr-banner-dismiss" onClick={() => { setVisible(false); onDismiss() }} aria-label="Masquer l’alerte de commande QR"><X size={20} /></button></aside>
}

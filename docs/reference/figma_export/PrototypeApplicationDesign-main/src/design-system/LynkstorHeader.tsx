import type { ReactNode } from 'react'
import { Bell, ChevronLeft, Menu, ShoppingCart } from 'lucide-react'

export interface LynkstorHeaderProps {
  title: string; subtitle: string; avatar?: ReactNode; cartCount?: number; notificationCount?: number; qrClientCount?: number
  showBack?: boolean; onBack?: () => void; showMenu?: boolean; onMenu?: () => void; showCart?: boolean; onCart?: () => void
  showNotification?: boolean; onNotification?: () => void; children?: ReactNode
}
function CountBadge({ count }: { count: number }) {
  return count > 0 ? <span className="lk-header-count" aria-label={`${count} élément${count > 1 ? 's' : ''} en attente`}>{count > 99 ? '99+' : count}</span> : null
}
/** Chrome principal commun aux écrans métier Lynkstor. */
export function LynkstorHeader({ title, subtitle, avatar, cartCount = 0, notificationCount = 0, qrClientCount = 0, showBack = false, onBack, showMenu = true, onMenu, showCart = true, onCart, showNotification = true, onNotification, children }: LynkstorHeaderProps) {
  return <header className=" lk-header"><div className="lk-header-main">
    <div className="lk-header-profile" aria-hidden={avatar ? undefined : true}>{showBack ? <button type="button" className="lk-header-action lk-header-back" onClick={onBack} aria-label="Retour"><ChevronLeft size={25} strokeWidth={2.25} /></button> : avatar ?? <span className="lk-header-avatar-placeholder">LS</span>}</div>
    <div className="lk-header-copy"><h1>{title}</h1><p>{subtitle}</p></div>
    <div className="lk-header-actions" aria-label="Actions de l’écran">
      {showCart && <div className="lk-header-cart-wrap"><button type="button" className="lk-header-action" onClick={onCart} aria-label={`Panier, ${cartCount} article${cartCount > 1 ? 's' : ''}`}><ShoppingCart size={22} strokeWidth={2.2} /><CountBadge count={cartCount} /></button>{qrClientCount > 0 && <span className="lk-header-qr-label">QR client</span>}</div>}
      {showNotification && <button type="button" className="lk-header-action" onClick={onNotification} aria-label={`${notificationCount} notification${notificationCount > 1 ? 's' : ''}`}><Bell size={21} strokeWidth={2.2} /><CountBadge count={notificationCount} /></button>}
      {showMenu && <button type="button" className="lk-header-action" onClick={onMenu} aria-label="Ouvrir le menu"><Menu size={23} strokeWidth={2.2} /></button>}
    </div>
  </div>{children && <div className="lk-header-context pt-0 pr-[10px] pb-[14px] pl-4">{children}</div>}</header>
}

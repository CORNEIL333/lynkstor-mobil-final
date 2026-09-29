import type { ComponentType } from 'react'
export interface LynkstorNavigationItem<T extends string> { id: T; label: string; icon: ComponentType<{ size?: number; color?: string; strokeWidth?: number; className?: string }> }
export interface LynkstorBottomNavigationProps<T extends string> { activeIndex: T; items: readonly LynkstorNavigationItem<T>[]; onTap: (id: T) => void }
/** Navigation mobile à quatre destinations, sans changer le modèle de routes existant. */
export function LynkstorBottomNavigation<T extends string>({ activeIndex, items, onTap }: LynkstorBottomNavigationProps<T>) {
  return <nav className="lk-bottom-navigation" aria-label="Navigation principale">{items.map(({ id, label, icon: Icon }) => { const active = id === activeIndex; return <button key={id} type="button" className={`lk-bottom-navigation-item${active ? ' is-active' : ''}`} onClick={() => onTap(id)} aria-current={active ? 'page' : undefined}><span className="lk-bottom-navigation-icon"><Icon size={23} strokeWidth={active ? 2.45 : 2} /></span><span>{label}</span></button> })}</nav>
}

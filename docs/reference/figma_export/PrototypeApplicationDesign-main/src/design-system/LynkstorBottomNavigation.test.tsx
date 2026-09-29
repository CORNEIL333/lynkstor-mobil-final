import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { LynkstorBottomNavigation } from './LynkstorBottomNavigation'

const Icon = ({ className }: { className?: string }) => <svg aria-hidden="true" className={className} />

describe('LynkstorBottomNavigation', () => {
  it('expose la destination active et transmet la destination choisie', () => {
    const onTap = vi.fn()
    render(
      <LynkstorBottomNavigation
        activeIndex="vente"
        items={[
          { id: 'accueil', label: 'Accueil', icon: Icon },
          { id: 'vente', label: 'Vente', icon: Icon },
          { id: 'stock', label: 'Stock', icon: Icon },
        ]}
        onTap={onTap}
      />,
    )

    expect(screen.getByRole('navigation', { name: 'Navigation principale' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Vente' })).toHaveAttribute('aria-current', 'page')
    expect(screen.getByRole('button', { name: 'Accueil' })).not.toHaveAttribute('aria-current')

    fireEvent.click(screen.getByRole('button', { name: 'Stock' }))
    expect(onTap).toHaveBeenCalledWith('stock')
  })
})

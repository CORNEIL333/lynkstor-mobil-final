import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { QrClientOrderBanner } from './QrClientOrderBanner'

describe('QrClientOrderBanner', () => {
  it('annonce la commande et laisse l’utilisateur l’ouvrir ou la masquer', () => {
    const onOpen = vi.fn()
    const onDismiss = vi.fn()
    render(<QrClientOrderBanner orderCount={2} onOpen={onOpen} onDismiss={onDismiss} autoDismissMs={0} />)

    expect(screen.getByLabelText('Nouvelle commande QR client')).toBeInTheDocument()
    expect(screen.getByText('2 nouvelles commandes en attente')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /voir/i }))
    expect(onOpen).toHaveBeenCalledOnce()

    fireEvent.click(screen.getByRole('button', { name: 'Masquer l’alerte de commande QR' }))
    expect(onDismiss).toHaveBeenCalledOnce()
    expect(screen.queryByLabelText('Nouvelle commande QR client')).not.toBeInTheDocument()
  })

  it('ne rend rien lorsqu’aucune commande QR n’est en attente', () => {
    render(<QrClientOrderBanner orderCount={0} onOpen={vi.fn()} onDismiss={vi.fn()} />)
    expect(screen.queryByLabelText('Nouvelle commande QR client')).not.toBeInTheDocument()
  })
})

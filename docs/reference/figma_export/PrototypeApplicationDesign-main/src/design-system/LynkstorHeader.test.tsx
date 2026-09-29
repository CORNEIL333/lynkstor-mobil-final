import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { LynkstorHeader } from './LynkstorHeader'

describe('LynkstorHeader', () => {
  it('affiche les compteurs accessibles et transmet les actions de chrome', () => {
    const onCart = vi.fn()
    const onNotification = vi.fn()
    const onMenu = vi.fn()
    render(
      <LynkstorHeader
        title="Vente"
        subtitle="Caisse mobile"
        cartCount={3}
        notificationCount={2}
        qrClientCount={1}
        onCart={onCart}
        onNotification={onNotification}
        onMenu={onMenu}
      />,
    )

    expect(screen.getByRole('heading', { name: 'Vente' })).toBeInTheDocument()
    expect(screen.getByText('QR client')).toBeInTheDocument()
    expect(screen.getByLabelText('3 éléments en attente')).toBeInTheDocument()
    expect(screen.getByLabelText('2 éléments en attente')).toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: 'Panier, 3 articles' }))
    fireEvent.click(screen.getByRole('button', { name: '2 notifications' }))
    fireEvent.click(screen.getByRole('button', { name: 'Ouvrir le menu' }))
    expect(onCart).toHaveBeenCalledOnce()
    expect(onNotification).toHaveBeenCalledOnce()
    expect(onMenu).toHaveBeenCalledOnce()
  })
})

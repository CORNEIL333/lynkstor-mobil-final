import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { ThemePicker, ThemeProvider } from './ThemeProvider'

describe('ThemeProvider', () => {
  it('applique et mémorise le thème choisi sans modifier la structure du picker', () => {
    render(<ThemeProvider><ThemePicker /></ThemeProvider>)

    fireEvent.click(screen.getByRole('radio', { name: 'Clair' }))
    expect(document.documentElement.dataset.theme).toBe('light')
    expect(localStorage.getItem('lynkstor.merchant.theme.v1')).toBe('light')

    fireEvent.click(screen.getByRole('radio', { name: 'Sombre' }))
    expect(document.documentElement.dataset.theme).toBe('dark')
    expect(localStorage.getItem('lynkstor.merchant.theme.v1')).toBe('dark')
  })
})

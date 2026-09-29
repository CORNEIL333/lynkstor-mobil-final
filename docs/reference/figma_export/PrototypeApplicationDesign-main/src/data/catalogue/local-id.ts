type LocalCrypto = {
  randomUUID?: () => string
  getRandomValues?: (values: Uint32Array) => Uint32Array
}

/**
 * Identifiants locaux : ils ne portent aucune information métier sensible et
 * doivent aussi fonctionner dans les webviews qui ne proposent pas randomUUID.
 */
export function createLocalId(prefix: string, cryptoApi: LocalCrypto | null = globalThis.crypto): string {
  if (typeof cryptoApi?.randomUUID === 'function') return `${prefix}:${cryptoApi.randomUUID()}`

  if (typeof cryptoApi?.getRandomValues === 'function') {
    const values = cryptoApi.getRandomValues(new Uint32Array(4))
    return `${prefix}:${Array.from(values, (value) => value.toString(36)).join('')}`
  }

  return `${prefix}:${Date.now().toString(36)}:${Math.random().toString(36).slice(2, 12)}`
}

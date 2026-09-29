import { useState } from 'react';
import { Store } from 'lucide-react';
export interface ShopIdentityData { id: string; name: string; city: string; image?: { url: string; fit?: 'contain' | 'cover' } | null }
export function ShopAvatar({ shop, size = 44 }: { shop: ShopIdentityData; size?: 32 | 40 | 44 | 64 }) {
  const [failedUrl, setFailedUrl] = useState<string | null>(null);
  const words = shop.name.trim().split(/\s+/u).filter(Boolean);
  const initials = words.slice(0, 2).map(word => Array.from(word)[0]).join('').toLocaleUpperCase('fr');
  const src = shop.image?.url;
  return <span className="lk-shop-avatar" style={{ width: size, height: size }} aria-hidden="true">{initials || <Store size={size / 2} />}
    {src && src !== failedUrl && <img src={src} alt="" style={{ objectFit: shop.image?.fit ?? 'contain' }} onError={() => setFailedUrl(src)} />}</span>;
}
export function ShopIdentity({ shop, size = 44, avatar = true }: { shop: ShopIdentityData; size?: 32 | 40 | 44 | 64; avatar?: boolean }) {
  return <div className="lk-shop-identity">{avatar && <ShopAvatar shop={shop} size={size} />}<div><strong>{shop.name.trim() || 'Boutique à configurer'}</strong>{shop.city && <span>{shop.city}</span>}</div></div>;
}

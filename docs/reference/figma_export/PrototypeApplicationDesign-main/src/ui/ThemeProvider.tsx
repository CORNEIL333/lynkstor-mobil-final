import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
export type ThemePreference = 'light' | 'dark' | 'system';
const KEY = 'lynkstor.merchant.theme.v1';
const valid = (v: unknown): v is ThemePreference => v === 'light' || v === 'dark' || v === 'system';
const ThemeContext = createContext<{ preference: ThemePreference; setPreference: (p: ThemePreference) => void; persistent: boolean } | null>(null);
export function ThemeProvider({ children }: { children: ReactNode }) {
  const [preference, setChoice] = useState<ThemePreference>(() => {
    const initial = document.documentElement.dataset.themePreference;
    return valid(initial) ? initial : 'system';
  });
  const [persistent, setPersistent] = useState(true);
  useEffect(() => {
    const media = matchMedia('(prefers-color-scheme: dark)');
    const apply = () => {
      document.documentElement.dataset.theme = preference === 'system' ? (media.matches ? 'dark' : 'light') : preference;
      document.documentElement.dataset.themePreference = preference;
    };
    apply();
    media.addEventListener('change', apply);
    return () => media.removeEventListener('change', apply);
  }, [preference]);
  useEffect(() => {
    const onStorage = (e: StorageEvent) => { if (e.key === KEY || e.key === null) setChoice(valid(e.newValue) ? e.newValue : 'system'); };
    window.addEventListener('storage', onStorage);
    return () => window.removeEventListener('storage', onStorage);
  }, []);
  const setPreference = (next: ThemePreference) => {
    setChoice(next);
    document.documentElement.dataset.theme = next === 'system' ? (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light') : next;
    document.documentElement.dataset.themePreference = next;
    try { localStorage.setItem(KEY, next); setPersistent(true); }
    catch { setPersistent(false); }
  };
  return <ThemeContext.Provider value={{ preference, setPreference, persistent }}>{children}</ThemeContext.Provider>;
}
export function useTheme() {
  const value = useContext(ThemeContext);
  if (!value) throw new Error('ThemeProvider is required');
  return value;
}
export function ThemePicker() {
  const { preference, setPreference, persistent } = useTheme();
  return <fieldset className="lk-appearance"><legend>Apparence</legend>
    <p>Système suit les réglages de votre appareil.</p>
    <div className="lk-theme-options">
      {([{ value: 'light', label: 'Clair' }, { value: 'dark', label: 'Sombre' }, { value: 'system', label: 'Système' }] as const).map(({ value, label }) =>
        <label key={value} className="lk-theme-option"><input type="radio" name="appearance" value={value} checked={preference === value} onChange={() => setPreference(value)} />
          <span className={`lk-theme-preview lk-preview-${value}`} aria-hidden="true"><i /><i /><i /></span><span>{label}</span></label>)}
    </div>
    {!persistent && <p role="status">Choix appliqué pour cette session. Votre navigateur ne permet pas de l’enregistrer.</p>}
  </fieldset>;
}

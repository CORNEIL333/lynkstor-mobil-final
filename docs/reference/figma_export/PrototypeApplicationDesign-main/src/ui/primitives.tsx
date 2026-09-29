import { Component, useEffect, useId, useRef, type ButtonHTMLAttributes, type InputHTMLAttributes, type SelectHTMLAttributes, type HTMLAttributes, type ReactNode, type ErrorInfo } from 'react';
export function Button({ type = 'button', className = '', title, ...props }: ButtonHTMLAttributes<HTMLButtonElement>) {
  return <button type={type} title={title} aria-label={props['aria-label'] ?? title} className={`lk-button ${className}`} {...props} />;
}
export function IconButton({ label, ...props }: ButtonHTMLAttributes<HTMLButtonElement> & { label: string }) {
  return <Button {...props} aria-label={label} title={label} className={`lk-icon-button ${props.className ?? ''}`} />;
}
export function Input({ className = '', ...props }: InputHTMLAttributes<HTMLInputElement>) { return <input className={`lk-input ${className}`} {...props} />; }
export function Select({ className = '', ...props }: SelectHTMLAttributes<HTMLSelectElement>) { return <select className={`lk-select ${className}`} {...props} />; }
export function Field({ label, error, hint, id, ...props }: InputHTMLAttributes<HTMLInputElement> & { label: string; error?: string; hint?: string }) {
  const generated = useId();
  const fieldId = id ?? generated;
  return <div className="lk-field"><label htmlFor={fieldId}>{label}</label><Input {...props} id={fieldId} aria-invalid={Boolean(error)} aria-describedby={error || hint ? `${fieldId}-help` : undefined} />{(error || hint) && <p id={`${fieldId}-help`} role={error ? 'alert' : undefined}>{error ?? hint}</p>}</div>;
}
export function Badge({ tone = 'info', children }: { tone?: 'info' | 'success' | 'warning' | 'danger'; children: ReactNode }) { return <span className={`lk-badge lk-badge-${tone}`}>{children}</span>; }
/** Native top-layer dialog shares focus containment, inert background and Escape. */
export function Dialog({ children, label, onDismiss, className = '', ...props }: HTMLAttributes<HTMLDivElement> & { label: string; onDismiss: () => void }) {
  const dialogRef = useRef<HTMLDialogElement>(null);
  const dismissRef = useRef(onDismiss);
  dismissRef.current = onDismiss;
  const headingId = useId();
  useEffect(() => {
    const dialog = dialogRef.current;
    if (!dialog) return;
    const previous = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    const heading = dialog.querySelector('h1,h2,h3');
    if (heading) { if (!heading.id) heading.id = headingId; dialog.setAttribute('aria-labelledby', heading.id); }
    dialog.showModal();
    return () => { dialog.close(); if (previous?.isConnected) previous.focus({ preventScroll: true }); };
  }, [headingId]);
  return <dialog ref={dialogRef} className="lk-dialog" aria-label={label} onClick={e => { if (e.target === e.currentTarget) dismissRef.current(); }} onCancel={e => { e.preventDefault(); dismissRef.current(); }}><div {...props} className={`lk-modal-body ${className}`}>{children}</div></dialog>;
}
export function Sheet(props: Parameters<typeof Dialog>[0]) { return <Dialog {...props} className={`lk-sheet ${props.className ?? ''}`} />; }
export class AppErrorBoundary extends Component<{ children: ReactNode }, { failed: boolean }> {
  state = { failed: false };
  static getDerivedStateFromError() { return { failed: true }; }
  componentDidCatch(error: Error, info: ErrorInfo) { console.error('Lynkstor render error', error, info.componentStack); }
  render() {
    if (this.state.failed) return <main className="lk-error"><h1>L’affichage a rencontré un problème</h1><p>Vous pouvez réessayer. Recharger entièrement la page efface les données de cette démonstration.</p><Button onClick={() => this.setState({ failed: false })}>Réessayer l’affichage</Button></main>;
    return this.props.children;
  }
}

// Лента на терминала за входните екрани (hacker тема). Чисто декоративна.

export function TermBar({ label }: { label: string }) {
  return (
    <div className="login-term-bar" aria-hidden="true">
      <span className="term-dot term-dot-r" />
      <span className="term-dot term-dot-y" />
      <span className="term-dot term-dot-g" />
      <span className="term-title">{label}</span>
    </div>
  );
}

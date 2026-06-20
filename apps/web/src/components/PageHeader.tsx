import type { ReactNode } from "react";

export function PageHeader({ title, kicker, actions }: { title: string; kicker: string; actions?: ReactNode }) {
  return (
    <header className="page-header">
      <div>
        <span className="page-kicker">{kicker}</span>
        <h1>{title}</h1>
      </div>
      {actions ? <div className="actions">{actions}</div> : null}
    </header>
  );
}

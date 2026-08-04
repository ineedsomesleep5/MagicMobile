import type { Metadata } from "next";
import type { ReactNode } from "react";
import Link from "next/link";
import "./globals.css";

export const metadata: Metadata = {
  title: "MagicMobile",
  description: "A polished Commander game powered by XMage rules"
};

const navItems: Array<[href: string, label: string]> = [
  ["/", "Home"],
  ["/decks", "Decks"],
  ["/play", "Play"],
  ["/account", "Account"]
];

export default function RootLayout({ children }: Readonly<{ children: ReactNode }>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body>
        <div className="app-shell">
          <aside className="side-nav">
            <Link className="brand" href="/">
              <span className="brand-mark" aria-hidden="true">M</span>
              <span className="brand-copy">
                <strong>MagicMobile</strong>
                <span>Commander, refined.</span>
              </span>
            </Link>
            <nav aria-label="Primary">
              {navItems.map(([href, label]) => (
                <Link href={href} key={href}>
                  {label}
                </Link>
              ))}
            </nav>
          </aside>
          <main className="content">{children}</main>
          <nav className="mobile-nav" aria-label="Primary mobile navigation">
            {navItems.map(([href, label]) => (
              <Link href={href} key={href}>{label}</Link>
            ))}
          </nav>
        </div>
      </body>
    </html>
  );
}

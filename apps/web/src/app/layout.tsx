import type { Metadata } from "next";
import type { ReactNode } from "react";
import Link from "next/link";
import "./globals.css";

export const metadata: Metadata = {
  title: "MagicMobile",
  description: "Commander-first tabletop and digital play scaffold"
};

const navItems: Array<[href: string, label: string]> = [
  ["/", "Home"],
  ["/decks", "Decks"],
  ["/cards", "Cards"],
  ["/play", "Play"],
  ["/rooms/demo-room", "Room"],
  ["/settings", "Settings"],
  ["/dev/engine", "Engine"],
  ["/dev/components", "Components"]
];

export default function RootLayout({ children }: Readonly<{ children: ReactNode }>) {
  return (
    <html lang="en">
      <body>
        <div className="app-shell">
          <aside className="side-nav">
            <Link className="brand" href="/">
              <strong>MagicMobile</strong>
              <span>Commander tables, clear state.</span>
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
        </div>
      </body>
    </html>
  );
}

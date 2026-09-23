import { Suspense, lazy, useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  AppleLogo,
  AndroidLogo,
  ArrowUpRight,
  ArrowRight,
  Plus,
} from "@phosphor-icons/react";
import "@fontsource-variable/archivo";
import "@fontsource-variable/manrope";
import "./style.css";
import { cards } from "./cards";
import { releases } from "./releases";

declare global {
  interface Window {
    ScrollCraft?: {
      mount: (root: HTMLElement) => unknown;
      instances: unknown[];
    };
  }
}
const CardScene = lazy(() => import("./CardScene"));
const android = releases.android.url;
const ios = releases.ios.url;

function App() {
  const [platform, setPlatform] = useState<"android" | "ios">("android");
  useEffect(() => {
    const boot = () => {
      if (matchMedia("(max-width: 650px)").matches) {
        document.getElementById("cards")?.setAttribute("data-sc-span", "1.5");
        document.getElementById("the-app")?.setAttribute("data-sc-span", "2.2");
      }
      if (window.ScrollCraft && !window.ScrollCraft.instances.length)
        window.ScrollCraft.mount(document.body);
    };
    boot();
    window.addEventListener("load", boot, { once: true });
    return () => window.removeEventListener("load", boot);
  }, []);
  return (
    <>
      <a className="skip" href="#main">
        Skip to content
      </a>
      <header className="masthead">
        <a className="brand" href="#cards" aria-label="MagicMobile home">
          <img src="/app-icon.png" alt="" width="36" height="36" />
          <span>MagicMobile</span>
        </a>
        <a className="header-download" href="#download">
          Get the game <ArrowUpRight size={18} />
        </a>
      </header>
      <nav className="destination-dock" aria-label="Page destinations">
        <a href="#cards">The cards</a>
        <a href="#the-app">The app</a>
        <a href="#download">
          Download <ArrowUpRight size={14} />
        </a>
      </nav>
      <main id="main">
        <section
          id="cards"
          className="opening"
          data-sc-act="pin"
          data-sc-span="1.8"
        >
          <div data-sc-stage className="opening-stage">
            <div className="hero-type" data-sc-parallax="0.6">
              <h1>
                MAKE YOUR
                <br />
                <span>NEXT MOVE.</span>
              </h1>
            </div>
            <div className="hand-stage">
              <Suspense
                fallback={
                  <img
                    className="loading-card"
                    src="/black-lotus.webp"
                    alt="Black Lotus collectible card"
                    width="672"
                    height="936"
                  />
                }
              >
                <CardScene />
              </Suspense>
            </div>
            <div className="hero-bottom">
              <p>
                Commander. Your decks.
                <br />A whole game in your pocket.
              </p>
              <div className="hero-downloads">
                <a href={ios}>
                  <AppleLogo weight="fill" size={22} />
                  <span>iPhone</span>
                  <ArrowUpRight size={16} />
                </a>
                <a href={android}>
                  <AndroidLogo size={22} />
                  <span>Android</span>
                  <ArrowUpRight size={16} />
                </a>
              </div>
            </div>
          </div>
        </section>
        <section className="invitation" data-sc-act="flow">
          <div className="invitation-inner" data-sc-in data-sc-stagger="65">
            <p>A new deck. A wild idea. One more game.</p>
            <h2>
              Good games begin
              <br />
              with <span>your next idea.</span>
            </h2>
          </div>
        </section>
        <section
          id="the-app"
          className="app-reveal"
          data-sc-act="pin"
          data-sc-span="2.8"
        >
          <div data-sc-stage className="app-reveal-stage">
            <div className="reveal-title" data-sc-cue="0 0.42 0 0.15">
              <h2>
                FROM YOUR HAND.
                <br />
                <span>TO YOUR PHONE.</span>
              </h2>
            </div>
            <div className="deal-table" aria-hidden="true">
              {[-2, -1, 0, 1, 2].map((n) => (
                <img
                  key={n}
                  className={`dealt-card dealt-card-${n + 2}`}
                  src={cards[n + 3].image}
                  width="1060"
                  height="1484"
                  alt=""
                />
              ))}
            </div>
            <div className="reveal-phone-wrap">
              <div
                className="reveal-phone"
                data-sc-reveal="up"
                data-sc-reveal-at="0.22 0.57"
              >
                <img
                  src="/studio-portrait.webp"
                  alt="Actual iOS Deck Studio: a Commander deck being edited"
                  width="1206"
                  height="2622"
                />
              </div>
            </div>
            <div className="reveal-caption" data-sc-cue="0.5 1 0.05 0.03">
              <h3>
                Your deck.
                <br />
                Your way.
              </h3>
              <p>
                Search cards. Import a list.
                <br />
                Build something worth playing.
              </p>
              <span>Actual iOS app preview</span>
            </div>
          </div>
        </section>
        <section className="gameplay" data-sc-act="flow">
          <div className="gameplay-copy" data-sc-in data-sc-stagger="60">
            <p className="section-label">The next decision is yours.</p>
            <h2>
              LESS SETUP.
              <br />
              <span>MORE MAGIC.</span>
            </h2>
            <p>
              Take your Commander ideas to the table. Play against AI, with the
              rules handled by the XMage engine.
            </p>
            <div className="capability-ledger">
              <div>
                <span>Build</span>
                <p>Deck imports, card search, and room to experiment.</p>
              </div>
              <div>
                <span>Play</span>
                <p>
                  Commander against AI. On iPhone, play with 2–4 people through
                  Game Center in the current TestFlight beta.
                </p>
              </div>
            </div>
          </div>
          <figure className="gameplay-image">
            <div className="gameplay-ground" aria-hidden="true">
              PLAY.
            </div>
            <div className="gameplay-phone" data-sc-parallax="-1.1">
              <img
                src="/game.webp"
                alt="iOS Commander battlefield development preview, not a live match"
                width="1206"
                height="2622"
                loading="lazy"
              />
            </div>
            <figcaption>
              iOS development preview. Not a live-match capture.
            </figcaption>
          </figure>
        </section>
        <section id="download" className="download" data-sc-act="flow">
          <div className="download-heading" data-sc-in data-sc-stagger="60">
            <h2>YOUR TURN.</h2>
            <p>Pick your phone. Take the game with you.</p>
          </div>
          <div className="download-desk">
            <div
              className="platform-picker"
              role="group"
              aria-label="Choose phone platform"
            >
              <button
                aria-pressed={platform === "android"}
                onClick={() => setPlatform("android")}
              >
                <AndroidLogo size={28} />
                Android
                <ArrowRight size={22} />
              </button>
              <button
                aria-pressed={platform === "ios"}
                onClick={() => setPlatform("ios")}
              >
                <AppleLogo weight="fill" size={28} />
                iPhone
                <ArrowRight size={22} />
              </button>
            </div>
            <div className="platform-detail" aria-live="polite">
              <div className="release-version">
                <strong>Version {releases[platform].version}</strong>
                <span>Build {releases[platform].build}</span>
                {platform === "android" && (
                  <a href={releases.android.notes}>Release notes ↗</a>
                )}
              </div>
              <div className="platform-detail-heading">
                <span>
                  {platform === "android" ? "Android alpha" : "iPhone beta"}
                </span>
                <span>
                  {platform === "android" ? "Android APK" : "Apple TestFlight"}
                </span>
              </div>
              <p>
                {platform === "android"
                  ? "Your next game is one download away."
                  : "Play against AI or meet other players through Game Center."}
              </p>
              <a
                className="download-action"
                href={platform === "android" ? android : ios}
              >
                {platform === "android"
                  ? "Download Android"
                  : "Join TestFlight"}
                <ArrowUpRight size={26} />
              </a>
              <small>
                {platform === "android"
                  ? "Android 8+ · ARM64. Hosted on GitHub. No account needed."
                  : `iOS 17+. ${releases.ios.status} Install TestFlight, then accept the invitation.`}
              </small>
            </div>
          </div>
          <div className="faq">
            <details>
              <summary>
                Installing on Android
                <Plus size={20} />
              </summary>
              <p>
                Open the APK link on your Android phone, then open the
                downloaded file. If asked, allow your browser to install this
                app. You can turn that permission off after installation.
              </p>
            </details>
            <details>
              <summary>
                What to expect from the alpha
                <Plus size={20} />
              </summary>
              <p>
                Deck building and local Commander against AI are available.
                Android is an early alpha; physical-phone acceptance is still
                pending. Live games do not yet resume after Android terminates
                the app process. Multiplayer is not included.
              </p>
            </details>
            <details>
              <summary>
                What’s new on iPhone?
                <Plus size={20} />
              </summary>
              <p>
                Build 11 fixes the solo AI starting-player flow: choosing Roll D20
                now opens the animated roll instead of asking you to pick a player.
                It also includes Game Center games with friends and AI opponents,
                a shared D20 roll, and cancellable turn-skipping. Apple has
                approved this build for Internal and External TestFlight.
              </p>
            </details>
            <details>
              <summary>
                Playing in the browser
                <Plus size={20} />
              </summary>
              <p>
                Not available yet. This website is your home for the phone
                downloads. Browser play is something we can explore next.
              </p>
            </details>
          </div>
          <footer>
            <a className="footer-brand" href="#cards">
              MagicMobile
              <ArrowUpRight size={24} />
            </a>
            <a href="https://github.com/ineedsomesleep5/MagicMobile">
              Follow the project
              <ArrowUpRight size={16} />
            </a>
            <p>
              Independent fan project. Not affiliated with Wizards of the Coast.
              Magic: The Gathering and card artwork belong to their respective
              owners. Black Lotus art by Chris Rahn, via{" "}
              <a href="https://scryfall.com/card/vma/4/black-lotus">Scryfall</a>
              . Showcase card only; not Commander legal.
            </p>
          </footer>
        </section>
      </main>
    </>
  );
}
createRoot(document.getElementById("root")!).render(<App />);

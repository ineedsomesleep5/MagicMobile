import { Suspense, lazy, useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  AppleLogo,
  AndroidLogo,
  ArrowUpRight,
  ArrowRight,
  Plus,
} from "@phosphor-icons/react";
import "@fontsource-variable/source-serif-4/opsz.css";
import "./style.css";
import { cards } from "./cards";
import { obtainium, releases } from "./releases";

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

/** The four-point sparkle from the MagicMobile mark, for labels and rules. */
function Sparkle() {
  return (
    <svg className="sparkle" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path d="M12 0c.9 6.2 4.6 10.4 12 12-7.4 1.6-11.1 5.8-12 12-.9-6.2-4.6-10.4-12-12C7.4 10.4 11.1 6.2 12 0z" />
    </svg>
  );
}

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
          <img src="/tavern/mark-96.webp" alt="" width="40" height="40" />
          <span>MagicMobile</span>
        </a>
        <a className="header-download plaque plaque-thin" href="#download">
          Get the game <ArrowUpRight size={16} />
        </a>
      </header>
      <nav className="destination-dock" aria-label="Page destinations">
        <a href="#cards">The cards</a>
        <a href="#the-app">The app</a>
        <a className="dock-download" href="#download">
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
            <div className="embers" aria-hidden="true">
              {Array.from({ length: 10 }, (_, i) => (
                <i key={i} />
              ))}
            </div>
            <div className="hero-type" data-sc-parallax="0.6">
              <h1>
                Make your
                <br />
                <span>next move.</span>
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
                <a className="plaque" href={ios}>
                  <AppleLogo weight="fill" size={22} />
                  <span>iPhone</span>
                  <ArrowUpRight size={16} />
                </a>
                <a className="plaque" href={android}>
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
            <p className="eyebrow">
              <Sparkle />
              A new deck. A wild idea. One more game.
            </p>
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
                From your hand.
                <br />
                <span>To your phone.</span>
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
                  src="/menu-landscape.webp"
                  alt="Actual iOS main menu in landscape: Play Commander, Decks and Friends beside the chosen Commander deck"
                  width="1300"
                  height="598"
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
            <p className="section-label eyebrow">
              <Sparkle />
              The next decision is yours.
            </p>
            <h2>
              Less setup.
              <br />
              <span>More magic.</span>
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
                  Commander against AI, or 2–4 people at one table. iPhone,
                  iPad and Android players host or join the same table with a
                  code, and Apple-only groups can also play through Game Center.
                </p>
              </div>
              <div>
                <span>Climb</span>
                <p>
                  Ranked 1v1 from Bronze to Mythic in monthly seasons, Quick
                  Match at your deck’s bracket, challenges with friends, and a
                  profile with your stats.
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
                src="/board-portrait.webp"
                alt="iOS Commander battlefield development preview on the walnut table, not a live match"
                width="660"
                height="1434"
                loading="lazy"
              />
            </div>
            <figcaption>
              iOS development preview. Not a live-match capture.
            </figcaption>
          </figure>
          <figure className="table-shot">
            <div className="table-frame">
              <img
                src="/board-landscape.webp"
                alt="iOS landscape battlefield development preview: the leather table, a hand of cards and the brass pass button, not a live match"
                width="1400"
                height="644"
                loading="lazy"
              />
            </div>
            <figcaption>
              Landscape table. iOS development preview, not a live-match
              capture.
            </figcaption>
          </figure>
        </section>
        <section id="download" className="download" data-sc-act="flow">
          <div className="download-heading" data-sc-in data-sc-stagger="60">
            <h2>Your turn.</h2>
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
                  {platform === "android" ? "Android alpha" : "iPhone & iPad beta"}
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
                className="download-action plaque plaque-ember"
                href={platform === "android" ? android : ios}
              >
                {platform === "android"
                  ? "Download Android"
                  : "Join TestFlight"}
                <ArrowUpRight size={26} />
              </a>
              {platform === "android" && (
                <div className="update-steps">
                  <strong>Get every update automatically</strong>
                  <ol>
                    <li>
                      <a className="plaque plaque-thin" href={obtainium.download}>
                        Download Obtainium ↓
                      </a>
                      <span>
                        A free, open-source app updater. Open the file and
                        allow the install.
                      </span>
                    </li>
                    <li>
                      <a className="plaque plaque-thin" href={obtainium.addApp}>
                        Add MagicMobile to Obtainium ↗
                      </a>
                      <span>
                        Opens Obtainium with MagicMobile filled in. Tap Add,
                        then Install. If nothing opens, choose Add App in
                        Obtainium and paste {obtainium.source}.
                      </span>
                    </li>
                    <li>
                      <span>
                        Done. Obtainium shows each new build; tap Update.
                        Your decks and settings stay.
                      </span>
                    </li>
                  </ol>
                </div>
              )}
              <small>
                {platform === "android"
                  ? "Android 8+ · ARM64. Hosted on GitHub. No account needed."
                  : `iPhone and iPad, iOS 17+. ${releases.ios.status} Install TestFlight, then accept the invitation.`}
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
                Easiest: install Obtainium, then add MagicMobile in it (the
                steps under the Android download). It installs the newest
                build and tells you when another one is out. Or open the APK
                link on your phone and open the downloaded file; if asked,
                allow your browser to install this app. You can turn that
                permission off after installation. If an install ever fails,
                check that the phone has about 1 GB free.
              </p>
            </details>
            <details>
              <summary>
                What to expect from the alpha
                <Plus size={20} />
              </summary>
              <p>
                Android build 16 lets you challenge a friend to a Quick Match, or
                to Ranked when you’re in the same tier, and friend ranked games
                count. The menu sits in a 3D tavern room that shifts as you tilt
                your phone, your profile picture is your favorite commander’s
                art, and the menu and Downloads match the tavern. It keeps
                Ranked, Quick Match and the Walnut Tavern table. Android is an
                early alpha; physical-phone acceptance is still pending.
              </p>
            </details>
            <details>
              <summary>
                What’s new on iPhone and iPad?
                <Plus size={20} />
              </summary>
              <p>
                Build 29 lets you challenge a friend from your friends list to a
                Quick Match, or to Ranked when you’re in the same tier, and
                friend ranked games count. The main menu sits in a real 3D
                tavern room that shifts as you tilt your phone, with flickering
                candles; your profile picture is your favorite commander’s art;
                rank badges turn more smoothly; and the menu and Downloads fit
                the tavern. It runs on iPhone and iPad. Apple has approved this
                build for Internal and External TestFlight.
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
              <img src="/tavern/mark-96.webp" alt="" width="44" height="44" />
              MagicMobile
              <ArrowUpRight size={24} />
            </a>
            <a href="https://github.com/ineedsomesleep5/MagicMobile">
              Follow the project
              <ArrowUpRight size={16} />
            </a>
            <a href="/privacy/">
              Privacy
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

import { useEffect, type ReactNode } from "react";
import { createRoot } from "react-dom/client";
import "@fontsource-variable/source-serif-4/opsz.css";
import "./style.css";
import { obtainium, releases } from "./releases";
import { startHall } from "./hall";
import { startBarDie } from "./barDie";

declare global {
  interface Window {
    ScrollCraft?: { mount: (root: HTMLElement) => unknown; instances: unknown[] };
  }
}

type Platform = "ios" | "android" | "web";
// The visitor's own screen comes first and in orange, in the bar and at the close. iPadOS reports a Mac with touch.
const ua = navigator.userAgent;
const mine: Platform =
  /iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1) ? "ios" : /Android/.test(ua) ? "android" : "web";
const order: Platform[] = [mine, ...(["ios", "android", "web"] as Platform[]).filter((p) => p !== mine)];
const screens: Record<Platform, { short: string; long: string; url: string }> = {
  ios: { short: "iPhone", long: "iPhone and iPad", url: releases.ios.url },
  android: { short: "Android", long: "Android", url: releases.android.url },
  web: { short: "Browser", long: "Browser", url: releases.web.url },
};

/** A screen's pill: your own goes straight to it; the others go to their row under Get MagicMobile. */
function ScreenPill({ p, long }: { p: Platform; long?: boolean }) {
  const own = p === mine;
  return (
    <a className={`pill ${own ? "pill--primary mine" : "pill--glass"}`} href={own ? screens[p].url : `#get-${p}`}>
      {long ? screens[p].long : screens[p].short}
    </a>
  );
}

type Exhibit = {
  id: string; ci: string; art: string; word: string; title: string; points: string[]; credit: string;
  card?: { src: string; alt: string }; artAlt: string;
};
const exhibits: Exhibit[] = [
  {
    id: "quick", ci: "BGRUW", art: "ur-dragon", word: "Play.", title: "Quick Match",
    points: ["One AI opponent, matched to your deck's bracket.", "The AI plays on your own device.", "100-card Commander."],
    credit: "The Ur-Dragon · art by Jaime Jones", artAlt: "The Ur-Dragon over a storm of dragons",
    card: { src: "ur-dragon", alt: "The Ur-Dragon card" },
  },
  {
    id: "ranked", ci: "BRW", art: "edgar-markov", word: "Climb.", title: "Ranked",
    points: ["Four divisions in every tier below Mythic.", "A new season every month.", "Below Mythic, a loss never drops your tier."],
    credit: "Edgar Markov · art by Volkan Baǵa", artAlt: "Edgar Markov on his throne",
  },
  {
    id: "studio", ci: "BUW", art: "yshtola", word: "Build.", title: "Deck Studio",
    points: ["Import from Archidekt, or paste any list.", "Choose the art for every card on your phone.", "Every deck gets a bracket from its list."],
    credit: "Y'shtola, Night's Blessed · art by Magali Villeneuve", artAlt: "Y'shtola casting under a night sky",
    card: { src: "yshtola", alt: "Y'shtola, Night's Blessed card" },
  },
  {
    id: "table", ci: "BGUW", art: "atraxa", word: "Host.", title: "Custom table",
    points: ["Up to four players.", "Against the AI, or at an online table with friends.", "Invite friends with a link."],
    credit: "Atraxa, Praetors' Voice · art by Victor Adame Minguez", artAlt: "Atraxa with wings spread",
    card: { src: "atraxa", alt: "Atraxa, Praetors' Voice card" },
  },
  {
    id: "friends", ci: "R", art: "krenko", word: "Challenge.", title: "Friends",
    points: ["Find players by name.", "Messages and challenges.", "See who is online and who is hosting."],
    credit: "Krenko, Mob Boss · art by Lie Setiawan", artAlt: "Krenko and his goblin mob",
    card: { src: "krenko", alt: "Krenko, Mob Boss card" },
  },
  {
    id: "hearth", ci: "GRU", art: "miirym", word: "Classic.", title: "Hearth",
    points: ["The classic tavern table.", "Hourglass, mana rail and table sockets.", "On iPhone and Android, switch to it in Options."],
    credit: "Miirym, Sentinel Wyrm · art by Kekai Kotaki", artAlt: "Miirym, a spectral dragon in a hoard",
    card: { src: "miirym", alt: "Miirym, Sentinel Wyrm card" },
  },
  {
    id: "learn", ci: "W", art: "giada", word: "Learn.", title: "How to play",
    points: ["A guided first game against the AI, on your phone.", "The turn, combat and the stack, step by step."],
    credit: "Giada, Font of Hope · art by Kai Carpenter", artAlt: "Giada, an angel in golden light",
    card: { src: "giada", alt: "Giada, Font of Hope card" },
  },
];
const TIERS = ["bronze", "silver", "gold", "platinum", "diamond", "mythic"];

function App() {
  useEffect(() => {
    if (window.ScrollCraft && !window.ScrollCraft.instances.length) window.ScrollCraft.mount(document.body);
    const stopHall = startHall();
    const stopDie = startBarDie();
    return () => { stopHall(); stopDie(); };
  }, []);

  const rows: Record<Platform, ReactNode> = {
    ios: (
      <article className="row" id="get-ios" key="ios">
        <div className="row__what">
          <strong>iPhone and iPad</strong>
          <span>TestFlight · Version {releases.ios.version} · Build {releases.ios.build} · iOS 17+</span>
        </div>
        <a className={`pill ${mine === "ios" ? "pill--primary" : "pill--glass"}`} href={releases.ios.url}>Join TestFlight</a>
      </article>
    ),
    android: (
      <article className="row" id="get-android" key="android">
        <div className="row__what">
          <strong>Android</strong>
          <span>
            APK · Version {releases.android.version} · Build {releases.android.build} · Android 8+, ARM64
          </span>
        </div>
        <a className={`pill ${mine === "android" ? "pill--primary" : "pill--glass"}`} href={releases.android.url}>Download APK</a>
        <details className="updates">
          <summary>Get every update with Obtainium</summary>
          <ol>
            <li>
              <a className="pill pill--glass" href={obtainium.download}>Download Obtainium</a>
              <br />A free, open-source app updater. Open the file and allow the install.
            </li>
            <li>
              <a className="pill pill--glass" href={obtainium.addApp}>Add MagicMobile to Obtainium</a>
              <br />
              Opens Obtainium with MagicMobile filled in. Tap Add, then Install. If nothing opens, choose Add App in
              Obtainium and paste {obtainium.source}.
            </li>
            <li>Done. Obtainium shows each new build; tap Update. Your decks and settings stay.</li>
          </ol>
        </details>
      </article>
    ),
    web: (
      <article className="row" id="get-web" key="web">
        <div className="row__what">
          <strong>Browser</strong>
          <span>Desktop · A current Chrome, Edge or Firefox · About 44 MB the first time</span>
        </div>
        <a className={`pill ${mine === "web" ? "pill--primary" : "pill--glass"}`} href={releases.web.url}>Play in the browser</a>
      </article>
    ),
  };

  return (
    <>
      <a className="skip" href="#main">Skip to content</a>
      <div className="sc-grain" aria-hidden="true" />
      <svg width="0" height="0" style={{ position: "absolute" }} aria-hidden="true">
        <defs>
          <linearGradient id="dieFill" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="#ffb24a" /><stop offset="0.5" stopColor="#f47a1c" /><stop offset="1" stopColor="#a8360a" />
          </linearGradient>
        </defs>
      </svg>

      <header className="bar">
        <div className="bar__in">
          <a className="brand" href="#main" aria-label="MagicMobile, back to the top">
            <img src="/site/mark.png" width="96" height="96" alt="" />
            <b>MagicMobile</b>
          </a>
          <div className="die-slot" aria-hidden="true" />
          <nav className="screens" aria-label="Get MagicMobile">
            {order.map((p) => <ScreenPill key={p} p={p} />)}
          </nav>
        </div>
      </header>
      <div className="die" aria-hidden="true">
        <canvas />
        <svg viewBox="0 0 100 100">
          <polygon className="face" points="50,2 92,26 92,74 50,98 8,74 8,26" />
          <polyline className="edge" points="50,22 78,68 22,68 50,22" />
          <polyline className="edge" points="8,26 50,22 92,26" /><line className="edge" x1="50" y1="2" x2="50" y2="22" />
          <polyline className="edge" points="92,26 78,68 92,74" /><line className="edge" x1="78" y1="68" x2="50" y2="98" />
          <polyline className="edge" points="8,26 22,68 8,74" /><line className="edge" x1="22" y1="68" x2="50" y2="98" />
          <text x="50" y="52">20</text>
        </svg>
      </div>

      <nav className="index away" aria-label="Ways to play">
        <ol className="index__list">
          {exhibits.map((ex, i) => (
            <li key={ex.id}>
              <button className="medal" data-go={i} aria-current={i === 0 ? "true" : "false"}>
                <img src={`/site/art/${ex.art}.webp`} alt="" /><span className="sr">{ex.title}</span>
              </button>
            </li>
          ))}
          <li>
            <button className="medal medal--play" data-go="play">
              <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 4.5v15l12.5-7.5z" /></svg><span className="sr">Get MagicMobile</span>
            </button>
          </li>
        </ol>
        <div className="index__pips" aria-hidden="true">
          {(["W", "U", "B", "R", "G"] as const).map((c) => (
            <i key={c} style={{ color: `var(--mana-${c.toLowerCase()})` }} data-c={c} />
          ))}
        </div>
      </nav>

      <main id="main">
        <section className="cut hero" data-sc-act="flow" data-sc-drift="#0c0d11">
          <div className="cut__bg"><img src="/site/art/ur-dragon.webp" width="1252" height="914" alt="The Ur-Dragon over a storm of dragons" /></div>
          <div className="cut__shade" />
          <img className="hero__card" src="/site/cards/ur-dragon.webp" width="520" height="727" alt="The Ur-Dragon card" />
          <div className="cut__copy">
            <h1 className="word">Commander.</h1>
            <p className="fact">100-card games against the AI or your friends. On iPhone, Android and in the browser.</p>
          </div>
        </section>

        <section className="cut cut--shot cut--draw" data-sc-act="flow" data-sc-drift="#120c09">
          <div className="cut__in">
            <figure className="hand" data-sc-reveal="up">
              <img src="/site/shots/draw.webp" width="1206" height="900" loading="lazy"
                alt="The Opening Hand screen: eight cards fanned, Mulligan to 6 cards?, and the Mulligan and Keep buttons" />
            </figure>
            <div className="cut__text" data-sc-in><h2 className="word">Draw.</h2><p className="fact">Mulligan or keep, the way Arena asks.</p></div>
          </div>
        </section>

        <section className="cut cut--shot cut--attack" data-sc-act="flow" data-sc-drift="#140d08">
          <div className="cut__in">
            <figure className="screen" data-sc-reveal="up">
              <picture>
                <source media="(max-width: 860px)" srcSet="/site/shots/attack-phone.webp" width="1080" height="839" />
                <img src="/site/shots/attack.webp" width="2200" height="886" loading="lazy"
                  alt="The Arena board in landscape: Serra Angels and Silvercoat Lions on the battlefield, the hand below, Next to combat" />
              </picture>
            </figure>
            <div className="cut__text" data-sc-in><h2 className="word">Attack.</h2><p className="fact">The Arena board, held either way.</p></div>
          </div>
        </section>

        <section className="hall" data-sc-act="pin" data-sc-span="9" aria-label="Ways to play">
          <div data-sc-stage className="hall__stage">
            <div className="room" aria-hidden="true">
              <div className="room__ambient" /><div className="room__glow" /><div className="room__floor" />
            </div>
            <div className="rail"><div className="rail__in">
              {exhibits.map((ex) => (
                <article key={ex.id} className={`ex${ex.id === "ranked" ? " ex--ranked" : ""}`} id={`ex-${ex.id}`}
                  data-ci={ex.ci} data-art={`/site/art/${ex.art}.webp`}>
                  <figure className="ex__plate"><img src={`/site/art/${ex.art}.webp`} width="1252" height="914" alt={ex.artAlt} loading="lazy" /></figure>
                  <p className="ex__word" aria-hidden="true">{ex.word}</p>
                  {ex.card && <img className="ex__card" src={`/site/cards/${ex.card.src}.webp`} width="520" height="727" alt={ex.card.alt} loading="lazy" />}
                  {ex.id === "ranked" && (
                    <div className="badge" aria-hidden="true">
                      {TIERS.map((t, i) => (
                        <img key={t} src={`/site/ranks/${t}.webp`} alt="" className={[i === 0 ? "on" : "", t === "mythic" ? "badge__mythic" : ""].join(" ").trim() || undefined} />
                      ))}
                    </div>
                  )}
                  <div className="ex__label glass">
                    <h3>{ex.title}</h3>
                    {ex.id === "ranked" && (
                      <ul className="tiers" aria-label="Tiers">
                        {TIERS.map((t, i) => <li key={t} className={i === 0 ? "on" : undefined}>{t[0].toUpperCase() + t.slice(1)}</li>)}
                      </ul>
                    )}
                    <ul>{ex.points.map((pt) => <li key={pt}>{pt}</li>)}</ul>
                    <p className="ex__credit">{ex.credit}</p>
                  </div>
                </article>
              ))}
            </div></div>
          </div>
        </section>

        {/* The peak: the stage holds while the bar's die leaves the bar and rolls above the caption. */}
        <section className="roll" data-sc-act="pin" data-sc-span="3.2" data-roll aria-label="Who goes first">
          <div data-sc-stage className="roll__stage">
            <h2 className="roll__cap" data-from="-1" data-to="0.36">Who goes first?</h2>
            <p className="roll__cap" data-from="0.36" data-to="0.7">Highest roll starts.</p>
            <p className="roll__cap roll__cap--won" data-from="0.7" data-to="2">You go first.</p>
          </div>
        </section>

        <section className="cut close" id="play" data-sc-act="flow" data-sc-drift="#0c0d11">
          <div className="cut__bg"><img src="/site/art/giada.webp" width="1252" height="914" alt="Giada, an angel in golden light" loading="lazy" /></div>
          <div className="cut__copy">
            <h2 className="word">Your turn.</h2>
            <div className="go">{order.map((p) => <ScreenPill key={p} p={p} long />)}</div>
          </div>
        </section>

        <section className="get" id="download" data-sc-act="flow">
          <div className="get__in">
            <h2>Get MagicMobile</h2>
            <div className="rows glass">{order.map((p) => rows[p])}</div>

            <div className="faq">
              <details>
                <summary>Installing on Android</summary>
                <p>
                  Easiest: install Obtainium, then add MagicMobile in it (the steps under Android above). It installs the
                  newest build and tells you when another one is out. Or open the APK link on your phone and open the
                  downloaded file; if asked, allow your browser to install this app. You can turn that permission off after
                  installation. If an install ever fails, check that the phone has about 1 GB free.
                </p>
              </details>
              <details>
                <summary>What to expect from the alpha</summary>
                <p>
                  Android build 44 has voice chat at online tables: tap the mic under the gear to talk with the other players,
                  on Android, iPhone or the web, with Push to Talk in the audio settings. Tables keep going when a player leaves, and the leaderboard and profile show
                  more of your games. AI opponents match your rank, and your decks stay in
                  sync across every phone signed in to the same profile. Arena stays the default board, with Hearth in Options. It keeps the lighter engine from
                  build 31. Android is an early alpha; physical-phone acceptance is still pending.
                </p>
              </details>
              <details>
                <summary>What’s new on iPhone and iPad?</summary>
                <p>
                  Build 59 keeps your decks in sync: sign in and the decks you build show up on every phone signed in to the
                  same profile. Arena stays the default board. It runs on iPhone and iPad. Apple has approved this build for
                  Internal and External TestFlight.
                </p>
              </details>
              <details>
                <summary>Playing in the browser</summary>
                <p>
                  MagicMobile also plays in a desktop browser: a current Chrome, Edge or Firefox. The first visit downloads the
                  game engine, about 44 MB, and keeps it for next time. Signed in with the same Google account, your profile and
                  decks are the same as on your phone.
                </p>
              </details>
            </div>

            <div className="support glass" id="support">
              <h3>Help cover server costs.</h3>
              <p>
                MagicMobile is free, with no ads and nothing to buy in the app. Online tables, friends and ranked games run on
                servers that cost money every month. If you enjoy the game, a small tip helps keep them running.
              </p>
              {/* The support page holds the one donation link; the apps open it too. */}
              <a className="pill pill--glass" href="/support/">Support MagicMobile</a>
              <small>Tips are optional and unlock nothing in the game.</small>
            </div>

            <footer className="foot">
              <nav aria-label="More">
                <a className="brand" href="#main"><img src="/site/mark.png" width="96" height="96" alt="" /><b>MagicMobile</b></a>
                <a href="/support/">Support</a>
                <a href="/privacy/">Privacy</a>
              </nav>
              <p>
                MagicMobile is unofficial Fan Content permitted under the Fan Content Policy. Not approved/endorsed by
                Wizards. Portions of the materials used are property of Wizards of the Coast. ©Wizards of the Coast LLC.
                Card images and art from <a href="https://scryfall.com">Scryfall</a>; each artist is credited beside their art.
              </p>
            </footer>
          </div>
        </section>
      </main>
    </>
  );
}
createRoot(document.getElementById("root")!).render(<App />);

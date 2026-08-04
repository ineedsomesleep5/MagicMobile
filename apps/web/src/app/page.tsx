import Link from "next/link";

export default function HomePage() {
  return (
    <div className="home-screen">
      <section className="home-hero">
        <div className="home-hero-copy">
          <p className="home-eyebrow">XMage rules · Commander first</p>
          <h1>Your next Commander match, wherever you are.</h1>
          <p className="home-lead">
            Build a deck, challenge the AI, and play a complete rules-accurate game with an interface designed for phone and desktop.
          </p>
          <div className="home-actions">
            <Link className="home-button home-button-primary" href="/play">Play Commander</Link>
            <Link className="home-button" href="/decks">Open deck library</Link>
          </div>
          <div className="home-trust" aria-label="Game capabilities">
            <span>100-card decks</span>
            <span>40 life</span>
            <span>Commander tax</span>
            <span>XMage stack</span>
          </div>
        </div>
        <div className="home-table" aria-label="Commander battlefield preview">
          <div className="home-opponent">
            <span className="home-avatar">AI</span>
            <span><strong>Arcane Rival</strong><small>40 life · 7 cards</small></span>
          </div>
          <div className="home-card-row home-card-row-opponent" aria-hidden="true">
            <i /><i /><i />
          </div>
          <div className="home-turn-rune"><span>YOUR TURN</span><strong>MAIN</strong></div>
          <div className="home-card-row" aria-hidden="true">
            <i /><i /><i /><i />
          </div>
          <div className="home-player">
            <span className="home-avatar home-avatar-player">YOU</span>
            <span><strong>Ready for battle</strong><small>Choose a deck to begin</small></span>
          </div>
        </div>
      </section>

      <section className="home-choices" aria-label="Commander actions">
        <Link className="home-choice home-choice-play" href="/play">
          <span className="home-choice-number">01</span>
          <span><small>Commander vs AI</small><strong>Enter the battlefield</strong></span>
          <span className="home-choice-arrow" aria-hidden="true">→</span>
        </Link>
        <Link className="home-choice" href="/decks">
          <span className="home-choice-number">02</span>
          <span><small>Cloud deck library</small><strong>Build, import, and refine</strong></span>
          <span className="home-choice-arrow" aria-hidden="true">→</span>
        </Link>
      </section>
    </div>
  );
}

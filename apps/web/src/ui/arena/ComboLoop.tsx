/**
 * The combo loop shortcut on the Arena board (ComboLoopOverlay): the offer after three identical rounds (what a round
 * does, a count picker, until I can't, until they lose), a slim glass bar while it repeats (its rounds, progress and
 * Stop), a curtain while a winning loop finishes, and the closing line for 9 s.
 */
import { useEffect, useState } from "react";
import { ComboLoop, ComboRepeat } from "../../core/comboLoop";
import type { ComboRun, GuestSession } from "../../table/guestSession";
import { gameAudio } from "../audio";

const LOOP = <svg viewBox="0 0 20 20" aria-hidden="true"><path d="M4.5 7.5A6 6 0 0 1 15.4 6l1.6-1.6V9h-4.6l1.7-1.7A4.2 4.2 0 0 0 6.3 8zM15.5 12.5A6 6 0 0 1 4.6 14L3 15.6V11h4.6l-1.7 1.7a4.2 4.2 0 0 0 7.8-.7z" /></svg>;

function title(run: ComboRun) {
  switch (run.mode.kind) {
    case "times": return `Repeating · ${run.done} of ${run.mode.count}`;
    case "untilCant": return `Repeating until you can't · ${run.done}`;
    case "untilWin": return `Repeating until they lose · ${run.done}`;
  }
}

export function ComboLoopOverlay({ session }: { session: GuestSession }) {
  const { comboOffer: offer, comboRun: run, comboFinishing: finishing, comboResult: result, comboWinForecast: forecast } = session.state;
  const [count, setCount] = useState<number>(ComboLoop.pickerDefault);
  const [shownResult, setShownResult] = useState<string>();
  useEffect(() => {
    if (!result) return;
    setShownResult(result);
    const timer = window.setTimeout(() => setShownResult((r) => (r === result ? undefined : r)), 9000);
    return () => window.clearTimeout(timer);
  }, [result]);
  const start = (mode: ComboRepeat) => { gameAudio.play("menu-play"); session.startComboLoop(mode); };
  const bump = (by: number) => { gameAudio.play("ui-tick"); setCount((c) => Math.max(1, Math.min(ComboLoop.maxRepeats, c + by))); };
  const stop = () => { gameAudio.play("ui-back"); session.stopComboLoop(); };

  if (run && finishing !== undefined) {
    // A loop that wins plays out behind a curtain, as fast as the rules allow, and the game ends.
    const rounds = Math.max(finishing, 1);
    return (
      <div className="acombo curtain" onClick={(e) => e.stopPropagation()}>
        <div className="glass box" role="status">
          <i className="crown" aria-hidden="true">♛</i>
          <b>Finishing the loop</b>
          <span>Round {Math.min(run.done + 1, rounds)} of {rounds}</span>
          <progress value={Math.min(run.done, rounds)} max={rounds} />
          <button type="button" className="aplaque secondary inline" onClick={stop}>Stop</button>
        </div>
      </div>
    );
  }
  if (run) {
    // A scrim keeps stray clicks off the board; the bar sits under the top edge with the board in view.
    return (
      <div className="acombo running" onClick={(e) => e.stopPropagation()}>
        <div className="glass bar" role="status">
          <i className="spin" style={{ transform: `rotate(${run.done * 90}deg)` }}>{LOOP}</i>
          <div>
            <b>{title(run)}</b>
            {run.lines.length > 0 && <small>{run.lines[run.lines.length - 1]}</small>}
            {run.mode.kind === "times" && <progress value={run.done} max={Math.max(run.mode.count, 1)} />}
          </div>
          <button type="button" className="aplaque secondary" onClick={stop}>Stop</button>
        </div>
      </div>
    );
  }
  if (offer) {
    const canFinish = forecast?.canFinish === true;
    return (
      <div className="acombo offer" onClick={(e) => e.stopPropagation()}>
        <div className="glass card" role="dialog" aria-label="Loop spotted">
          <header>
            <i>{LOOP}</i><b>Loop spotted</b>
            <button type="button" className="close" aria-label="Not now" onClick={() => { gameAudio.play("ui-back"); session.declineComboLoop(); }}>✕</button>
          </header>
          <div className="each">
            <small>EACH ROUND</small>
            {ComboLoop.preview(offer).map((line, i) => <span key={i}>› {line}</span>)}
          </div>
          <p>Every step is still checked by the rules. It waits for your own triggers, keeps the same target until it's gone, and stops if an opponent responds.</p>
          <div className="picker">
            <button type="button" className="step" aria-label="One fewer" disabled={count <= 1} onClick={() => bump(-1)}>−</button>
            <b aria-label={`${count} rounds`}>{count}</b>
            <button type="button" className="step" aria-label="One more" disabled={count >= ComboLoop.maxRepeats} onClick={() => bump(1)}>+</button>
            <span />
            <button type="button" className="aplaque secondary" onClick={() => bump(5)}>+5</button>
            <button type="button" className="aplaque secondary" onClick={() => bump(10)}>+10</button>
          </div>
          <div className="go">
            <button type="button" className="aplaque primary" onClick={() => start(ComboRepeat.times(count))}>Repeat {count}×</button>
            <button type="button" className="aplaque secondary" onClick={() => start(ComboRepeat.untilCant)}>Until I can't</button>
            <button type="button" className={`aplaque ${canFinish ? "primary" : "secondary"}`} disabled={!canFinish} onClick={() => start(ComboRepeat.untilWin)}>
              {canFinish ? `Until they lose · ${forecast!.rounds}` : "Until they lose"}</button>
          </div>
          {!canFinish && <p className="reason">{forecast === undefined
            ? "Until they lose needs a round that takes the same life (or poison) from every opponent."
            : "Until they lose waits while an opponent holds cards and an untapped land."}</p>}
        </div>
      </div>
    );
  }
  if (shownResult) {
    return (
      <div className="acombo result" onClick={(e) => e.stopPropagation()}>
        <div className="glass line" role="status">
          <i aria-hidden="true">✓</i><span>{shownResult}</span>
          <button type="button" className="close" aria-label="Dismiss" onClick={() => setShownResult(undefined)}>✕</button>
        </div>
      </div>
    );
  }
  return null;
}

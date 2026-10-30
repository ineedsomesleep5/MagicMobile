/**
 * Awards on a profile (iOS Ranked/AwardViews.swift; Caleb, 2026-10-30): medals that live on the server, art included, so
 * a new one needs no deploy (docs/SERVER_CONTROLS.md). Art, or a star medal in the award's tint when it has none or it
 * can't load. Styles in profile.css.
 */
import { useEffect, useState } from "react";
import { Award } from "../../core/account";
import { gameAudio } from "../audio";
import { Btn, Caps } from "./kit";

const metal = "mawardmetal";

/** An award's art, or a star medal in its tint. */
export function AwardMedal({ award, size = 60 }: { award: Award; size?: number }) {
  const [failed, setFailed] = useState(false);
  useEffect(() => setFailed(false), [award.imageUrl]);
  const art = award.imageUrl && !failed;
  return (
    <span className={`mawardmedal rarity${award.rarity}`} aria-hidden="true" style={{ width: size, height: size, ["--tint" as string]: award.tint }}>
      {art ? <img src={award.imageUrl} alt="" onError={() => setFailed(true)} />
        : <svg viewBox="0 0 24 24"><path className={metal} d="M12 3.2l2.7 5.6 6.1.8-4.5 4.2 1.2 6.1-5.5-3-5.5 3 1.2-6.1-4.5-4.2 6.1-.8z" /></svg>}
    </span>
  );
}

/** One award, large: over the menu when it is new, or opened from a shelf. Only Continue closes it. */
export function AwardCeremony({ award, isNew = false, onClose }: { award: Award; isNew?: boolean; onClose: () => void }) {
  useEffect(() => { if (isNew) gameAudio.play("victory"); }, [isNew]);
  const caption = Award.caption(award);
  return (
    <div className="mawardceremony" role="dialog" aria-modal="true" aria-label={award.name} data-id="award.ceremony">
      {isNew && <Caps text="New award" />}
      <AwardMedal award={award} size={170} />
      <h2 style={{ ["--tint" as string]: award.tint }}>{award.name}</h2>
      {award.detail && <p>{award.detail}</p>}
      {caption && <small>{caption}</small>}
      <Btn onClick={onClose} id="award.ceremony.continue">Continue</Btn>
    </div>
  );
}

/** A row of awards, best first. Tapping one opens it. */
export function AwardShelf({ awards, size = 60 }: { awards: readonly Award[]; size?: number }) {
  const [open, setOpen] = useState<Award>();
  return (
    <div className="mawardshelf" data-id="awards">
      {awards.map((award) => (
        <button key={award.id} type="button" className="maward" style={{ width: size * 1.55 }} title={award.detail} data-id={`award.${award.id}`}
          onClick={() => { gameAudio.play("ui-open"); setOpen(award); }}>
          <AwardMedal award={award} size={size} />
          <span>{award.name}</span>
        </button>
      ))}
      {open && <AwardCeremony award={open} onClose={() => setOpen(undefined)} />}
    </div>
  );
}

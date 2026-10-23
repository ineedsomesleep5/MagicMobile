/**
 * A friend's challenge over the menus (iOS ChallengeInviteBanner): their rank emblem (ranked) or crossed flags, who
 * challenges you and what it counts for, Decline and Accept. It pulses gently and plays the open sound when it comes in.
 */
import { useEffect } from "react";
import type { FriendChallenge } from "../../core/account";
import { FriendChallengeRules } from "../../core/matchmaking";
import { RankPosition } from "../../core/rankLadder";
import { gameAudio } from "../audio";
import { Btn } from "./kit";
import { RankEmblem } from "./TopBar";

export function ChallengeBanner({ challenge, accept, decline }: { challenge: FriendChallenge; accept: () => void; decline: () => void }) {
  useEffect(() => { gameAudio.play("ui-open"); }, [challenge.id]);
  const ranked = FriendChallengeRules.isRanked(challenge);
  return (
    <div className="mchallenge glass" role="alert" data-id="challenge.invite">
      <span className="mchallengemark">
        {ranked && challenge.challengerStep !== undefined ? <RankEmblem tier={RankPosition.atStep(challenge.challengerStep).tier} size={44} />
          : <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 2h2v20H4zm3 1h8l-1.5 3L15 9H7zm6 6h7l-1.5 3 1.5 3h-7z" /></svg>}
      </span>
      <span className="grow">
        <b>{challenge.challenger ?? "A friend"} challenges you</b>
        <small>{ranked ? "Ranked · counts for both" : "Quick Match · friendly"}</small>
      </span>
      <Btn kind="secondary" compact id="challenge.decline" onClick={decline}>Decline</Btn>
      <Btn kind="primary" compact id="challenge.accept" onClick={accept}>Accept</Btn>
    </div>
  );
}

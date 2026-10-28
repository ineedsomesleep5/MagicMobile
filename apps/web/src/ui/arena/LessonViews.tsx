/**
 * The lessons on the web board (iOS LessonViews.swift): Maren's note at the top of the table, with Got it on a note and
 * Next Lesson and Done once the lesson is over; a wrong move shakes the card and says so.
 */
import { useEffect, useState } from "react";
import { forDesktop, LessonText } from "../../core/lessons";
import type { LessonTable } from "../../table/lessonTable";

export function LessonCoachCard({ table }: { table: LessonTable }) {
  const { coach, complete, waitsForGotIt, nudges } = table.run;
  const [nudged, setNudged] = useState(false);
  const [shake, setShake] = useState(0);
  useEffect(() => { if (nudges > 0) { setNudged(true); setShake((n) => n + 1); } }, [nudges]);
  useEffect(() => { setNudged(false); }, [coach]);
  const text = forDesktop(nudged ? LessonText.nudge : complete && !coach ? LessonText.allComplete : coach?.text ?? "");
  return (
    <div key={shake} className={`alessoncoach ${shake > 0 ? "shake" : ""}`} data-id="lesson.coach" role="status">
      <header>
        <span className="tag">{LessonText.coach.toUpperCase()}</span>
        <h3>{complete ? LessonText.complete : coach?.title ?? table.lesson.title}</h3>
      </header>
      <p data-id="lesson.coach.text">{text}</p>
      {complete ? (
        <footer>
          <button type="button" className="aplaque secondary inline" data-id="lesson.done" onClick={() => table.leave()}>{LessonText.done}</button>
          <button type="button" className="aplaque primary inline" data-id="lesson.next" onClick={() => table.rematch()}>{table.nextTitle}</button>
        </footer>
      ) : waitsForGotIt && (
        <footer>
          <span />
          <button type="button" className="aplaque primary inline" data-id="lesson.gotIt" onClick={() => table.gotIt()}>{LessonText.gotIt}</button>
        </footer>
      )}
    </div>
  );
}

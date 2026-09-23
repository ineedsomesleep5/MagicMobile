#!/usr/bin/env python3
"""Summarize saved `gh run view --json createdAt,updatedAt,jobs` evidence offline.

Does not call GitHub, mutate release state, or estimate unavailable model usage.
Runner time and elapsed time are different metrics because jobs overlap.
"""
import argparse
from datetime import datetime
import json
from pathlib import Path


def timestamp(value):
    if not isinstance(value, str):
        raise ValueError('Timestamp must be an ISO 8601 string')
    parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
    if parsed.tzinfo is None:
        raise ValueError('Timestamp must have a timezone')
    return parsed.timestamp()


def optional_timestamp(value):
    # GitHub can omit timing or use its zero-date for skipped work.
    if value in (None, '', '0001-01-01T00:00:00Z', '0001-01-01T00:00:00+00:00'):
        return None
    return timestamp(value)


def duration(item, run_start, run_end, label):
    a = optional_timestamp(item.get('startedAt'))
    b = optional_timestamp(item.get('completedAt'))
    for point in (a, b):
        if point is not None and not run_start <= point <= run_end:
            raise ValueError(f'{label} timestamp outside run bounds')
    if a is None or b is None:
        return None, None
    if b < a:
        raise ValueError(f'{label} end precedes start')
    return b - a, (a, b)


def summarize(run):
    start, end = timestamp(run['createdAt']), timestamp(run['updatedAt'])
    if end < start:
        raise ValueError('Run end precedes start')
    jobs = []
    intervals = []
    timed_steps = []
    untimed_steps = 0
    for job in run['jobs']:
        if job.get('status') != 'completed':
            raise ValueError('Only completed job evidence can be summarized')
        skipped = job['conclusion'] == 'skipped'
        seconds, interval = (None, None) if skipped else duration(job, start, end, 'Job')
        if interval is not None:
            intervals.append(interval)
        jobs.append({'name': job['name'], 'seconds': seconds,
                     'conclusion': job['conclusion']})
        for step in job.get('steps', []):
            if skipped or step.get('conclusion') == 'skipped':
                continue
            if step.get('status') != 'completed':
                continue
            step_seconds, _ = duration(step, start, end, 'Step')
            if step_seconds is None:
                untimed_steps += 1
            else:
                timed_steps.append({'job': job['name'], 'name': step['name'],
                                    'seconds': step_seconds,
                                    'conclusion': step['conclusion']})
    merged = []
    for a, b in sorted(intervals):
        if merged and a <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], b)
        else:
            merged.append([a, b])
    return {'elapsedSeconds': end - start,
            'summedJobSeconds': sum(j['seconds'] for j in jobs if j['seconds'] is not None),
            'occupiedWallSeconds': sum(b - a for a, b in merged),
            'nonSuccessJobs': sum(j['conclusion'] not in ('success', 'skipped') for j in jobs),
            'skippedJobs': sum(j['conclusion'] == 'skipped' for j in jobs),
            'untimedJobs': sum(j['seconds'] is None and j['conclusion'] != 'skipped' for j in jobs),
            'untimedSteps': untimed_steps,
            'slowSteps': sorted(timed_steps, key=lambda s: s['seconds'], reverse=True)[:10],
            'jobs': jobs,
            'scope': 'Saved CI timing evidence; duration totals omit untimed work, '
                     'waiting is included, not active agent time, wall-time savings or model cost'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('evidence', type=Path)
    args = parser.parse_args()
    print(json.dumps(summarize(json.loads(args.evidence.read_text())), indent=2))


if __name__ == '__main__':
    main()

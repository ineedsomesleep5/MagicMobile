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
    parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
    if parsed.tzinfo is None:
        raise ValueError('Timestamp must have a timezone')
    return parsed.timestamp()


def summarize(run):
    start, end = timestamp(run['createdAt']), timestamp(run['updatedAt'])
    if end < start:
        raise ValueError('Run end precedes start')
    jobs = []
    intervals = []
    for job in run['jobs']:
        if job.get('status') != 'completed':
            raise ValueError('Only completed job evidence can be summarized')
        a, b = timestamp(job['startedAt']), timestamp(job['completedAt'])
        if b < a or a < start or b > end:
            raise ValueError('Job timestamps outside run bounds')
        intervals.append((a, b))
        jobs.append({'name': job['name'], 'seconds': b - a,
                     'conclusion': job['conclusion']})
    merged = []
    for a, b in sorted(intervals):
        if merged and a <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], b)
        else:
            merged.append([a, b])
    return {'elapsedSeconds': end - start,
            'summedJobSeconds': sum(j['seconds'] for j in jobs),
            'occupiedWallSeconds': sum(b - a for a, b in merged),
            'nonSuccessJobs': sum(j['conclusion'] != 'success' for j in jobs),
            'jobs': jobs,
            'scope': 'Saved CI timing evidence; waiting is included, not active agent time or model cost'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('evidence', type=Path)
    args = parser.parse_args()
    print(json.dumps(summarize(json.loads(args.evidence.read_text())), indent=2))


if __name__ == '__main__':
    main()

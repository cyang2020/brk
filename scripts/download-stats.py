#!/usr/bin/env python3
"""Records how often each release zip was downloaded, and writes a summary (docs/release.md, "Download counts").

    GH_TOKEN=... GH_REPO=cyang2020/brk scripts/download-stats.py <stats folder> <event>

GitHub counts the downloads of each release file, but the count belongs to the file: the release workflow replaces
the zips of "Latest build" on every push to main, and the replaced files take their counts with them. So the counts
are read every day and once more right before a publish replaces anything, and appended to `downloads.tsv` in the
stats folder (a checkout of the `stats` branch). A file's count only grows while it exists, so the highest count
recorded for it is what it had; the total is the sum of those over every file ever recorded.

Writes in the stats folder:
- downloads.tsv: time, event, release, asset id, file name, downloads (one row per file per reading);
- repo.tsv: time, event, stars, forks;
- README.md: totals, Apple silicon and Intel, and new downloads per day.
"""
import csv
import datetime
import json
import os
import sys
import urllib.request

API = os.environ.get('GITHUB_API_URL', 'https://api.github.com')
DOWNLOADS = ['time', 'event', 'release', 'asset_id', 'asset', 'downloads']
REPO = ['time', 'event', 'stars', 'forks']
DAYS_SHOWN = 30


def get(path):
    request = urllib.request.Request(API + path, headers={
        'Accept': 'application/vnd.github+json',
        'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'brk-download-stats',
    })
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def releases(repo):
    """Every published release (drafts are CI tests) with its files."""
    found, page = [], 1
    while True:
        batch = get(f'/repos/{repo}/releases?per_page=100&page={page}')
        found += [r for r in batch if not r.get('draft')]
        if len(batch) < 100:
            return found
        page += 1


def append(path, header, rows):
    new = not os.path.exists(path)
    with open(path, 'a', newline='') as f:
        writer = csv.writer(f, delimiter='\t', lineterminator='\n')
        if new:
            writer.writerow(header)
        writer.writerows(rows)


def read(path):
    if not os.path.exists(path):
        return []
    with open(path, newline='') as f:
        return list(csv.DictReader(f, delimiter='\t'))


def arch(name):
    if 'arm64' in name:
        return 'Apple silicon'
    if 'x86_64' in name:
        return 'Intel'
    return 'Other'


def summary(rows, repo_rows, repo):
    """README.md for the stats branch, from every reading so far."""
    best = {}                       # asset id -> (highest count, file name)
    totals_by_day = {}              # UTC day -> total over all files at the day's last reading
    for row in sorted(rows, key=lambda r: r['time']):
        count = int(row['downloads'])
        if count > best.get(row['asset_id'], (-1, ''))[0]:
            best[row['asset_id']] = (count, row['asset'])
        totals_by_day[row['time'][:10]] = sum(c for c, _ in best.values())
    total = sum(c for c, _ in best.values())
    by_arch = {}
    for count, name in best.values():
        by_arch[arch(name)] = by_arch.get(arch(name), 0) + count
    first = min((r['time'][:10] for r in rows), default='-')
    lines = [
        '# Brk download counts',
        '',
        f'Downloads of the release zips of [{repo}](https://github.com/{repo}/releases), recorded every day and before '
        f'every publish by `.github/workflows/download-stats.yml`. Counting began on {first}; downloads of files that '
        'were replaced before then are not included.',
        '',
        '| | Downloads |',
        '| --- | ---: |',
        f'| **All** | **{total}** |',
    ]
    lines += [f'| {name} | {by_arch[name]} |' for name in ('Apple silicon', 'Intel', 'Other') if name in by_arch]
    if repo_rows:
        last = repo_rows[-1]
        lines += ['', f'Stars: {last["stars"]} · Forks: {last["forks"]} (at {last["time"]})']
    days = sorted(totals_by_day)
    lines += ['', f'## New downloads per day (UTC, last {DAYS_SHOWN} days)', '', '| Day | New | Total |',
              '| --- | ---: | ---: |']
    for index in range(len(days) - 1, max(-1, len(days) - 1 - DAYS_SHOWN), -1):
        day = days[index]
        before = totals_by_day[days[index - 1]] if index > 0 else 0
        lines.append(f'| {day} | {totals_by_day[day] - before} | {totals_by_day[day]} |')
    lines += ['', 'The full readings are in `downloads.tsv` (one row per file per reading) and `repo.tsv`.', '']
    return '\n'.join(lines)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    folder, event = sys.argv[1], sys.argv[2]
    repo = os.environ['GH_REPO']
    now = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    rows = [[now, event, r['tag_name'], a['id'], a['name'], a['download_count']]
            for r in releases(repo) for a in r.get('assets', [])]
    info = get(f'/repos/{repo}')
    os.makedirs(folder, exist_ok=True)
    append(os.path.join(folder, 'downloads.tsv'), DOWNLOADS, rows)
    append(os.path.join(folder, 'repo.tsv'), REPO, [[now, event, info['stargazers_count'], info['forks_count']]])
    text = summary(read(os.path.join(folder, 'downloads.tsv')), read(os.path.join(folder, 'repo.tsv')), repo)
    with open(os.path.join(folder, 'README.md'), 'w') as f:
        f.write(text)
    print(f'{len(rows)} files read at {now} ({event})')
    print(text)


if __name__ == '__main__':
    main()

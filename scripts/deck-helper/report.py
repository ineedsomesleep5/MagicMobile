#!/usr/bin/env python3
"""Write a self-contained HTML deck report from the JSON that dh-report-style runs of the engine produce.

  report.py <report.json> <out.html>

Card images load from cards.scryfall.io by Scryfall id, so the file needs an internet connection but no server.
"""
import html, json, sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
out = Path(sys.argv[2])
e = lambda s: html.escape(str(s))
img = lambda c, size='small': f"https://cards.scryfall.io/{size}/front/{c['id'][0]}/{c['id'][1]}/{c['id']}.jpg" if c and c.get('id') else ''
ROLE = {'ramp': 'Ramp', 'draw': 'Draw', 'removal': 'Removal', 'counter': 'Counter', 'wipe': 'Wipe', 'tutor': 'Tutor', 'protection': 'Protection', 'recursion': 'Recursion', 'finisher': 'Finisher', 'engine': 'Engine'}
BAND = {'Exhibition': '1–2', 'Core': '3–4', 'Upgraded': '5–6', 'Optimized': '7–8', 'cEDH': '9–10'}


def tile(c, caption='', pill='', badge='', cls=''):
    if not c:
        return ''
    return (f'<figure class="card {cls}"><div class="pic"><img loading="lazy" src="{img(c)}" alt="{e(c["name"])}">'
            f'{f"<span class=badge>{e(badge)}</span>" if badge else ""}{f"<span class=pill>{e(pill)}</span>" if pill else ""}</div>'
            f'<figcaption><b>{e(c["name"].split(" // ")[0])}</b>{f"<span>{caption}</span>" if caption else ""}</figcaption></figure>')


b, a = data['before'], data['after']
cmd = data['commander']
who = cmd['name'].split(',')[0]
delta = lambda k, d=1: (f'+{a[k]-b[k]:.{d}f}' if a[k] > b[k] else f'{a[k]-b[k]:.{d}f}' if a[k] < b[k] else 'same')
nums = [
    ('Power (1–10)', f"{b['table']:.1f}", f"{a['table']:.1f}", f"{b['band']} → {a['band']} range", delta('table')),
    ('App AI match', f"{b['ai']:.1f}", f"{a['ai']:.1f}", f"{b['tier']} → {a['tier']} tier decks", delta('ai')),
    ('Bracket', str(b['bracket']), str(a['bracket']), 'no Game Changers either way' if not a['gcs'] else ', '.join(a['gcs']), ''),
    ('Ramp', b['ramp'], a['ramp'], 'template wants 10–12', delta('ramp', 0)),
    ('Card draw', b['draw'], a['draw'], 'wants 10–12', delta('draw', 0)),
    ('Removal', b['targeted'], a['targeted'], 'wants 11–14 with one opponent', delta('targeted', 0)),
    ('Lands entering tapped', f"{b['tapped']:g}", f"{a['tapped']:g}", f"of {a['lands']} lands", delta('tapped')),
    (f'Typical {e(who)}', f"{b['fit']['avgInc']}%", f"{a['fit']['avgInc']}%", f"avg. EDHREC inclusion across {data['edh']['decks']:,} decks", ''),
    ('Average mana value', f"{b['mv']:.2f}", f"{a['mv']:.2f}", f"{a['eff']:.2f} effective", ''),
]
swaps_html = ''
for s in data['swaps']:
    why = '; '.join(s['cutReasons'][:2]) or ('enters tapped' if 'land' in (s['out']['type'] or '').lower() else '')
    gain = ', '.join(ROLE[t] for t in s['inTags'] if t in ROLE) or ('untapped land' if 'Land' in (s['in']['type'] or '') else 'plan card')
    edh = f" · in {s['inEdh']['inc']}% of {e(who)} decks" if s.get('inEdh') else ''
    swaps_html += (f'<div class="swap">{tile(s["out"], caption=e(why), badge="OUT", cls="out")}<div class="arrow">→</div>'
                   f'{tile(s["in"], caption=e(gain) + edh + (f" · ${s["in"]["usd"]}" if s["in"].get("usd") else ""), badge="IN", cls="in")}</div>')
cuts_html = ''.join(tile(c['card'], caption=e('; '.join(c['reasons'][:2])) + (f'<br><i>{e(c["edh"])}</i>' if c.get('edh') else ''), badge=f"{c['score']:.1f}", pill=f"{c['card']['cmc']:g} mv") for c in data['cuts'])
groups = [('Commander', lambda r: r['commander']), ('Lands', lambda r: r['land'] and not r['commander']), ('Ramp', lambda r: 'ramp' in r['tags']), ('Card draw', lambda r: 'draw' in r['tags']),
          ('Removal and wipes', lambda r: any(t in r['tags'] for t in ('removal', 'counter', 'wipe'))), ('Everything else (the plan)', lambda r: True)]
seen, groups_html = set(), ''
swapped_out = {s['out']['name'] for s in data['swaps']}
for title, test in groups:
    rows = [r for r in data['rows'] if r['card']['name'] not in seen and not r['land'] or title in ('Lands', 'Commander')]
    rows = [r for r in data['rows'] if r['card']['name'] not in seen and test(r)]
    if title not in ('Commander',):
        rows = [r for r in rows if not r['commander']]
    for r in rows:
        seen.add(r['card']['name'])
    if not rows:
        continue
    tiles = ''.join(tile(r['card'], caption=' · '.join([ROLE[t] for t in r['tags'] if t in ROLE] + (['tapped'] if r['tapped'] >= 1 else ['sometimes tapped'] if r['tapped'] else []) + ([f"×{r['qty']}"] if r['qty'] > 1 else [])),
                         pill=(f"{r['edh']['inc']}%" if r.get('edh') else ''), badge='OUT' if r['card']['name'] in swapped_out else '', cls='out' if r['card']['name'] in swapped_out else '') for r in rows)
    groups_html += f'<h3>{title} <small>{sum(r["qty"] for r in rows)}</small></h3><div class="grid small">{tiles}</div>'
plan = ', '.join(f"{k} ({v})" for k, v in data['plan']['share'].items() if v)
curve_rows = ''.join(f'<div class="col"><div class="stick" style="height:{round(100*n/max(1,max(b["curve"])))}%"></div><div>{n}</div><div>{"7+" if i == 7 else i}</div></div>' for i, n in enumerate(b['curve']))
page = f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{e(cmd['name'])} · Deck Helper report</title>
<style>
:root{{color-scheme:dark;--bg:#120e0b;--glass:rgba(24,19,16,.8);--hair:rgba(250,214,134,.32);--ink:#f3ebdc;--ink2:rgba(243,235,220,.72);--gold:#fad686;--ember:#f47a1c;--bad:#ff5a2e;--good:#7fe0a6;--cyan:#7ff0ff}}
*{{box-sizing:border-box}}body{{margin:0;background:radial-gradient(1200px 600px at 50% -10%,#1f1813,var(--bg) 70%) fixed,var(--bg);color:var(--ink);font:15px/1.45 "Source Sans 3","Helvetica Neue",Arial,sans-serif;padding:20px 16px 60px}}
h1,h2,h3{{font-family:"Cormorant Garamond","Palatino Linotype",Georgia,serif;margin:0;text-shadow:0 1px 2px #000}}h1{{font-size:2.2rem}}h2{{font-size:1.5rem;color:var(--gold)}}h3{{font-size:1.2rem;margin-top:18px}}h3 small{{color:var(--ink2);font-size:.8rem;font-family:inherit}}
.wrap{{max-width:1180px;margin:0 auto;display:grid;gap:16px}}.panel{{background:var(--glass);border:1px solid var(--hair);border-radius:14px;padding:16px 18px;box-shadow:0 10px 30px rgba(0,0,0,.45)}}
.sub{{color:var(--ink2);font-size:13.5px}}.hero{{display:grid;grid-template-columns:180px 1fr;gap:18px;align-items:start}}@media(max-width:700px){{.hero{{grid-template-columns:1fr}}}}
.hero img{{width:100%;border-radius:4.75%/3.5%;box-shadow:0 10px 24px rgba(0,0,0,.5)}}
table{{border-collapse:collapse;width:100%;font-size:14px}}th,td{{padding:7px 10px;border-bottom:1px solid rgba(255,255,255,.08);text-align:left}}th{{font-size:11px;letter-spacing:.1em;text-transform:uppercase;color:var(--gold)}}td.n{{text-align:right;font-variant-numeric:tabular-nums}}td.big{{font-family:"Cormorant Garamond",Georgia,serif;font-size:1.5rem;font-weight:700}}.up{{color:var(--good);font-weight:700}}.down{{color:var(--bad);font-weight:700}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:14px 12px}}.grid.small{{grid-template-columns:repeat(auto-fill,minmax(112px,1fr));gap:10px 8px}}
figure.card{{margin:0;min-width:0}}.card .pic{{position:relative}}.card img{{width:100%;aspect-ratio:63/88;object-fit:cover;border-radius:4.75%/3.5%;display:block;background:#2a221c;box-shadow:0 6px 16px rgba(0,0,0,.45)}}
.card.out img{{outline:3px solid var(--bad);filter:saturate(.5) brightness(.8)}}.card.in img{{outline:3px solid var(--good)}}
.card .badge{{position:absolute;left:6px;bottom:6px;font-family:"Cormorant Garamond",Georgia,serif;font-weight:700;padding:4px 8px;border-radius:999px;background:rgba(0,0,0,.75);border:1px solid var(--hair);color:var(--gold)}}.card.out .badge{{color:var(--bad)}}.card.in .badge{{color:var(--good)}}
.card .pill{{position:absolute;right:6px;bottom:6px;font-size:11px;font-weight:700;padding:2px 7px;border-radius:999px;background:rgba(0,0,0,.75);border:1px solid var(--hair)}}
figcaption{{margin-top:6px;font-size:13px;line-height:1.25}}figcaption b{{display:block}}figcaption span{{color:var(--ink2);font-size:12px}}figcaption i{{color:rgba(243,235,220,.5)}}
.swap{{display:grid;grid-template-columns:150px 32px 150px;gap:10px;align-items:start;padding:12px 0;border-top:1px solid rgba(255,255,255,.08)}}.swap .arrow{{font-size:26px;color:var(--gold);text-align:center;padding-top:80px}}
.swaps{{display:grid;grid-template-columns:repeat(auto-fill,minmax(340px,1fr));gap:0 24px}}
.curve{{display:grid;grid-template-columns:repeat(8,1fr);gap:6px;align-items:end;height:100px;max-width:420px}}.curve .col{{display:grid;grid-template-rows:1fr auto auto;height:100%;gap:3px;text-align:center;font-size:12px;color:var(--ink2)}}.curve .stick{{align-self:end;background:linear-gradient(180deg,var(--gold),#b78b3a);border-radius:4px 4px 0 0;min-height:2px}}
.two{{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:14px}}
</style></head><body><div class="wrap">
<header><h1>{e(cmd['name'])}</h1><p class="sub">Deck Helper report, 2026-10-27 · judged by the deck's own cards and categories; EDHREC ({data['edh']['decks']:,} decks) as a tie-breaker only.</p></header>
<section class="panel hero"><img src="{img(cmd, 'normal')}" alt="">
<div><h2>Before and after the seven swaps</h2><p class="sub">The plan the helper reads from your cards: {e(plan)}.</p>
<table style="margin-top:10px"><thead><tr><th></th><th class="n">Now</th><th class="n">After</th><th></th><th></th></tr></thead><tbody>
{''.join(f'<tr><td>{k}</td><td class="n big">{v1}</td><td class="n big">{v2}</td><td class="sub">{cap}</td><td class="n {"up" if str(d).startswith("+") and k != "Lands entering tapped" or (k == "Lands entering tapped" and str(d).startswith("-")) else "down" if str(d).startswith("-") or (k == "Lands entering tapped" and str(d).startswith("+")) else ""}">{d}</td></tr>' for k, v1, v2, cap, d in nums)}
</tbody></table>
<p class="sub" style="margin-top:10px">Power moves from {b['table']:.1f} to {a['table']:.1f}: the card counts now sit on the template, and the mana is faster. The bracket stays 2 because nothing added is a Game Changer, a combo or land denial; the next step up is a Jeska's Will or Mana Vault, which are Game Changers and worth a point or so each.</p></div></section>
<section class="panel"><h2>The swaps</h2><p class="sub">Out on the left, in on the right. Each cut is the deck's own reason; each add fills a category you were short on or shares your plan.</p>
<div class="swaps">{swaps_html}</div></section>
<section class="two"><div class="panel"><h2>Curve now</h2><div class="curve" style="margin-top:10px">{curve_rows}</div><p class="sub" style="margin-top:8px">{b['cheap']} plays at 2 mana or less. After the swaps the curve is {a['mv']:.2f}, unchanged in practice.</p></div>
<div class="panel"><h2>Cuts the helper considered</h2><p class="sub">Highest cut score first. Neheb and Cryptborn Horror are life-loss payoffs the classifier cannot yet see as on plan; if they are deliberate, keep them and cut Hypnotic Specter and Gogo instead.</p></div></section>
<section class="panel"><div class="grid">{cuts_html}</div></section>
<section class="panel"><h2>The whole list by job</h2><p class="sub">Cards leaving are marked OUT. The percentage is how often {e(who)} decks run the card.</p>{groups_html}</section>
<p class="sub">Images from Scryfall. Numbers from the MagicMobile Deck Helper test bed (scripts/deck-helper).</p>
</div></body></html>'''
out.write_text(page)
print(f'wrote {out} ({len(page)//1000} KB)')

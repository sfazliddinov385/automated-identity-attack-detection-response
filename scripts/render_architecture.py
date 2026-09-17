#!/usr/bin/env python3
"""Render the lab diagram. Requires Inkscape and DejaVu Sans fonts."""
from html import escape
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'diagrams'
OUT.mkdir(exist_ok=True)
W, H = 1600, 940
INK, MUTED, BORDER = '#182b40', '#506477', '#c4d0dc'
BLUE, GREEN = '#28699f', '#147d64'
parts = [f'''<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" role="img" aria-labelledby="title desc">
<title id="title">Identity attack detection and response</title>
<desc id="desc">Failed logins on VICTIM-B produce Windows logs on DC-01. Splunk and its connector send a detection to Shuffle. The responder requires approval on DC-01, followed by resubmission of the same alert from Shuffle. It then disables the five lab accounts and verifies their state in Active Directory. Event 4725 is separately checked in Splunk.</desc>
<defs>''']
for name, color in [('blue', BLUE), ('green', GREEN)]:
    parts.append(f'<marker id="{name}" markerWidth="10" markerHeight="10" refX="8" refY="5" orient="auto" markerUnits="userSpaceOnUse"><path d="M 0 0 L 9 5 L 0 10 Z" fill="{color}"/></marker>')
parts.append('</defs>')

def box(x, y, w, h, stroke=BORDER, fill='white'):
    parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="8" fill="{fill}" stroke="{stroke}" stroke-width="1.6"/>')

def text(x, y, label, size=22, color=INK, bold=False, anchor='start', mono=False):
    family = 'DejaVu Sans Mono, monospace' if mono else 'DejaVu Sans, sans-serif'
    parts.append(f'<text x="{x}" y="{y}" font-family="{family}" font-size="{size}" font-weight="{700 if bold else 400}" fill="{color}" text-anchor="{anchor}">{escape(label)}</text>')

def arrow(d, color='blue', dashed=False):
    parts.append(f'<path d="{d}" fill="none" stroke="{BLUE if color == "blue" else GREEN}" stroke-width="2.5" stroke-linejoin="round"'+(' stroke-dasharray="7 6"' if dashed else '')+f' marker-end="url(#{color})"/>')

parts.append('<rect width="1600" height="940" fill="#f7f9fc"/>')
text(64, 77, 'Identity attack detection and response', 44, bold=True)
text(64, 117, 'Splunk + Shuffle + Active Directory', 23, MUTED)
text(64, 183, 'Detection', 26, bold=True)

nodes = [
    (64, 'VICTIM-B', 'Failed SMB logins', '192.168.226.133'),
    (446, 'DC-01', 'Windows Security logs', '192.168.226.132'),
    (828, 'SIEM-01', 'Splunk + Python connector', '192.168.226.129'),
    (1210, 'SOAR-01', 'Shuffle', '192.168.226.134'),
]
for x, name, role, ip in nodes:
    box(x, 212, 326, 174)
    text(x+22, 256, name, 30, bold=True)
    text(x+22, 299, role, 21, MUTED)
    text(x+22, 353, ip, 18, MUTED, mono=True)
for x, *_ in nodes[:-1]:
    arrow(f'M {x+333} 297 H {x+374}')

text(64, 453, 'Response', 26, bold=True)
arrow('M 1373 392 V 452 H 272 V 509')
# The label sits above the line, away from the Response heading.
text(855, 438, 'POST /disable-users', 21, BLUE, anchor='middle', mono=True)

box(64, 520, 416, 184)
text(86, 565, 'Approval required', 28, bold=True)
text(86, 610, 'No accounts changed', 22, MUTED)
text(86, 657, 'HTTP 202 · pending_approval', 19, MUTED, mono=True)

box(592, 520, 416, 184)
text(614, 565, 'Approve request', 28, bold=True)
text(614, 610, 'Approve on DC-01', 22, MUTED)
text(614, 657, 'Resend same alert from Shuffle', 21, MUTED)

box(1120, 520, 416, 184, GREEN)
text(1142, 565, 'Disable + verify in AD', 27, bold=True)
text(1142, 610, 'Disable the five lab accounts', 21, MUTED)
text(1142, 657, 'Confirm all five are disabled', 21, GREEN)
arrow('M 488 608 H 584')
arrow('M 1016 608 H 1112', 'green')

text(64, 781, 'Audit', 26, bold=True)
arrow('M 1328 711 V 809', dashed=True)
box(64, 820, 1472, 76)
text(86, 869, 'DC-01: Event 4725', 25, bold=True)
arrow('M 355 859 H 421')
text(451, 869, 'Splunk', 25, bold=True)
text(738, 869, 'Check the audit events manually', 23, MUTED)
parts.append('</svg>')
svg = OUT / 'architecture-diagram.svg'
svg.write_text('\n'.join(parts)+'\n')
subprocess.run(['inkscape', str(svg), '--export-type=png',
                '--export-filename='+str(OUT/'architecture-diagram.png'),
                '--export-width=2400'], check=True)
print(svg)
print(OUT/'architecture-diagram.png')

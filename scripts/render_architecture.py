#!/usr/bin/env python3
"""Build the lab architecture SVG and PNG. Requires Inkscape for PNG export."""
from html import escape
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'diagrams'
OUT.mkdir(exist_ok=True)
W, H = 1800, 1480
C = dict(bg='#081321', card='#102238', card2='#13273e', line='#29415a',
         white='#f3f7fc', muted='#b8c9dc', dim='#819ab4', blue='#49b7ff',
         amber='#ffbd60', green='#48d8b3')
parts = [f'''<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" role="img" aria-labelledby="title desc">
<title id="title">Automated identity attack detection and response with local approval</title>
<desc id="desc">VICTIM-B generates failed SMB logons. DC-01 forwards Event 4625 to Splunk. A Python connector delivers detections to Shuffle. The DC responder holds live requests for local operator approval, which expires after 15 minutes by default. The operator resubmits the same alert from Shuffle. The responder disables the five allowed lab accounts and verifies their state in Active Directory. Windows Event 4725 is separately forwarded to Splunk and manually audited.</desc>
<defs>
<linearGradient id="background" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#0b192a"/><stop offset="1" stop-color="#07111e"/></linearGradient>
''']
for name in ['blue','amber','green']:
    parts.append(f'<marker id="arrow-{name}" markerWidth="10" markerHeight="10" refX="8" refY="5" orient="auto" markerUnits="userSpaceOnUse"><path d="M 0 0 L 9 5 L 0 10 Z" fill="{C[name]}"/></marker>')
parts.append('</defs>')

def rect(x,y,w,h,fill,stroke=None,r=18,sw=1):
    parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}"'+(f' stroke="{stroke}" stroke-width="{sw}"' if stroke else '')+'/>')

def text(x,y,s,size=23,color='white',weight=400,anchor='start',mono=False,spacing=None):
    family='DejaVu Sans Mono, monospace' if mono else 'DejaVu Sans, sans-serif'
    parts.append(f'<text x="{x}" y="{y}" fill="{C.get(color,color)}" font-family="{family}" font-size="{size}" font-weight="{weight}" text-anchor="{anchor}"'+(f' letter-spacing="{spacing}"' if spacing else '')+f'>{escape(s)}</text>')

def path(d,color='blue',arrow=True,dash=False,width=3):
    parts.append(f'<path d="{d}" fill="none" stroke="{C.get(color,color)}" stroke-width="{width}" stroke-linejoin="round" stroke-linecap="round"'+(f' marker-end="url(#arrow-{color})"' if arrow else '')+(' stroke-dasharray="8 8"' if dash else '')+'/>')

def section(y,num,title,sub=None):
    text(64,y,num,20,'blue',700,mono=True)
    text(112,y,title,28,'white',700)
    if sub: text(1736,y,sub,20,'dim',anchor='end')

def pill(x,y,w,label,color='blue'):
    rect(x,y,w,31,C['bg'],C[color],r=8,sw=1)
    text(x+w/2,y+22,label,15,color,700,anchor='middle',spacing=.8)

rect(0,0,W,H,'url(#background)',r=0)
text(64,47,'SECURITY OPERATIONS  /  LAB ARCHITECTURE',16,'green',700,spacing=2)
pill(1498,24,238,'VALIDATED · 17 SEP 2026','green')
text(64,109,'Automated Identity Attack Detection & Response',49,'white',700)
text(64,154,'Automatic detection. Local approval. Verified account disabling.',25,'muted')
path('M 64 187 H 1736','line',False,width=1)

section(230,'01','Detect automatically','MITRE ATT&CK T1110.003 · Password spraying')
xs=[64,492,920,1348]
labels=[
 ('TEST ENDPOINT','VICTIM-B',['Five controlled failed','SMB logons to DC-01'],'192.168.226.133','blue'),
 ('DOMAIN CONTROLLER','DC-01',['Active Directory + DNS','Forwards Event 4625 via UF'],'192.168.226.132','blue'),
 ('SIEM + CONNECTOR','SIEM-01',['Splunk: 5-minute correlation','60-second polling + dedup'],'192.168.226.129','blue'),
 ('ORCHESTRATION','SOAR-01',['Shuffle SOAR + Docker','Validates alert conditions'],'192.168.226.134','green'),
]
for x,(tag,title,lines,ip,color) in zip(xs,labels):
    rect(x,262,388,233,C['card'],C['line'],r=19)
    rect(x+24,286,4,28,C[color],r=2)
    text(x+42,306,tag,15,color,700,spacing=1.15)
    text(x+24,354,title,34,'white',700)
    for yy,line in zip([398,431],lines): text(x+24,yy,line,22,'muted')
    text(x+24,472,ip,19,'dim',mono=True)
for a,b in zip(xs,xs[1:]):path(f'M {a+393} 370 H {b-8}','blue')

section(559,'02','Require approval before response')
# Shuffle submits the first request to the responder on DC-01.
path('M 1542 500 V 596 H 324 V 639','green')
rect(618,577,778,37,C['bg'],r=8)
text(1007,602,'Authenticated POST /disable-users · HTTP 8081',21,'green',500,anchor='middle')

for x,color in [(64,'amber'),(640,'amber'),(1216,'green')]:
    rect(x,650,520,322,C['card'],C[color],r=20,sw=1.4)
    rect(x+24,674,4,27,C[color],r=2)
text(106,695,'LIVE REQUEST · DC-01',16,'amber',700,spacing=1)
text(88,744,'Awaiting approval',32,'white',700)
rect(88,768,472,42,'#332b20',r=8)
text(106,797,'202 · pending_approval',22,'amber',500,mono=True)
text(88,848,'No AD changes before approval.',23,'muted')
text(88,883,'HTTP callers cannot self-approve.',23,'muted')
text(88,941,'PowerShell responder on DC-01',20,'dim')

text(682,695,'HUMAN REVIEW · DC-01',16,'amber',700,spacing=1)
text(664,744,'Local operator approval',30,'white',700)
text(664,789,'Review source, users, and evidence.',22,'muted')
text(664,824,'Record operator identity and reason.',22,'muted')
text(664,859,'15-min default expiry · exact request',22,'muted')
rect(664,881,472,66,'#332b20',r=10)
text(680,906,'MANUAL RESUBMISSION',15,'amber',700,spacing=1)
text(680,932,'Send the same alert again from Shuffle.',21,'white')

text(1258,695,'APPROVED RESPONSE · DC-01',16,'green',700,spacing=1)
text(1240,744,'Disable + verify',32,'white',700)
text(1240,789,'Check all five users and their OU.',22,'muted')
text(1240,824,'Disable eligible lab accounts.',22,'muted')
text(1240,859,'Read AD state back from the same DC.',22,'muted')
rect(1240,881,472,66,'#103d35',r=10)
text(1258,907,'SUCCESS REQUIRES',15,'green',700,spacing=1)
text(1258,934,'5 / 5 accounts verified disabled',23,'white',700)
path('M 590 806 H 632','amber')
path('M 1166 806 H 1208','green')

section(1035,'03','Audit independently')
path('M 1476 978 V 1071','blue',True,True)
rect(64,1081,1672,130,C['card'],C['line'],r=19)
text(88,1128,'DC-01 · Event 4725',26,'white',700)
path('M 453 1120 H 505','blue')
text(534,1128,'SIEM-01 · Splunk',26,'white',700)
path('M 870 1120 H 922','blue')
text(955,1128,'Analyst checks users, actor, and time',25,'white',700)
text(88,1180,'Separate manual audit. Automatic response verification comes from Active Directory readback.',23,'muted')

text(64,1266,'Safeguards and lab boundaries',27,'white',700)
controls=[
 ('Request-bound approval',['Protected local approval records','Source, time, domain, and users'],'green'),
 ('Limited account scope',['Five-user allowlist + dedicated OU','Source-IP check + separate keys'],'blue'),
 ('Execution safeguards',['Dry run + durable processing claim','Completed replay returns prior result'],'blue'),
 ('Isolated lab boundary',['SYSTEM on DC-01 · internal HTTP','Single-source, short-window detection'],'amber'),
]
for x,(title,lines,col) in zip(xs,controls):
    path(f'M {x} 1291 H {x+388}','line',False,width=1)
    text(x,1327,title,23,col,700)
    text(x,1363,lines[0],19,'muted')
    text(x,1394,lines[1],19,'muted')
text(64,1449,'LAB VALIDATION: five accounts verified disabled + five matching account-disable events in Splunk.',18,'dim')
text(1736,1449,'APPROVAL FLOW · v2',16,'dim',700,anchor='end')
parts.append('</svg>')
svg=OUT/'architecture-diagram.svg'
svg.write_text('\n'.join(parts)+'\n')
subprocess.run(['inkscape',str(svg),'--export-type=png','--export-filename='+str(OUT/'architecture-diagram.png'),'--export-width=2400'],check=True)
print(svg)
print(OUT/'architecture-diagram.png')

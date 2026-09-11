# -*- coding: utf-8 -*-
import os, html, io
from structure import TREE, FIXED_COURSE, flatten

HERE = os.path.dirname(os.path.abspath(__file__))
DIST = os.path.join(HERE, "dist")
os.makedirs(DIST, exist_ok=True)
BOM = "\ufeff"

def esc(s): return html.escape(s, quote=True)

# ---------- readme + scripts ----------
def readme_text():
    lines = ["強腦力 G 槽資料夾說明", "=" * 40, "",
             "每個資料夾的名字都說明了用途。找不到地方放的檔案，一律先放 00_待整理。", ""]
    for n in TREE:
        lines.append(f"{n['name']}")
        lines.append(f"    {n['purpose']}")
        for c in n.get("children", []):
            p = c.get("purpose", "")
            lines.append(f"    ├ {c['name']}" + (f"　{p}" if p else ""))
        lines.append("")
    lines += ["每門課（20_課程教材 裡的每一夾）固定六個小資料夾：",
              *[f"    {c['name']}　{c['purpose']}" for c in FIXED_COURSE], "",
              "檔名規則：日期_主題_內容_版本.副檔名",
              "    例：2026-09-11_超級記憶力_第01講_講義_v2.pdf",
              "    日期用 年-月-日；版本用 v1、v2；定稿加 _定稿；舊版本放同層的 99_舊版。", "",
              "三個習慣：每週五清空 00_待整理；新課、新活動先建資料夾再存檔；每季把結束的東西搬進 90_封存/年份。",
              ""]
    return "\n".join(lines)

def write_bom(name, text, newline="\r\n"):
    with io.open(os.path.join(DIST, name), "w", encoding="utf-8", newline="") as f:
        f.write(BOM + text.replace("\n", newline))

def write_ascii(name, text):
    with io.open(os.path.join(DIST, name), "w", encoding="ascii", newline="") as f:
        f.write(text.replace("\n", "\r\n"))

folders = flatten(TREE)
ps_folders = ",\n".join("  '" + p.replace("'", "''") + "'" for p in folders)
create_ps = open(os.path.join(HERE, "create_template.ps1"), encoding="utf-8").read()
create_ps = create_ps.replace("__FOLDERS__", ps_folders).replace("__README__", readme_text().rstrip("\n"))
scan_ps = open(os.path.join(HERE, "scan_template.ps1"), encoding="utf-8").read()

write_bom("01_scan_G.ps1", scan_ps)
write_bom("02_create_folders.ps1", create_ps)
write_ascii("01_scan_G.bat", open(os.path.join(HERE, "scan.bat")).read())
write_ascii("02_create_folders.bat", open(os.path.join(HERE, "create.bat")).read())
write_bom("_資料夾說明.txt", readme_text())

# ---------- HTML pieces ----------
TAG_CLASS = {"個資": "warn", "大檔案": "big", "選用": "opt"}
def tags_html(tags):
    return "".join(f'<span class="tag tag-{TAG_CLASS[t]}">{esc(t)}</span>' for t in (tags or []))

def split_name(name):
    if len(name) > 2 and name[:2].isdigit() and name[2] == "_":
        return name[:2], name[2:]
    return "", name

def name_html(name, cls="nm"):
    num, rest = split_name(name)
    if num:
        return f'<span class="{cls}"><span class="num">{num}</span>{esc(rest)}</span>'
    return f'<span class="{cls}">{esc(name)}</span>'

def is_course(n):
    ch = n.get("children", [])
    return len(ch) == len(FIXED_COURSE) and all(a["name"] == b["name"] for a, b in zip(ch, FIXED_COURSE))

def li(n):
    out = ['<li>', '<div class="row">', '<i class="fd fd-s" aria-hidden="true"></i>',
           '<div class="rowtext">', name_html(n["name"])]
    if n.get("purpose"):
        out.append(f' <span class="desc">{esc(n["purpose"])}</span>')
    out.append(tags_html(n.get("tags")))
    if n.get("example"):
        out.append('<span class="tag tag-ex">範例</span>')
    out.append('</div></div>')
    if n.get("children") and not is_course(n):
        out.append('<ul>' + "".join(li(c) for c in n["children"]) + '</ul>')
    out.append('</li>')
    return "".join(out)

def overview_rows():
    out = []
    for n in TREE:
        out.append(
            '<li class="ov">'
            '<i class="fd" aria-hidden="true"></i>'
            f'<a class="ovname" href="#b-{n["name"][:2]}">{name_html(n["name"])}</a>'
            f'<span class="ovdesc">{esc(n["purpose"])}{tags_html(n.get("tags"))}</span>'
            '</li>')
    return "\n".join(out)

def branches():
    out = []
    for n in TREE:
        num = n["name"][:2]
        out.append(f'<article class="branch" id="b-{num}">')
        out.append('<header class="bhead"><i class="fd" aria-hidden="true"></i><div>')
        out.append(f'<h3>{name_html(n["name"], "bname")}{tags_html(n.get("tags"))}</h3>')
        out.append(f'<p class="bpurpose">{esc(n["purpose"])}</p>')
        if n.get("why"):
            out.append(f'<p class="bwhy">{esc(n["why"])}</p>')
        out.append('</div></header>')
        ch = n.get("children", [])
        if ch:
            out.append('<ul class="tree">' + "".join(li(c) for c in ch) + '</ul>')
            if any(is_course(c) for c in ch):
                out.append('<div class="fixed"><p class="fixed-title">每一門課裡面，固定長這樣</p><ul class="tree">'
                           + "".join(li(c) for c in FIXED_COURSE) + '</ul></div>')
        else:
            out.append('<p class="nosub">不再分小資料夾。</p>')
        out.append('</article>')
    return "\n".join(out)

CSS = r"""
:root{
  --bg:#F4F5F9;--surface:#FFFFFF;--surface-2:#EEF0F6;
  --ink:#191B30;--ink-2:#3B3F5C;--muted:#5F6382;--line:#DCDFEA;--line-2:#C4C8DA;
  --folder:#F2C75C;--folder-deep:#C9962A;--folder-text:#8A6410;--folder-bg:#FFF6DC;
  --violet:#5F4FD6;--violet-bg:#EEEBFF;
  --teal:#0F8F89;--teal-bg:#E1F4F2;
  --orange:#B8500C;--orange-bg:#FFEBDC;
  --red:#B9403F;--red-bg:#FBE7E6;
  --code-bg:#EEF0F6;
  --serif:"Noto Serif TC","PingFang TC","Microsoft JhengHei","Noto Sans TC",serif;
  --sans:"Noto Sans TC","PingFang TC","Microsoft JhengHei",sans-serif;
  --mono:"IBM Plex Mono",Consolas,"Microsoft JhengHei",monospace;
}
@media (prefers-color-scheme: dark){
  :root:not([data-theme="light"]){
    --bg:#14162A;--surface:#1C1F37;--surface-2:#242849;
    --ink:#ECEDF6;--ink-2:#CFD2E4;--muted:#A3A7C4;--line:#303456;--line-2:#434869;
    --folder:#F0C45A;--folder-deep:#B98A22;--folder-text:#F0C45A;--folder-bg:#33301F;
    --violet:#A89CFF;--violet-bg:#2B2850;
    --teal:#4FC9C1;--teal-bg:#1B3A3A;
    --orange:#FFA060;--orange-bg:#3E2A1B;
    --red:#FF8A88;--red-bg:#40252A;
    --code-bg:#242849;
  }
}
:root[data-theme="dark"]{
  --bg:#14162A;--surface:#1C1F37;--surface-2:#242849;
  --ink:#ECEDF6;--ink-2:#CFD2E4;--muted:#A3A7C4;--line:#303456;--line-2:#434869;
  --folder:#F0C45A;--folder-deep:#B98A22;--folder-text:#F0C45A;--folder-bg:#33301F;
  --violet:#A89CFF;--violet-bg:#2B2850;
  --teal:#4FC9C1;--teal-bg:#1B3A3A;
  --orange:#FFA060;--orange-bg:#3E2A1B;
  --red:#FF8A88;--red-bg:#40252A;
  --code-bg:#242849;
}
*{box-sizing:border-box}
html{scroll-behavior:smooth}
@media (prefers-reduced-motion: reduce){html{scroll-behavior:auto}}
body{margin:0;background:var(--bg);color:var(--ink);font-family:var(--sans);font-size:16px;line-height:1.8;-webkit-font-smoothing:antialiased}
@media (min-width:700px){body{font-size:17px}}
a{color:var(--violet);text-decoration:none}
a:hover{text-decoration:underline}
:focus-visible{outline:2px solid var(--violet);outline-offset:2px;border-radius:3px}
.page{max-width:1080px;margin:0 auto;padding-inline:20px;padding-block:32px 96px;display:grid;grid-template-columns:minmax(0,1fr);gap:32px}
@media (min-width:1000px){.page{grid-template-columns:200px minmax(0,760px);gap:56px;padding-inline:32px}}
main{min-width:0}
h1,h2{font-family:var(--serif);font-weight:700;letter-spacing:.01em;text-wrap:balance;margin:0}
h1{font-size:2.3rem;line-height:1.25}
h2{font-size:1.45rem;line-height:1.35;margin-block:0 .5rem;padding-top:.5rem}
h3{font-size:1.1rem;font-weight:700;margin:0;line-height:1.5}
p{margin:0}
.eyebrow{font-size:.78rem;letter-spacing:.14em;text-transform:uppercase;color:var(--folder-text);font-weight:600;margin-bottom:10px}
.lede{font-size:1.1rem;color:var(--ink-2);max-width:40em;margin-top:14px;text-wrap:pretty}
.meta{display:flex;flex-wrap:wrap;gap:8px;margin-top:18px}
.meta span{font-family:var(--mono);font-size:.78rem;color:var(--muted);background:var(--surface-2);padding:3px 10px;border-radius:999px}
header.top{padding-bottom:28px;border-bottom:1px solid var(--line)}
/* nav */
nav.toc{position:sticky;top:20px;align-self:start}
nav.toc .toc-title{font-size:.75rem;letter-spacing:.14em;text-transform:uppercase;color:var(--muted);margin-bottom:8px;font-weight:600}
nav.toc ol{list-style:none;margin:0;padding:0;display:flex;flex-wrap:wrap;gap:6px 14px}
@media (min-width:1000px){nav.toc ol{flex-direction:column;gap:2px}}
nav.toc a{display:block;color:var(--ink-2);font-size:.92rem;padding:3px 0;border-left:2px solid transparent}
@media (min-width:1000px){nav.toc a{padding-left:10px}nav.toc a:hover{border-left-color:var(--folder);text-decoration:none;color:var(--ink)}}
/* sections */
section.sec{padding-top:40px;display:grid;gap:18px}
section.sec>p{max-width:40em;text-wrap:pretty}
.notice{background:var(--folder-bg);border-left:4px solid var(--folder);padding:16px 20px;border-radius:0 8px 8px 0;margin-top:26px;display:grid;gap:6px}
.notice strong{color:var(--folder-text)}
.notice p{max-width:44em;text-wrap:pretty}
/* principles */
.principles{list-style:none;margin:0;padding:0;display:grid;gap:12px}
.principles li{display:grid;grid-template-columns:auto 1fr;gap:14px;align-items:start;background:var(--surface);border:1px solid var(--line);border-radius:8px;padding:14px 18px}
.principles .pn{font-family:var(--mono);color:var(--folder-text);font-weight:500;font-size:.95rem;line-height:1.9}
.principles b{display:block;font-weight:700}
.principles span{color:var(--ink-2)}
/* folder glyph */
.fd{display:inline-block;width:20px;height:16px;position:relative;flex:none;margin-top:6px}
.fd::before{content:"";position:absolute;left:0;top:0;width:9px;height:5px;background:var(--folder-deep);border-radius:2px 2px 0 0}
.fd::after{content:"";position:absolute;left:0;top:3px;right:0;bottom:0;background:var(--folder);border-radius:2px;box-shadow:inset 0 0 0 1px var(--folder-deep)}
.fd-s{width:16px;height:13px;margin-top:7px}
.fd-s::before{width:7px;height:4px}
.fd-s::after{top:2px}
/* overview list */
.ovlist{list-style:none;margin:0;padding:0;background:var(--surface);border:1px solid var(--line);border-radius:10px;overflow:hidden}
.ov{display:grid;grid-template-columns:20px 1fr;gap:6px 12px;padding:12px 18px;border-top:1px solid var(--line);align-items:start}
.ov:first-child{border-top:0}
@media (min-width:640px){.ov{grid-template-columns:20px 15.5em 1fr}}
.ovname{color:var(--ink);font-weight:700}
.ovname:hover{color:var(--violet);text-decoration:none}
.ovdesc{color:var(--ink-2)}
@media (max-width:639px){.ovdesc{grid-column:2}}
.num{font-family:var(--mono);font-weight:500;color:var(--folder-text);letter-spacing:.02em}
.nm{font-weight:600}
.bname{font-weight:700}
/* branches */
.branch{background:var(--surface);border:1px solid var(--line);border-radius:10px;padding:18px 20px 16px;display:grid;gap:12px;scroll-margin-top:24px}
.bhead{display:flex;gap:12px;align-items:flex-start}
.bhead .fd{margin-top:7px}
.bhead h3{display:flex;flex-wrap:wrap;gap:8px;align-items:center}
.bpurpose{color:var(--ink-2)}
.bwhy{color:var(--muted);font-size:.93rem;margin-top:4px;max-width:44em;text-wrap:pretty}
.tree,.tree ul{list-style:none;margin:0;padding:0}
.tree>li{padding:5px 0 5px 32px;position:relative}
.tree ul{margin-top:2px}
.tree ul li{position:relative;padding:4px 0 4px 26px}
.tree ul li::before{content:"";position:absolute;left:6px;top:0;bottom:0;border-left:1px solid var(--line-2)}
.tree ul li:last-child::before{bottom:auto;height:19px}
.tree ul li::after{content:"";position:absolute;left:6px;top:19px;width:14px;border-top:1px solid var(--line-2)}
.row{display:flex;gap:10px;align-items:flex-start}
.rowtext{min-width:0}
.desc{color:var(--muted)}
.desc::before{content:"　"}
.nosub{color:var(--muted);padding-left:32px;font-size:.95rem}
.fixed{margin-left:32px;border:1px dashed var(--line-2);border-radius:8px;padding:12px 14px 10px;background:var(--surface-2)}
.fixed .fixed-title{font-weight:700;font-size:.95rem;margin-bottom:4px}
.fixed .tree>li{padding-left:0}
.tag{display:inline-block;font-size:.72rem;font-weight:600;letter-spacing:.06em;padding:1px 8px;border-radius:999px;margin-left:8px;vertical-align:2px;white-space:nowrap}
.tag-warn{background:var(--orange-bg);color:var(--orange)}
.tag-big{background:var(--teal-bg);color:var(--teal)}
.tag-opt{background:var(--surface-2);color:var(--muted)}
.tag-ex{background:var(--violet-bg);color:var(--violet)}
.legend{display:flex;flex-wrap:wrap;gap:6px 14px;font-size:.9rem;color:var(--muted);align-items:center}
.legend .tag{margin-left:0}
/* numbering aside */
.aside{border:1px solid var(--line);border-radius:10px;padding:16px 20px;display:grid;gap:8px;background:var(--surface)}
.aside h3{font-size:1rem}
.aside ul{margin:0;padding-left:1.2em;color:var(--ink-2);display:grid;gap:4px}
/* filename */
.pattern{font-family:var(--mono);font-size:1.05rem;background:var(--code-bg);padding:12px 16px;border-radius:8px;overflow-x:auto;white-space:nowrap}
.pattern b{color:var(--folder-text);font-weight:500}
.examples{display:grid;gap:14px}
@media (min-width:720px){.examples{grid-template-columns:1fr 1fr}}
.ex{background:var(--surface);border:1px solid var(--line);border-radius:10px;padding:14px 18px;display:grid;gap:8px;align-content:start}
.ex h3{font-size:.95rem;display:flex;align-items:center;gap:8px}
.ex .pill{font-size:.72rem;letter-spacing:.06em;padding:1px 8px;border-radius:999px;font-weight:600}
.pill-good{background:var(--teal-bg);color:var(--teal)}
.pill-bad{background:var(--red-bg);color:var(--red)}
.ex ul{list-style:none;margin:0;padding:0;display:grid;gap:6px}
.ex li{font-family:var(--mono);font-size:.86rem;line-height:1.55;word-break:break-all;color:var(--ink-2)}
.ex li small{display:block;font-family:var(--sans);color:var(--muted);font-size:.82rem}
.rules{margin:0;padding-left:1.3em;display:grid;gap:6px;color:var(--ink-2)}
.rules li::marker{color:var(--folder-text);font-family:var(--mono)}
/* table */
.tablewrap{overflow-x:auto;border:1px solid var(--line);border-radius:10px;background:var(--surface)}
table{border-collapse:collapse;width:100%;min-width:560px;font-size:.95rem}
th,td{text-align:left;padding:10px 16px;vertical-align:top;border-top:1px solid var(--line)}
th{font-size:.78rem;letter-spacing:.1em;text-transform:uppercase;color:var(--muted);font-weight:600;border-top:0;background:var(--surface-2)}
td.path{font-family:var(--mono);font-size:.86rem;color:var(--ink);white-space:nowrap}
td.path .num{color:var(--folder-text)}
td .sub{display:block;color:var(--muted);font-size:.85rem;font-family:var(--sans)}
/* steps */
.steps{list-style:none;margin:0;padding:0;display:grid;gap:14px;counter-reset:step}
.steps li{display:grid;grid-template-columns:auto 1fr;gap:16px;background:var(--surface);border:1px solid var(--line);border-radius:10px;padding:16px 20px}
.steps .sn{font-family:var(--mono);font-size:1.6rem;font-weight:500;color:var(--folder-text);line-height:1.2;min-width:1.4em}
.steps h3{display:flex;flex-wrap:wrap;gap:8px 12px;align-items:baseline}
.steps .who{font-size:.75rem;letter-spacing:.08em;font-weight:600;padding:1px 8px;border-radius:999px;background:var(--violet-bg);color:var(--violet)}
.steps .who.me{background:var(--teal-bg);color:var(--teal)}
.steps p{color:var(--ink-2);margin-top:4px;text-wrap:pretty}
.steps code{font-family:var(--mono);font-size:.88em;background:var(--code-bg);padding:1px 6px;border-radius:4px}
.safe{display:grid;gap:8px;border-left:4px solid var(--teal);background:var(--teal-bg);padding:14px 18px;border-radius:0 8px 8px 0}
.safe b{color:var(--teal)}
.safe ul{margin:0;padding-left:1.2em;display:grid;gap:4px;color:var(--ink-2)}
/* habits */
.habits{list-style:none;margin:0;padding:0;display:grid;gap:10px}
.habits li{display:grid;grid-template-columns:9em 1fr;gap:12px;padding:12px 16px;background:var(--surface);border:1px solid var(--line);border-radius:8px}
@media (max-width:520px){.habits li{grid-template-columns:1fr;gap:2px}}
.habits .when{font-weight:700}
.habits span{color:var(--ink-2)}
/* files */
.files{display:grid;gap:10px}
.file{display:grid;grid-template-columns:auto 1fr;gap:14px;align-items:start;background:var(--surface);border:1px solid var(--line);border-radius:8px;padding:12px 16px}
.file .fn{font-family:var(--mono);font-size:.9rem;font-weight:500;white-space:nowrap}
.file span{color:var(--ink-2)}
pre{font-family:var(--mono);font-size:.86rem;background:var(--code-bg);padding:14px 16px;border-radius:8px;overflow-x:auto;margin:0;line-height:1.6}
.ask{background:var(--ink);color:var(--bg);border-radius:12px;padding:22px 24px;display:grid;gap:10px;margin-top:48px}
:root[data-theme="dark"] .ask{background:var(--surface-2);color:var(--ink)}
@media (prefers-color-scheme: dark){:root:not([data-theme="light"]) .ask{background:var(--surface-2);color:var(--ink)}}
.ask h2{font-size:1.25rem;padding-top:0}
.ask ol{margin:0;padding-left:1.3em;display:grid;gap:6px}
.ask li::marker{font-family:var(--mono);color:var(--folder)}
footer.foot{margin-top:32px;color:var(--muted);font-size:.85rem;display:grid;gap:4px}
"""

# ---------- decision table ----------
DECISION = [
    ("剛下載、剛拍、還不確定放哪", "00", "_待整理", "每週五一次清掉"),
    ("上課簡報、講義、練習題", "20", "_課程教材／該課程／02 或 03", "簡報放 02，發給學員的放 03"),
    ("剪好、要上架的課程影片", "20", "_課程教材／該課程／04_影片成品", "母檔放這，Vimeo 連結記在影片清單.txt"),
    ("手機、相機直出的原始影片", "30", "_影片與素材／31_原始拍攝檔／日期_內容", "不改檔名，用資料夾名標日期"),
    ("剪映、CapCut、Premiere 專案", "30", "_影片與素材／32_剪輯專案檔", "一支影片一個資料夾"),
    ("YouTube 長片、短影音成品", "30", "_影片與素材／33_成品影片", "腳本與縮圖放 43"),
    ("廣告圖、廣告影片、成效截圖", "40", "_行銷推廣／41_廣告投放／活動名稱", ""),
    ("LINE 圖文、免費資源 PDF、QR code", "40", "_行銷推廣／42_LINE官方帳號", ""),
    ("某一場實體活動的所有東西", "40", "_行銷推廣／45_活動與場次／日期_地點_活動", "例：2026-08-29_高雄_記憶實戰課"),
    ("SEO 文章、銷售頁文案、群發信", "40", "_行銷推廣／46_文案與文章", ""),
    ("學員見證截圖、家長回饋", "40", "_行銷推廣／47_見證與案例", "簽好的授權書放 55"),
    ("報名表、名單、繳費、出席", "50", "_學員與客戶／51_報名與名單／梯次", "含個資，限制分享"),
    ("退費申請、客訴處理", "50", "_學員與客戶／54_客服與退費", ""),
    ("發票、收據、對帳、報稅", "10", "_公司管理／13_財務與發票／年份", ""),
    ("合約", "10", "_公司管理／12_合約與法律文件", "師傅的合約放 81"),
    ("Logo、模板、形象照、名片", "70", "_品牌資產", ""),
    ("網站用的圖片原檔、後台匯出的 CSV", "60", "_網站與系統", ""),
    ("找師傅系列的任何東西", "80", "_就業力精品課_找師傅", "老師、課程、行銷、報名都在這"),
    ("已經結束、超過一年沒動", "90", "_封存／年份", "保留原本的資料夾名稱"),
]

def decision_rows():
    out = []
    for what, num, rest, note in DECISION:
        note_html = f'<span class="sub">{esc(note)}</span>' if note else ""
        out.append(f'<tr><td>{esc(what)}</td><td class="path"><span class="num">{num}</span>{esc(rest)}{note_html}</td></tr>')
    return "\n".join(out)

BODY = f"""<title>強腦力 G 槽整理提案</title>
<meta name="description" content="強腦力 SkyBraining 的 G 槽資料夾架構、檔名規則與分批搬移作法">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Noto+Serif+TC:wght@700&family=Noto+Sans+TC:wght@400;500;700&family=IBM+Plex+Mono:wght@400;500&display=swap">
<style>{CSS}</style>
<div class="page">
<nav class="toc" aria-label="目錄">
  <div class="toc-title">目錄</div>
  <ol>
    <li><a href="#principles">整理原則</a></li>
    <li><a href="#overview">最上層架構</a></li>
    <li><a href="#detail">每一層放什麼</a></li>
    <li><a href="#naming">檔名規則</a></li>
    <li><a href="#where">這個檔案放哪</a></li>
    <li><a href="#steps">執行步驟</a></li>
    <li><a href="#habits">維護習慣</a></li>
    <li><a href="#files">附件與腳本</a></li>
    <li><a href="#reply">需要你回覆</a></li>
  </ol>
</nav>
<main>
<header class="top">
  <div class="eyebrow">強腦力 SkyBraining｜內部作業文件</div>
  <h1>G 槽整理提案</h1>
  <p class="lede">一套「看名字就知道放哪」的資料夾架構，加上檔名規則和分批搬移的作法。目前只是提案，還沒動你任何一個檔案。</p>
  <div class="meta"><span>提案 v1</span><span>2026-09-11</span><span>{len(folders)} 個資料夾</span><span>兩支腳本：盤點、建資料夾</span></div>
  <div class="notice">
    <strong>先說清楚：我從這裡看不到你的 G:\\</strong>
    <p>這個工作環境在雲端，連不到你的電腦。所以這份架構是依照強腦力的業務內容擬的：線上課、高雄實體班、找師傅精品課、YouTube 與短影音、LINE 官方帳號、廣告與活動場次、後台與金流。</p>
    <p>要把你「現在的檔案」一個個對進新架構，需要先跑第 1 步的盤點腳本（只讀不改），把結果傳給我，我再做「舊資料夾 → 新位置」的搬移對照表。</p>
  </div>
</header>

<section class="sec" id="principles">
  <h2>五個整理原則</h2>
  <p>整套架構都從這五條長出來。之後遇到沒寫到的情況，照這五條判斷就不會錯。</p>
  <ol class="principles">
    <li><span class="pn">1</span><div><b>看名字就知道放哪</b><span>每個資料夾都是中文、都說清楚用途。不用縮寫、不用英文代號、不用「其他」「雜項」。</span></div></li>
    <li><span class="pn">2</span><div><b>數字開頭，順序固定</b><span>兩位數字決定排列順序：常用的在前、封存在後。子資料夾沿用上一層的十位數，光看號碼就知道它屬於哪一區。</span></div></li>
    <li><span class="pn">3</span><div><b>一個檔案只有一個家</b><span>每種檔案都有明確的歸屬（見「這個檔案放哪」）。想不出來就放 00_待整理，不要自己另開新的最上層資料夾。</span></div></li>
    <li><span class="pn">4</span><div><b>原始檔集中，成品跟著用途走</b><span>拍攝原檔與剪輯專案都在 30。剪好的課程影片放課程資料夾，廣告影片放廣告活動的資料夾。</span></div></li>
    <li><span class="pn">5</span><div><b>只搬不刪</b><span>整個過程不刪任何檔案。每一筆搬移都有紀錄可以還原；舊東西進 90_封存，不是進垃圾桶。</span></div></li>
  </ol>
</section>

<section class="sec" id="overview">
  <h2>最上層架構：{len(TREE)} 個資料夾</h2>
  <p>打開 G:\\ 只會看到這 {len(TREE)} 個。點名稱可以跳到它的細節。</p>
  <ul class="ovlist">
{overview_rows()}
  </ul>
  <div class="legend"><span>標記：</span><span class="tag tag-warn">個資</span>含學員或員工個資，限制分享　<span class="tag tag-big">大檔案</span>影片為主，占空間最多　<span class="tag tag-opt">選用</span>用不到可以不建</div>
  <div class="aside">
    <h3>為什麼名字都用數字開頭</h3>
    <ul>
      <li>檔案總管是照名稱排序的。有了數字，順序就固定：00 待整理永遠在最上面，90 封存和 99 個人永遠在最下面。</li>
      <li>最上層用 10、20、30 跳著編，中間留空位，以後要加一區不用全部重編。</li>
      <li>第二層沿用十位數：看到「45_活動與場次」就知道它在 40_行銷推廣裡面；看到「13_財務與發票」就知道在 10_公司管理。</li>
      <li>依日期命名的資料夾（活動、梯次、拍攝）用「年-月-日_名稱」開頭，自動照時間排。</li>
    </ul>
  </div>
</section>

<section class="sec" id="detail">
  <h2>每一層放什麼</h2>
  <p>每個資料夾下面列出它的子資料夾、放什麼，以及為什麼這樣分。灰字是判斷用的說明，不是資料夾名稱。</p>
{branches()}
</section>

<section class="sec" id="naming">
  <h2>檔名規則</h2>
  <p>資料夾負責「分類」，檔名負責「排序」和「一眼認出」。四段式，用底線分開：</p>
  <div class="pattern"><b>日期</b>_<b>主題</b>_<b>內容</b>_<b>版本</b>.副檔名</div>
  <div class="examples">
    <div class="ex">
      <h3><span class="pill pill-good">這樣取</span>一看就知道是什麼、哪一版</h3>
      <ul>
        <li>2026-09-11_超級記憶力_第01講_講義_v2.pdf</li>
        <li>2026-08-27_台北記憶實戰課_FB廣告_1080x1080_v3.jpg</li>
        <li>2026-09_LINE群發_九月開課通知_定稿.docx</li>
        <li>2026-08-29_高雄記憶實戰課_家長見證_王媽媽.mp4</li>
      </ul>
    </div>
    <div class="ex">
      <h3><span class="pill pill-bad">避免</span>三個月後自己也看不懂</h3>
      <ul>
        <li>簡報 最終版(2).pptx<small>「最終」之後一定還有更終</small></li>
        <li>IMG_4821.MOV 直接丟在根目錄<small>原始檔可以不改名，但要進「日期_內容」的資料夾</small></li>
        <li>新增資料夾／未命名／副本 - 副本<small>盤點腳本會把這些全部找出來</small></li>
        <li>9月11日講義.pdf<small>不會照時間排，換成 2026-09-11</small></li>
      </ul>
    </div>
  </div>
  <ol class="rules">
    <li>日期寫「年-月-日」：2026-09-11；只到月份就寫 2026-09。這樣排序就是時間順序。</li>
    <li>段落之間用底線「_」，不用空格；尺寸、平台這類補充放在「內容」那一段。</li>
    <li>版本用 v1、v2 往上加；定稿在後面加「_定稿」。不要用「最新」「最終」「真的最終」。</li>
    <li>被取代的舊版本，搬到同一層的 99_舊版，不要跟現行版本擺在一起。</li>
    <li>相機、手機直出的原始檔不改檔名，用它所在的資料夾名稱（日期_內容）來辨識就好。</li>
    <li>不要留「副本」「新增資料夾」「未命名」「(1)」這種名稱。</li>
  </ol>
</section>

<section class="sec" id="where">
  <h2>這個檔案放哪</h2>
  <p>手上有一個檔案、不確定該進哪裡時，查這張表。找不到對應的就放 00_待整理，週五再一起決定。</p>
  <div class="tablewrap">
    <table>
      <thead><tr><th>你手上的檔案</th><th>放去哪裡</th></tr></thead>
      <tbody>
{decision_rows()}
      </tbody>
    </table>
  </div>
</section>

<section class="sec" id="steps">
  <h2>執行步驟</h2>
  <p>分五步，每一步都可以停下來檢查。前三步完全不會動到現有檔案。</p>
  <ol class="steps">
    <li><span class="sn">1</span><div><h3>盤點 <span class="who">你來做</span></h3><p>對 <code>01_scan_G.bat</code> 按兩下，按 Enter 用 G:\\（Google Drive 的話可以改填 G:\\我的雲端硬碟）。跑完桌面會多出「G槽盤點_日期.txt」和「G槽盤點_日期.csv」，把這兩個檔案傳給我。只讀取，不改任何東西；檔案很多的話可能要幾分鐘到幾十分鐘。</p></div></li>
    <li><span class="sn">2</span><div><h3>做搬移對照表 <span class="who me">我來做</span></h3><p>我依盤點結果，把你現有的每個資料夾（必要時到檔案）對應到新架構，列成一張「舊位置 → 新位置」的表給你確認。名稱看不懂、想改的，這時候一起改。</p></div></li>
    <li><span class="sn">3</span><div><h3>建立空架構 <span class="who">你來做</span></h3><p>你確認名稱後，對 <code>02_create_folders.bat</code> 按兩下。它只建立空資料夾（{len(folders)} 個）並放一份「_資料夾說明.txt」在根目錄；已存在的會跳過，現有檔案完全不動。</p></div></li>
    <li><span class="sn">4</span><div><h3>分批搬移 <span class="who me">我產生腳本</span><span class="who">你按執行</span></h3><p>我依確認過的對照表產生 <code>03_move.ps1</code>：只搬不刪，每一筆搬移寫進「搬移紀錄.csv」，隨時可以照紀錄搬回去。先搬最確定的三區（課程教材、品牌資產、影片），再搬行銷與公司管理，最後剩下的留在 00_待整理慢慢分。</p></div></li>
    <li><span class="sn">5</span><div><h3>收尾 <span class="who">你來做</span></h3><p>舊資料夾清空後才刪掉那個空殼；把 50_學員與客戶 的分享權限縮到需要的人；之後照下面的維護習慣走。</p></div></li>
  </ol>
  <div class="safe">
    <b>安全上的三件事</b>
    <ul>
      <li>全程不刪任何檔案，只搬。搬移紀錄可以還原。</li>
      <li>G:\\ 如果是 Google Drive：分享連結綁的是檔案本身，搬移或改資料夾名稱不會讓連結失效；搬移只是改位置，不會重新上傳。</li>
      <li>大量搬移前，先等雲端同步跑完（右下角的雲端圖示沒在轉），中途不要關機。</li>
    </ul>
  </div>
</section>

<section class="sec" id="habits">
  <h2>維護習慣</h2>
  <p>架構建好之後，靠這五個習慣維持。每一個都很短。</p>
  <ul class="habits">
    <li><span class="when">每週五 15 分鐘</span><span>清空 00_待整理：每個檔案照「這個檔案放哪」歸位，順手照檔名規則改名。</span></li>
    <li><span class="when">每次開新課、新活動</span><span>先建資料夾（年-月-日_地點_活動，或 年-月_課程名），再開始存檔。</span></li>
    <li><span class="when">每季一次</span><span>把結束的活動、改版前的教材搬進 90_封存／年份，保留原資料夾名稱。</span></li>
    <li><span class="when">每年 1 月</span><span>13_財務與發票 和 90_封存 各開一個新年份資料夾。</span></li>
    <li><span class="when">分享給別人前</span><span>只分享需要的那一區（例如剪輯師只給 30、助教只給 20）；50_學員與客戶 永遠不整夾分享。</span></li>
  </ul>
</section>

<section class="sec" id="files">
  <h2>附件與腳本</h2>
  <p>四個檔案放在同一個資料夾，對 .bat 按兩下就會執行對應的 .ps1。都不需要改 Windows 設定；如果跳出「Windows 已保護你的電腦」，點「其他資訊」再點「仍要執行」。</p>
  <div class="files">
    <div class="file"><span class="fn">01_scan_G.bat<br>01_scan_G.ps1</span><span>盤點。只讀取資料夾與檔名，輸出摘要（資料夾樹、副檔名、最大的檔案、同名檔案、名稱有「副本」「最終」之類的檔案）和完整清單到桌面。</span></div>
    <div class="file"><span class="fn">02_create_folders.bat<br>02_create_folders.ps1</span><span>建立空架構。會先問要建在哪、再要你輸入 Y 確認；已存在的跳過。想先看不建，可以加 -DryRun。</span></div>
    <div class="file"><span class="fn">_資料夾說明.txt</span><span>第 3 步會自動放到根目錄，給任何打開 G 槽的人看的一頁說明。這裡先附一份預覽。</span></div>
  </div>
  <pre>進階：在 PowerShell 直接執行，指定路徑或只預覽
powershell -NoProfile -ExecutionPolicy Bypass -File .\\01_scan_G.ps1 -Root "G:\\我的雲端硬碟"
powershell -NoProfile -ExecutionPolicy Bypass -File .\\02_create_folders.ps1 -Root "G:\\" -DryRun</pre>
</section>

<div class="ask" id="reply">
  <h2>需要你回覆的三件事</h2>
  <ol>
    <li>看完架構，哪些名稱要改、哪幾區用不到、有沒有漏掉的業務（例如還有別的課或別的品牌）。</li>
    <li>跑第 1 步的盤點，把桌面上的 txt 和 csv 傳給我。</li>
    <li>告訴我 G:\\ 是 Google Drive 還是一般硬碟，以及根目錄是 G:\\ 還是 G:\\我的雲端硬碟。</li>
  </ol>
</div>
<footer class="foot">
  <span>強腦力 SkyBraining・G 槽整理提案 v1・2026-09-11</span>
  <span>資料夾名稱要改的話直接告訴我，我會同步更新這一頁、兩支腳本和說明檔。</span>
</footer>
</main>
</div>
"""

with io.open(os.path.join(DIST, "index.html"), "w", encoding="utf-8") as f:
    f.write(BODY)

STANDALONE = ('<!doctype html>\n<html lang="zh-Hant-TW">\n<head>\n<meta charset="utf-8">\n'
              '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
              '<meta name="color-scheme" content="light dark">\n' + BODY.split("<div class=\"page\">", 1)[0]
              + '</head>\n<body>\n<div class="page">' + BODY.split("<div class=\"page\">", 1)[1] + '</body>\n</html>\n')
with io.open(os.path.join(DIST, "強腦力G槽整理提案.html"), "w", encoding="utf-8") as f:
    f.write(STANDALONE)

print("built:", sorted(os.listdir(DIST)))
print("html bytes:", len(BODY.encode("utf-8")))

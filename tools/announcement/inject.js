// 網站公告片段批次插入／更新（全站沒有共用檔，只能每頁 inline）
// 用法：node tools/announcement/inject.js          → 插入或整段替換
//       node tools/announcement/inject.js --dry    → 只列出會改哪些頁，不寫檔
//       node tools/announcement/inject.js --remove → 全部拿掉
// 片段用 <!-- SB-ANN:START … --> … <!-- SB-ANN:END --> 包住；改 snippet.html 後重跑就會整段換新。
// 寫檔前後都把每頁 inline script 抽出來跑 node --check，任何一頁變壞就整批不寫。
const fs = require('fs'), path = require('path'), os = require('os'), cp = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');
const DRY = process.argv.includes('--dry'), REMOVE = process.argv.includes('--remove');
const SNIP = fs.readFileSync(path.join(__dirname, 'snippet.html'), 'utf8').replace(/\r\n/g, '\n').trim();
const BLOCK_RE = /[ \t]*<!-- SB-ANN:START[\s\S]*?<!-- SB-ANN:END -->\r?\n?/g;

// 登入後公告：會員才看得到的頁
const LOGIN_PAGES = ['member.html', 'account.html', 'watch.html'];
// 不跳公告：後台、結帳與付款結果、登入流程、婦女再就業報名系列、講師班簡易報名表、內部示意頁
const SKIP = [/^admin/, /^checkout\.html$/, /^success\.html$/, /^login\.html$/, /^line-callback\.html$/,
  /^funv/, /^mindmap-trainer-1107\.html$/, /^pro-shifu-preview\.html$/, /^story-sample\.html$/];

const pages = fs.readdirSync(ROOT).filter(f => f.endsWith('.html')).sort();
const plan = pages.map(f => ({ f, mode: LOGIN_PAGES.includes(f) ? 'login' : SKIP.some(r => r.test(f)) ? null : 'site' }));

const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'sbann-'));
function checkScripts(html, tag) {
  const re = /<script([^>]*)>([\s\S]*?)<\/script>/gi; let m, i = 0; const bad = [];
  while ((m = re.exec(html))) {
    i++; const at = m[1], src = m[2];
    if (!src.trim() || /\ssrc=/.test(at)) continue;
    if (/ld\+json|application\/json/.test(at)) { try { JSON.parse(src); } catch (e) { bad.push('#' + i + ' JSON'); } continue; }
    const file = path.join(TMP, tag + '_' + i + (/module/.test(at) ? '.mjs' : '.js'));
    fs.writeFileSync(file, src);
    try { cp.execFileSync(process.execPath, ['--check', file], { stdio: 'pipe' }); } catch (e) { bad.push('#' + i); }
  }
  return bad;
}

const out = []; let problems = 0;
for (const p of plan) {
  const file = path.join(ROOT, p.f);
  const before = fs.readFileSync(file, 'utf8');
  const nl = before.includes('\r\n') ? '\r\n' : '\n';
  let after = before.replace(BLOCK_RE, '');
  if (p.mode && !REMOVE) {
    const ends = after.split('</body>').length - 1;
    if (ends !== 1) { console.log('  ✗ ' + p.f + '：</body> 有 ' + ends + ' 個，跳過'); problems++; continue; }
    const block = SNIP.replace("var MODE='__MODE__';", "var MODE='" + p.mode + "';").replace(/\n/g, nl) + nl;
    if (!block.includes("var MODE='" + p.mode + "'")) throw new Error('snippet.html 找不到 MODE 佔位');
    after = after.replace('</body>', block + '</body>');
  }
  if (after === before) continue;
  const b0 = checkScripts(before, 'b_' + p.f), b1 = checkScripts(after, 'a_' + p.f);
  if (b1.length > b0.length) { console.log('  ✗ ' + p.f + '：改完 inline script 語法錯 ' + b1.join(',')); problems++; continue; }
  out.push({ ...p, file, after, scripts: b1.length });
}
fs.rmSync(TMP, { recursive: true, force: true });

const n = m => out.filter(o => o.mode === m).length;
console.log((DRY ? '（乾跑）' : '') + (REMOVE ? '移除' : '插入／更新') + '：會改 ' + out.length + ' 頁（進站 ' + n('site') + '、登入後 ' + n('login') + (REMOVE ? '' : '') + '）');
console.log('不跳公告的頁：' + plan.filter(p => !p.mode).map(p => p.f).join('、'));
if (problems) { console.log('有 ' + problems + ' 個問題，整批不寫。'); process.exit(1); }
if (!DRY) for (const o of out) fs.writeFileSync(o.file, o.after);
console.log(DRY ? '沒有寫檔。' : '已寫入。');

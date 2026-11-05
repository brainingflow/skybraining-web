#!/usr/bin/env node
// 用法：node tools/build-llms-full.js  → 在網站根目錄產生 llms-full.txt
// 只收 sitemap.xml 裡有的頁，避免把 noindex 頁、就業力頁放進給 AI 讀的全文檔。
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const SITE = 'https://skybraining.com';

const BRAND_PAGES = [
  'kaohsiung.html', 'courses.html',
  'course-memory.html', 'course-thinking.html', 'course-strong-thinking.html',
  'course-onsite-basic.html', 'course-onsite-advanced.html', 'course-bundle.html',
  'free.html', 'mindmap-free.html', 'mindmap.html', 'memory-science.html',
];

const sitemap = fs.readFileSync(path.join(ROOT, 'sitemap.xml'), 'utf8');
const inSitemap = (f) => {
  const loc = f === 'index.html' ? `${SITE}/` : `${SITE}/${f}`;
  return sitemap.includes(`<loc>${loc}</loc>`);
};

const all = fs.readdirSync(ROOT).filter((f) => f.endsWith('.html'));
const articles = all.filter((f) => /^article-.+\.html$/.test(f)).sort();
const learns = all.filter((f) => /^learn-.+\.html$/.test(f)).sort();
const pages = [...BRAND_PAGES, ...articles, ...learns].filter((f) => all.includes(f) && inSitemap(f));

const ENT = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', middot: '·', hellip: '…', ndash: '–', mdash: '—', times: '×', rarr: '→', larr: '←', copy: '©' };
const decode = (s) => s
  .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
  .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(+d))
  .replace(/&([a-z]+);/gi, (m, n) => (n.toLowerCase() in ENT ? ENT[n.toLowerCase()] : m));

const inline = (s) => decode(s.replace(/<br\s*\/?>/gi, ' ').replace(/<[^>]+>/g, '')).replace(/\s+/g, ' ').trim();

function pick(html, re) {
  const m = html.match(re);
  return m ? m[1] : '';
}

function toText(fragment) {
  let s = fragment
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/<(script|style|svg|noscript|template|form|button|iframe|select|textarea|dialog)\b[\s\S]*?<\/\1>/gi, '')
    .replace(/<(input|img|source|video|audio)\b[^>]*>/gi, '');

  s = s.replace(/<a\b[^>]*href=["'](https?:\/\/[^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi, (m, href, text) => {
    const t = inline(text);
    if (!t) return '';
    if (/skybraining\.com/.test(href) || t === href) return t;
    return `${t}（${href}）`;
  });

  s = s.replace(/<h([1-6])\b[^>]*>([\s\S]*?)<\/h\1>/gi, (m, lv, text) => {
    const t = inline(text);
    if (!t) return '\n';
    return `\n\n${'#'.repeat(Math.min(+lv + 1, 6))} ${t}\n\n`;
  });
  s = s.replace(/<small\b[^>]*>/gi, '：');
  s = s.replace(/<li\b[^>]*>/gi, '\n- ');
  s = s.replace(/<(td|th)\b[^>]*>/gi, ' | ');
  s = s.replace(/<br\s*\/?>/gi, '\n');
  s = s.replace(/<\/?(p|div|section|header|article|figure|figcaption|blockquote|ul|ol|tr|table|details|summary|dl|dt|dd|main|aside)\b[^>]*>/gi, '\n');
  s = s.replace(/<[^>]+>/g, '');
  s = decode(s);

  return s
    .split('\n')
    .map((l) => l.replace(/[ \t ]+/g, ' ').trim())
    .filter((l, i, arr) => !(l === '-' || l === '|'))
    .join('\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

function extract(file) {
  const html = fs.readFileSync(path.join(ROOT, file), 'utf8');
  const clean = html.replace(/<!--[\s\S]*?-->/g, '');
  const url = pick(clean, /<link rel="canonical" href="([^"]+)"/i) || `${SITE}/${file}`;
  const h1 = inline(pick(clean, /<h1\b[^>]*>([\s\S]*?)<\/h1>/i));
  const docTitle = inline(pick(clean, /<title>([\s\S]*?)<\/title>/i));
  // 課程頁的 H1 是標語、課名在 <title>；文章頁的 H1 才是篇名
  const title = (/<article\b/i.test(clean) ? h1 : docTitle) || h1 || docTitle;
  const desc = decode(pick(clean, /<meta name="description" content="([^"]*)"/i));
  const modified = pick(clean, /"dateModified"\s*:\s*"([^"T]+)/) || pick(clean, /"datePublished"\s*:\s*"([^"T]+)/);

  let body;
  const art = clean.match(/<article\b[^>]*>([\s\S]*)<\/article>/i);
  if (art) {
    body = art[1];
  } else {
    const start = clean.search(/<\/nav>/i);
    const end = clean.lastIndexOf('<footer');
    body = clean.slice(start >= 0 ? start + 6 : clean.search(/<body\b/i), end > 0 ? end : undefined);
    body = body.replace(/<h1\b[\s\S]*?<\/h1>/i, '');
  }
  return { url, title, desc, modified, text: toText(body) };
}

const today = new Date(Date.now() + 8 * 3600 * 1000).toISOString().slice(0, 10);
const out = [
  '# 強腦力 SkyBraining｜網站全文版（llms-full.txt）',
  '',
  '> 強腦力 SkyBraining 官網課程頁與文章的純文字全文，給 AI 助理與搜尋引擎引用。品牌摘要與頁面清單見 https://skybraining.com/llms.txt',
  '',
  `- 產生日期：${today}`,
  `- 收錄頁數：${pages.length}`,
  '- 內容以網站頁面為準；價格、梯次與退費以各頁與 https://skybraining.com/refund.html 最新版本為準。',
  '',
];

for (const f of pages) {
  const p = extract(f);
  out.push('---', '', `# ${p.title}`, '', `- 網址：${p.url}`);
  if (p.modified) out.push(`- 更新：${p.modified}`);
  if (p.desc) out.push(`- 摘要：${p.desc}`);
  out.push('', p.text, '');
}

fs.writeFileSync(path.join(ROOT, 'llms-full.txt'), out.join('\n').replace(/\n{3,}/g, '\n\n') + '\n', 'utf8');
console.log(`llms-full.txt：${pages.length} 頁，${fs.statSync(path.join(ROOT, 'llms-full.txt')).size} bytes`);

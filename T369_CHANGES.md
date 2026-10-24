# T369 心智圖免費課＋T371 網站公告：改動清單（2026-10-25，分支 feat/free-mindmap，本機）

## 新檔
- mindmap-free.html：落地頁（鉤子、三件你會學到、「免費領取」→ login.html?next=watch.html?course=mindmap-free；JSON-LD Course isAccessibleForFree；內鏈 mindmap／kaohsiung）
- lessons/mindmap-free-7q4k/slides.html＋mm-01～31.webp＋mm-blur-59/66/75/86.webp：簡報第 1～58 頁＋4 頁模糊預覽（共 2.12 MB；noindex；沒登入直接開會導回落地頁）
- img-mindmap-free-hero.webp、og-mindmap-free.jpg
- admin-announcements.html：後台公告（新增／編輯／停用、台灣時間、#demo=1 示範模式）
- supabase/sql/2026-10-25_mindmap_free_course.sql：courses 加 mindmap-free（on conflict do nothing）
- supabase/sql/2026-10-25_announcements.sql：announcements 表＋RLS＋初始 10/31 公告
- tools/announcement/inject.js＋snippet.html：公告片段批次插入（SB-ANN 註解包住，前後 node --check）

## 改的檔
- watch.html：HTML 簡報單元（只收 lessons/ 路徑、同網域 iframe）、免費簡報課登入自動開通、GA mindmap_free_slide／mindmap_free_cta、左右鍵轉給簡報、單一簡報單元時播放區全寬
- login.html：next 帶 course=mindmap-free 時顯示 Gmail 提示、Google 鈕加框（本來就排第一）
- courses.html：免費課有 intro_url 時卡片連落地頁「免費領取 →」
- admin-courses.html：儲存時保留 type:'html'／html_url
- admin-landings.html：STATIC_PAGES 加 mindmap-free（pending＝本機）
- admin-*.html（20 頁）：後台導覽加「公告」
- mindmap.html、kaohsiung.html：內鏈 mindmap-free
- vercel.json：/lessons/ 加 X-Robots-Tag noindex；CSP frame-src 加 'self'
- robots.txt（Disallow /lessons/）、sitemap.xml（加 mindmap-free；courses／mindmap／kaohsiung lastmod）、llms.txt、.vercelignore（tools/ 不上線）
- 83 頁公開頁＋登入後頁：SB-ANN 公告片段（member／account／watch 為登入後，其他為進站；跳過 admin*、checkout、success、login、line-callback、funv*、mindmap-trainer-1107、pro-shifu-preview、story-sample）

## 上線前老闆要做
1. Supabase SQL Editor 依序貼 2026-10-25_announcements.sql、2026-10-25_mindmap_free_course.sql。
2. 驗收過再合進 main 部署；上線時 admin-landings 的 mindmap-free 狀態改 live。

## 驗收退回修正（2026-10-25）
- watch.html：播 HTML 簡報時 html 加 class slides-on，外層 html,body overscroll-behavior-x:none（手機往右滑不會被瀏覽器返回手勢帶離教室；影片課不加）；桌機簡報框高度 clamp(420px, 100svh−300px, 640px)，1200×800 首屏看得到完整翻頁列。
- watch.html?preview=mindmap-free：**本機預覽用，上線時不影響**。程式判斷 location.hostname 只有 localhost／127.0.0.1 才成立，不用登入、不讀寫 Supabase（課程資料用頁內一份跟 SQL 相同的設定）；線上網域帶這個參數只會顯示「缺少課程參數」。預覽網址 http://localhost:8081/watch.html?preview=mindmap-free

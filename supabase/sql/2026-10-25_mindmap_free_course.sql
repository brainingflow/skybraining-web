-- ============================================================
-- 強腦力：新增「心智圖免費課」（T369，2026-10-25）
--
-- 做什麼：在 courses 表加一筆免費課 mindmap-free，照「10 倍聯想力」（free-warmup）
--         同一套免費邏輯：price = 0、accent = free、category = brain、上架。
--         課程內容是一份 HTML 簡報（教室 watch.html 第 1 堂直接嵌入），
--         檔案在網站 lessons/mindmap-free-7q4k/slides.html。
--         intro_url 指向落地頁 mindmap-free.html，課程列表那張卡會連過去。
--
-- 怎麼貼：Supabase → SQL Editor → New query → 整段貼上 → Run。
--         看到「Success」就完成了。可以重複執行：這筆已經存在就不動，
--         你在後台「課程管理」改過的名稱、說明不會被蓋掉。
-- 前提：網站要先上線新版 watch.html（認得 HTML 簡報）與 lessons/ 資料夾，
--       不然會員點進教室會看到「即將上線」。
--
-- 會員怎麼拿到這堂課：登入後打開教室就自動開通（寫一筆 enrollments，source = free），
--   跟 10 倍聯想力按「NT$0 免費開通」寫進去的是同一種紀錄。
-- ============================================================

insert into public.courses
  (id, name, subtitle, description, price, level, accent, vimeo_id, is_published, sort_order,
   episodes, note, intro_url, default_ratio, category)
values
  ('mindmap-free',
   '心智圖免費課',
   '免費・58 頁教學簡報',
   '你登入就能看強腦力高雄初階班的心智圖教學簡報前 58 頁：大腦怎麼記東西、大師的筆記、六大規則與五個步驟。',
   0, 0, 'free', null, true, 0,
   '{"v":2,"chapters":[{"title":"第 1 堂","lessons":[{"title":"心智圖，把思考畫出來（教學簡報 58 頁）","type":"html","html_url":"lessons/mindmap-free-7q4k/slides.html","vimeo_id":"","ratio":"16:9","preview":false,"duration":""}]}]}'::jsonb,
   null, 'mindmap-free.html', '16:9', 'brain')
on conflict (id) do nothing;

-- 檢查：應該看到一列 mindmap-free、price 0、is_published true
select id, name, price, is_published, intro_url, episodes->'chapters'->0->'lessons'->0->>'html_url' as html_url
from public.courses where id = 'mindmap-free';

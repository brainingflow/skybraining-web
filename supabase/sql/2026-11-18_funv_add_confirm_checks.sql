-- ============================================================
-- 強腦力：婦女再就業後台「四個確認格」的三個新欄位（T746，2026-11-18）
--
-- 老闆 11/18 原話：
--   「加入申請表、領據、收款、存摺四個確認的格子 重複地幫我注意一下不需要重複」
--   「R127 線上強腦力後台也要一起改」
--
-- 這支做了什麼：
--   在報名表 funv_applications 加三個打勾欄位（是／否，預設「否」）：
--     apply_sent        申請表寄出
--     receipt_sent      領據寄出
--     passbook_checked  存摺（存摺已確認；只是打勾，跟學員上傳的匯款帳簿封面 passbook_path 是兩回事）
--   「收款」不新增欄位：直接用 2026-11-10 那支建好的 leader_paid（就是老師名單頁的「已收款」），
--   後台列表的「收款」格和老師名單頁的「已收款」是同一個欄位，誰勾都一樣。
--   三個新欄位只有後台（admin-funv*.html）看得到、改得到；老師名單頁 funv-team 讀的是 funv_team_roster，
--   本檔沒有改那支函式，所以老師看不到這三格。
--
-- 權限：後台是用管理員登入直接改表（跟標記、備註、上課日期同一條路），
--   沿用 funv_applications.sql 的 admin_update 政策與 table 層級的 grant update，不用另開權限，
--   也不用改任何 Edge Function（報名表 funv-submit 新增資料時這三欄自動是「否」）。
--
-- 怎麼貼：Supabase → SQL Editor → New query → 整段貼上 → Run。
--         看到「Success. No rows returned」就完成了。可以重複執行，不刪資料、不會清掉已經勾的。
--
-- 按 Run 之前：後台列表的「申請表寄出」「領據寄出」「存摺」三格是灰的、表頭寫「待開通」，
--             頁面最上面有一條黃色提示；「收款」格、標記、備註、上課日期、匯出都照常能用。
-- 按 Run 之後：重新整理後台（https://skybraining.com/admin-funv.html），黃色提示消失、三格可以勾，
--             表頭顯示「0/總人數」。隨便勾一格、重新整理，勾還在就是成功；再點一次取消。
--
-- 還原（要整個拿掉時才用；欄位一刪，已經勾的紀錄就沒了）：把下面 4 行去掉開頭的 -- 再 Run
--   alter table public.funv_applications drop column if exists apply_sent,
--     drop column if exists receipt_sent,
--     drop column if exists passbook_checked;
--   notify pgrst, 'reload schema';
--   還原後後台會自動回到「待開通」的樣子，不會壞。
-- ============================================================

alter table public.funv_applications add column if not exists apply_sent       boolean not null default false;
alter table public.funv_applications add column if not exists receipt_sent     boolean not null default false;
alter table public.funv_applications add column if not exists passbook_checked boolean not null default false;

-- 讓 API 立刻認得新欄位，不用等快取自己更新
notify pgrst, 'reload schema';

-- 檢查（選用）：應該列出三列，預設值都是 false
--   select column_name, data_type, column_default from information_schema.columns
--    where table_schema = 'public' and table_name = 'funv_applications'
--      and column_name in ('apply_sent','receipt_sent','passbook_checked');

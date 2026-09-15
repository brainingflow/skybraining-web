-- ============================================================
-- 婦女再就業補助報名表：新增「匯款帳簿封面照片」欄位（選填）
-- 搭配 2026-09-15 更新的 funv-submit（收第三個檔案欄位 passbook）
-- 與 funv-apply*.html（身分證正反面之後多一題，選填）。
--
-- 老闆要做的事：Supabase → SQL Editor → 貼上本檔全部內容 → Run。
-- 可重複執行，不會刪資料；不用重跑 funv_applications.sql（那份已經跑過）。
-- 匯款帳簿封面沿用身分證同一個私有 bucket funv-ids，RLS 與 Storage policy
-- 已經在 funv_applications.sql 第 4、5 段開好（管理員可讀、其餘人一律不行），這裡不用再加。
-- ============================================================

alter table public.funv_applications add column if not exists passbook_path text; -- 匯款帳簿封面：bucket funv-ids 內的路徑，選填，沒上傳就是 null

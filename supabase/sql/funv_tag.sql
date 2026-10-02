-- ============================================================
-- 婦女再就業後台「顏色標記」欄位（後台 admin-funv.html 用）
--
-- 老闆在 Supabase SQL Editor 貼上執行一次；可重複執行（不刪資料、不會清掉已經標好的顏色）。
--
-- tag 只收七個值：none（沒有標記）、red、orange、yellow、green、blue、gray。
-- 畫面上顯示的中文名（不符資格、待補件…）寫在 admin-funv.html 的 TAGS 常數，
-- 改名只改網頁、不用動這裡；要「加新顏色」才要改下面的 check（先 drop constraint 再 add）。
-- 權限沿用 funv_applications.sql 第 2 段的 admin_update 政策，不另開。
-- ============================================================

alter table public.funv_applications add column if not exists tag text not null default 'none';

do $$ begin
  alter table public.funv_applications
    add constraint funv_applications_tag_check
    check ( tag in ('none','red','orange','yellow','green','blue','gray') );
exception when duplicate_object then null; end $$;

create index if not exists funv_applications_tag_idx on public.funv_applications(tag);

-- 讓 API 立刻認得新欄位，不用等快取自己更新
notify pgrst, 'reload schema';

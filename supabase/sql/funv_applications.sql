-- ============================================================
-- 婦女再就業補助：就業技能課程報名表（網頁 funv-apply.html）
-- 搭配 Edge Function: funv-submit（收表單、存照片、寫這張表）
--
-- 老闆要做的兩件事，順序不能反：
--   1) Supabase → SQL Editor → 貼上本檔全部內容 → Run
--      （可重複執行，不刪任何資料；會一併建立私有 bucket funv-ids）
--   2) 終端機在 網頁專案/ 底下執行：supabase functions deploy funv-submit
--      部署完到 Edge Functions → funv-submit → Details，把 Verify JWT 設成 OFF
--      （報名表沒有登入，前端只帶 anon key）
--
-- 身分證照片放在私有 bucket funv-ids，只有 service role 與後台管理員（is_admin，見第 5 段）讀得到；
-- 補助申請完成後請到 Storage 把該筆資料夾整個刪掉（網頁上寫的是「申請後刪除」）。
--
-- 2026-09-14 新增第 5、6 段（後台 admin-funv.html 要用）：第 5 段讓管理員讀得到 funv-ids 的身分證照片，
-- 第 6 段加後台備註欄。**這兩段 2026-09-14 已經在 Supabase 跑過**（pg_policies 查得到 funv_ids_admin_read，
-- note 欄也在），不用再跑一次；本檔仍然可以整份重複執行，不會刪資料。
-- ============================================================

-- 1) 報名資料（30 題）
create table if not exists public.funv_applications (
  id                uuid primary key default gen_random_uuid(),
  created_at        timestamptz not null default now(),
  labor_insurance   text,                      -- Q1  現在有沒有保勞保（工會/電話/開始時間）
  name              text,                      -- Q2  名字
  line_id           text,                      -- Q3  line id（電話也可）
  id_number         text,                      -- Q4  身分證字號
  id_front_path     text,                      -- Q5  身分證正面：bucket funv-ids 內的路徑
  id_back_path      text,                      -- Q6  身分證背面
  birthday          date,                      -- Q7  生日
  mobile            text,                      -- Q8  手機
  address           text,                      -- Q9  通訊地址（政府寄信）
  email             text,                      -- Q10 電子信箱
  education         text,                      -- Q11 最高學歷（學校/科系）
  skills            text,                      -- Q12 專長（選填）
  last_company      text,                      -- Q13 最後工作：公司名稱
  last_title        text,                      -- Q14 最後工作：職稱
  leave_reason      text,                      -- Q15 退出職場背景
  work_start        text,                      -- Q16 最後工作開始時間（YYYY-MM）
  work_end          text,                      -- Q17 最後工作離開時間（YYYY-MM）
  referrer          text,                      -- Q18 邀請人
  course_choice     text,                      -- Q19 選擇課程
  course_reason     text,                      -- Q20 選此課程原因
  target_job        text,                      -- Q21 未來想從事的職業
  job_relevance     text,                      -- Q22 課程與未來就業的關聯性
  after_training    text[] not null default '{}',  -- Q23 結訓後如何運用（可多選）
  family_care       text,                      -- Q24 家庭照護需求如何解決
  self_improvement  text[] not null default '{}',  -- Q25 離開職場期間的自我提升（可多選）
  job_search        text,                      -- Q26 最近的求職經驗
  commute_pref      text,                      -- Q27 理想工作條件（地點）
  work_hours        text,                      -- Q28 理想工時（選填）
  transport         text,                      -- Q29 交通工具（選填）
  confirmed         boolean not null default false, -- Q30 確認事項勾選「是」
  ip                text,
  user_agent        text,
  status            text not null default 'new'     -- new → 聯絡中 → 已送件 → 完成／不符（後台 admin-funv.html 人工改）
);

create index if not exists funv_applications_created_at_idx on public.funv_applications(created_at);
create index if not exists funv_applications_status_idx     on public.funv_applications(status);
create index if not exists funv_applications_ip_idx         on public.funv_applications(ip, created_at);

-- 2) RLS：anon 與一般登入者一律沒有任何權限
-- 註：service role key 呼叫會略過 RLS，funv-submit 用 service role 寫入不受這裡限制。
--     下面只開給管理員看與改狀態，沒有 anon／authenticated 的 policy＝他們什麼都拿不到。
alter table public.funv_applications enable row level security;
do $$ begin
  create policy admin_select_funv_applications on public.funv_applications
    for select using ( public.is_admin() );
exception when duplicate_object then null; end $$;
do $$ begin
  create policy admin_update_funv_applications on public.funv_applications
    for update using ( public.is_admin() ) with check ( public.is_admin() );
exception when duplicate_object then null; end $$;

-- 3) 私有 bucket：身分證照片
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('funv-ids', 'funv-ids', false, 10485760, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

-- 4) Storage policy：只有 service role 進得去（後台管理員另外開在第 5 段）
-- service role 本來就略過 RLS，這條是寫明「除了 service role 沒有人有權限」，避免之後誤開。
do $$ begin
  create policy funv_ids_service_role_only on storage.objects
    for all
    using ( bucket_id = 'funv-ids' and auth.role() = 'service_role' )
    with check ( bucket_id = 'funv-ids' and auth.role() = 'service_role' );
exception
  when duplicate_object then null;
  when insufficient_privilege then
    raise notice 'storage.objects 沒有建立 policy 的權限，略過；funv-ids 是私有 bucket，沒有 policy 時本來就只有 service role 讀得到。';
end $$;

-- 5) Storage policy：管理員可讀 funv-ids
-- 後台 admin-funv.html 的「看身分證正面／背面」是用登入者的身分向 Storage 要一張 5 分鐘的
-- 簽名網址（createSignedUrl），不是走 service role，所以要讓 is_admin() 為真的登入者能 select
-- 這個 bucket 的物件。多條 policy 之間是「或」的關係，不會蓋掉第 4 段那條，anon 依然什麼都拿不到。
do $$ begin
  create policy funv_ids_admin_read on storage.objects
    for select
    using ( bucket_id = 'funv-ids' and public.is_admin() );
exception
  when duplicate_object then null;
  when insufficient_privilege then
    raise notice 'storage.objects 沒有建立 policy 的權限，請改用 Dashboard → Storage → funv-ids → Policies 手動新增一條 SELECT 政策，條件填 public.is_admin()。';
end $$;

-- 6) 後台備註欄
-- admin-funv.html 改狀態時順便寫的備註（打過電話沒接、缺哪份資料、寄件日期…）。
-- 第 1 段的 create table if not exists 對已經存在的表不會補欄位，所以獨立寫一行。
alter table public.funv_applications add column if not exists note text;

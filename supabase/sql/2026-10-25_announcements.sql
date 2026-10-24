-- ============================================================
-- 強腦力：網站公告（T371，2026-10-25）
--
-- 做什麼：建 announcements 表。網站會讀「啟用中、而且在時間內」的公告：
--   進站公告（placement = site）→ 公開頁面載入時跳一次（一位訪客一天最多一次）；
--   登入後公告（placement = login）→ 會員中心、帳號、教室等登入後頁面跳一次（一天一次）；
--   兩者（placement = both）→ 兩邊都會出現（同一天同一則只跳一次）。
--   後台 admin-announcements.html 可以新增、編輯、停用，免費課時間你自己改。
--
-- 怎麼貼：Supabase → SQL Editor → New query → 整段貼上 → Run。
--         看到「Success」就完成了。可以重複執行，不刪資料，第一筆公告也不會重複新增。
-- 前提：admins.sql 已經跑過（public.is_admin() 存在；後台能登入就代表跑過了）。
--
-- 權限：
--   所有人（沒登入也可以）→ 只看得到「啟用、而且現在在開始～結束時間內」的公告。
--   管理員（is_admin）→ 看得到全部（含已停用、已過期），可以新增、修改、刪除。
-- ============================================================

create table if not exists public.announcements (
  id         uuid primary key default gen_random_uuid(),
  title      text not null check (char_length(btrim(title)) between 1 and 40),
  body       text check (body is null or char_length(body) <= 120),
  btn_text   text check (btn_text is null or char_length(btn_text) <= 16),
  link       text check (link is null or (char_length(link) <= 300 and link !~* '^\s*(javascript|data|vbscript):')),
  starts_at  timestamptz not null default now(),
  ends_at    timestamptz not null,
  placement  text not null default 'both' check (placement in ('site', 'login', 'both')),
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint announcements_time_order check (ends_at > starts_at)
);

create index if not exists announcements_live_idx on public.announcements(active, starts_at, ends_at);

alter table public.announcements enable row level security;

-- Supabase 預設把 public 新表的全部權限給 anon／authenticated，先收回再只開需要的
revoke all on public.announcements from anon, authenticated;
grant select on public.announcements to anon, authenticated;
grant insert, update, delete on public.announcements to authenticated;

drop policy if exists announcements_public_read on public.announcements;
create policy announcements_public_read on public.announcements
  for select to anon, authenticated
  using ( active and now() >= starts_at and now() <= ends_at );

drop policy if exists announcements_admin_read on public.announcements;
create policy announcements_admin_read on public.announcements
  for select to authenticated
  using ( coalesce(public.is_admin(), false) );

drop policy if exists announcements_admin_insert on public.announcements;
create policy announcements_admin_insert on public.announcements
  for insert to authenticated
  with check ( coalesce(public.is_admin(), false) );

drop policy if exists announcements_admin_update on public.announcements;
create policy announcements_admin_update on public.announcements
  for update to authenticated
  using ( coalesce(public.is_admin(), false) )
  with check ( coalesce(public.is_admin(), false) );

drop policy if exists announcements_admin_delete on public.announcements;
create policy announcements_admin_delete on public.announcements
  for delete to authenticated
  using ( coalesce(public.is_admin(), false) );

create or replace function public.announcements_touch()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end; $$;

drop trigger if exists announcements_touch on public.announcements;
create trigger announcements_touch before update on public.announcements
  for each row execute function public.announcements_touch();

-- 第一筆公告：10/31 體驗場。報名 10/28 23:59 截止，公告同時結束；額滿提早關時到後台把這則停用。
insert into public.announcements (title, body, btn_text, link, starts_at, ends_at, placement, active)
select '10/31（六）高雄 3 小時體驗場 限時免費',
       '3 小時實體實戰，現場帶你練圖像記憶與心智圖。',
       '免費報名',
       'ad-live.html',
       now(),
       timestamptz '2026-10-28 23:59:00+08',
       'both',
       true
where not exists (select 1 from public.announcements where title = '10/31（六）高雄 3 小時體驗場 限時免費')
  and now() < timestamptz '2026-10-28 23:59:00+08';

-- 檢查：應該看到 10/31 那一筆
select title, placement, active, starts_at, ends_at from public.announcements order by created_at desc;

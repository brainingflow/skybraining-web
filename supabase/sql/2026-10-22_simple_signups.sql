-- ============================================================
-- 強腦力：簡易報名表（只收姓名、電話、地址）（T336，2026-10-22）
--
-- 做什麼：給「只要姓名電話地址」的活動報名頁用，第一個是
--         mindmap-trainer-1107.html（心智圖講師班 11/7 全天）。
--         後台 admin-simple-signups.html 看名單、依活動篩、匯出 CSV、寫備註。
--
-- 為什麼不寫 funv_applications：那張表只開給 Edge Function funv-submit
--   （service role）寫，anon 沒有任何權限；funv-submit 又一定要身分證字號、
--   身分證照片、生日、Email 等 30 題，只填三欄會被擋下來。
--
-- 怎麼貼：Supabase → SQL Editor → New query → 整段貼上 → Run。
--         看到「Success. No rows returned」就完成了。可以重複執行，不刪資料。
-- 前提：admins.sql 已經跑過（public.is_admin() 存在；後台能登入就代表跑過了）。
--
-- 權限：
--   沒登入的人（anon）、一般會員 → 只能「新增」event／name／phone／address 四欄，
--     看不到、改不了任何一筆（包含自己剛送出的）。
--   管理員（is_admin）→ 可以看全部、改 note（備註）與 tag（標記）。
-- ============================================================

create table if not exists public.simple_signups (
  id         uuid primary key default gen_random_uuid(),
  event      text not null check (char_length(btrim(event)) between 1 and 60),
  name       text not null check (char_length(btrim(name)) between 1 and 40),
  phone      text not null check (char_length(btrim(phone)) between 6 and 30),
  address    text not null check (char_length(btrim(address)) between 1 and 200),
  created_at timestamptz not null default now(),
  note       text,
  tag        text
);

create index if not exists simple_signups_event_idx on public.simple_signups(event, created_at desc);

alter table public.simple_signups enable row level security;

-- Supabase 預設把 public 新表的全部權限給 anon／authenticated，先收回再只開需要的欄位，
-- 這樣即使 RLS 放行 insert，也塞不進 note、tag、created_at、id。
revoke all on public.simple_signups from anon, authenticated;
grant insert (event, name, phone, address) on public.simple_signups to anon, authenticated;
grant select on public.simple_signups to authenticated;
grant update (note, tag) on public.simple_signups to authenticated;

drop policy if exists simple_signups_public_insert on public.simple_signups;
create policy simple_signups_public_insert on public.simple_signups
  for insert to anon, authenticated
  with check ( true );

drop policy if exists simple_signups_admin_select on public.simple_signups;
create policy simple_signups_admin_select on public.simple_signups
  for select to authenticated
  using ( coalesce(public.is_admin(), false) );

drop policy if exists simple_signups_admin_update on public.simple_signups;
create policy simple_signups_admin_update on public.simple_signups
  for update to authenticated
  using ( coalesce(public.is_admin(), false) )
  with check ( coalesce(public.is_admin(), false) );

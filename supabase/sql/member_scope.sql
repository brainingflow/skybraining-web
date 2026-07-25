-- ============================================================
-- 強腦力：課程權限「以會員編號為單位」
--
-- 問題：前台原本用 enrollments 直接查「我買了哪些課」，
--       但 enrollments 是綁 auth.users.id，不是綁會員編號。
--       1) 管理員有一條「admin read all enrollments」policy，
--          所以管理員自己的會員中心會把別人的課也算成自己的。
--       2) 未來同一個人如果有多個 auth 帳號（Email／Google／LINE
--          綁在同一個 member_no 底下），課程也應該互通。
--
-- 解法：一律走下面三支 SECURITY DEFINER 函式，範圍固定是
--       「我的會員編號底下的所有 auth 帳號」，跟 member_me()
--       回報的課程數完全一致。
--
-- 不刪除任何資料，可重複執行。
-- ============================================================

-- 1) 我的會員編號底下，所有 auth 帳號的 user_id
create or replace function public.member_user_ids()
returns setof uuid
language sql
security definer
stable
set search_path = public
as $fn$
  select auth.uid()
  where auth.uid() is not null
  union
  select ma2.user_id
    from public.member_accounts ma1
    join public.member_accounts ma2 on ma2.member_no = ma1.member_no
   where ma1.user_id = auth.uid()
$fn$;

-- 2) 我（這個會員編號）已開通的課程 id
create or replace function public.member_course_ids()
returns setof text
language sql
security definer
stable
set search_path = public
as $fn$
  select distinct e.course_id
    from public.enrollments e
   where e.user_id in (select public.member_user_ids())
$fn$;

-- 3) 我（這個會員編號）有沒有某一門課
create or replace function public.member_owns_course(p_course_id text)
returns boolean
language sql
security definer
stable
set search_path = public
as $fn$
  select exists (
    select 1
      from public.enrollments e
     where e.course_id = p_course_id
       and e.user_id in (select public.member_user_ids())
  )
$fn$;

-- 沒有登入時 auth.uid() 是 null，三支函式都會回空／false，
-- 所以不需要另外開 policy，也不會外洩任何人的購買紀錄。

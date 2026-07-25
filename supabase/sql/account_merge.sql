-- ============================================================
-- 強腦力：同一個 Email 的 Google 登入 / Email 密碼登入 自動視為同一帳號
--
-- 為什麼需要：Supabase 在「Email 已驗證」時會自動把 Google 身分掛到同一個
-- 帳號上；但如果帳號是在設定完成前建立的、或 Email 尚未驗證，就會出現
-- 兩筆 auth.users 用同一個 Email。這支程式負責把它們接起來。
--
-- 安全設計：**不刪除任何帳號、不刪除任何資料**。作法是把課程開通紀錄
-- （enrollments）與個人資料互相補齊，讓使用者不管從哪一邊登入，
-- 看到的課程與資料都一樣。全程可重複執行。
--
-- 在 Supabase → SQL Editor 貼上整段執行一次。
-- ============================================================

-- 1) 合併紀錄（稽核用，之後要查是誰跟誰合併的） ---------------
create table if not exists public.account_merges (
  id          bigint generated always as identity primary key,
  email       text not null,
  user_ids    uuid[] not null,
  courses_added int not null default 0,
  merged_at   timestamptz not null default now()
);
alter table public.account_merges enable row level security;
-- 不開 policy：只有下面的 SECURITY DEFINER 函式寫得進去

create index if not exists account_merges_email_idx on public.account_merges (email);

-- 2) 使用者自助合併：登入後前端自動呼叫一次 -------------------
create or replace function public.account_merge_self()
returns json
language plpgsql security definer set search_path = public as $$
declare
  v_uid    uuid;
  v_email  text;
  v_ids    uuid[];
  v_added  int := 0;
  v_n      int;
begin
  v_uid   := auth.uid();
  v_email := lower(btrim(coalesce(auth.jwt()->>'email','')));
  if v_uid is null or v_email = '' then
    return json_build_object('ok', false, 'reason', 'no_session');
  end if;

  -- 找出所有使用同一個 Email 的帳號
  select array_agg(u.id order by u.created_at asc)
    into v_ids
  from auth.users u
  where lower(coalesce(u.email,'')) = v_email;

  v_n := coalesce(array_length(v_ids, 1), 0);

  -- 順手把 profiles.email 補上（有些舊帳號是空的）
  update public.profiles p
     set email = v_email
   where p.id = v_uid and coalesce(p.email,'') = '';

  if v_n <= 1 then
    return json_build_object('ok', true, 'accounts', v_n, 'merged', 0);
  end if;

  -- 課程開通：把所有帳號的課程，補齊到每一個帳號上（只新增、不刪除）
  with all_courses as (
    select distinct e.course_id
    from public.enrollments e
    where e.user_id = any(v_ids)
  ),
  targets as (
    select unnest(v_ids) as uid
  ),
  ins as (
    insert into public.enrollments (user_id, course_id, source)
    select t.uid, a.course_id, 'merge'
    from targets t cross join all_courses a
    where not exists (
      select 1 from public.enrollments e2
      where e2.user_id = t.uid and e2.course_id = a.course_id
    )
    returning 1
  )
  select count(*) into v_added from ins;

  -- 個人資料：用最完整的一筆補齊目前這個帳號的空欄位
  update public.profiles p
     set display_name   = coalesce(nullif(p.display_name,''),   src.display_name),
         child_nickname = coalesce(nullif(p.child_nickname,''), src.child_nickname),
         child_grade    = coalesce(nullif(p.child_grade,''),    src.child_grade)
    from (
      select max(nullif(q.display_name,''))   as display_name,
             max(nullif(q.child_nickname,'')) as child_nickname,
             max(nullif(q.child_grade,''))    as child_grade
      from public.profiles q
      where q.id = any(v_ids)
    ) src
   where p.id = v_uid;

  if v_added > 0 then
    insert into public.account_merges(email, user_ids, courses_added)
    values (v_email, v_ids, v_added);
  end if;

  return json_build_object('ok', true, 'accounts', v_n, 'merged', v_added);
end;
$$;

-- 3) 後台：列出目前有重複 Email 的帳號（給站長檢查用）---------
create or replace function public.admin_duplicate_accounts()
returns table(email text, account_count bigint, providers text, user_ids uuid[], total_courses bigint)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '沒有權限：僅限管理員'; end if;
  return query
  select lower(u.email)::text as email,
         count(*) as account_count,
         (select string_agg(distinct i.provider, ',' order by i.provider)
            from auth.identities i where i.user_id = any(array_agg(u.id))) as providers,
         array_agg(u.id) as user_ids,
         (select count(*) from public.enrollments e where e.user_id = any(array_agg(u.id))) as total_courses
  from auth.users u
  where coalesce(u.email,'') <> ''
  group by lower(u.email)
  having count(*) > 1
  order by count(*) desc;
end;
$$;

-- 4) 後台：手動幫某個 Email 觸發一次合併（同樣不刪資料）-------
create or replace function public.admin_merge_email(p_email text)
returns json
language plpgsql security definer set search_path = public as $$
declare v_email text; v_ids uuid[]; v_added int := 0;
begin
  if not public.is_admin() then raise exception '沒有權限：僅限管理員'; end if;
  v_email := lower(btrim(coalesce(p_email,'')));
  if v_email = '' then raise exception '請輸入 Email'; end if;

  select array_agg(u.id order by u.created_at asc) into v_ids
  from auth.users u where lower(coalesce(u.email,'')) = v_email;

  if coalesce(array_length(v_ids,1),0) <= 1 then
    return json_build_object('ok', true, 'accounts', coalesce(array_length(v_ids,1),0), 'merged', 0);
  end if;

  with all_courses as (
    select distinct e.course_id from public.enrollments e where e.user_id = any(v_ids)
  ),
  targets as (select unnest(v_ids) as uid),
  ins as (
    insert into public.enrollments (user_id, course_id, source)
    select t.uid, a.course_id, 'merge'
    from targets t cross join all_courses a
    where not exists (
      select 1 from public.enrollments e2 where e2.user_id = t.uid and e2.course_id = a.course_id
    )
    returning 1
  )
  select count(*) into v_added from ins;

  if v_added > 0 then
    insert into public.account_merges(email, user_ids, courses_added) values (v_email, v_ids, v_added);
  end if;
  return json_build_object('ok', true, 'accounts', array_length(v_ids,1), 'merged', v_added);
end;
$$;

-- 5) 權限 -----------------------------------------------------
grant execute on function public.account_merge_self()        to authenticated;
grant execute on function public.admin_duplicate_accounts()  to authenticated;
grant execute on function public.admin_merge_email(text)     to authenticated;
revoke all on function public.account_merge_self()       from anon;
revoke all on function public.admin_duplicate_accounts() from anon;
revoke all on function public.admin_merge_email(text)    from anon;

-- ============================================================
-- 另外請在 Supabase 後台開一個開關（治本）：
--   Authentication → Sign In / Providers → 找到
--   「Allow account linking for the same email address」之類的選項並開啟。
-- 開了之後，未來用 Google 登入且 Email 已驗證時，Supabase 會直接把身分
-- 掛在同一個帳號上，根本不會產生第二個帳號。
-- ============================================================

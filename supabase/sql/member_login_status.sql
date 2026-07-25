-- ============================================================
-- 強腦力：修正「Email／密碼登入」綁定狀態誤判
--
-- 問題：用 Google 建立的帳號，之後在 account.html 補設密碼，
--       Supabase 不會新增 email identity，所以 member_me() 從
--       auth.identities 彙整的 providers 裡永遠沒有 'email'，
--       會員中心就一直顯示「未綁定」——但密碼明明登入得了。
--
-- 解法：member_me() 改成「只要這個會員編號底下任何帳號
--       有 Email 也有密碼，providers 就補上 'email'」。
--       後台 admin_members_overview() 也用同一套邏輯。
--
-- 不刪除任何資料，可重複執行。
-- ============================================================

create or replace function public.member_me()
returns json
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid; v_no text; v_email text;
  v_provs text[]; v_accounts int; v_courses int;
  v_line_id text; v_line_name text; v_line_pic text; v_line_at timestamptz;
begin
  v_uid := auth.uid();
  if v_uid is null then
    return json_build_object('ok', false, 'reason', 'no_session');
  end if;

  v_no := public.member_ensure(v_uid);

  select lower(coalesce(u.email,'')) into v_email
    from auth.users u where u.id = v_uid;

  -- 這個會員編號底下所有 auth 帳號的登入方式，全部彙整起來
  select coalesce(array_agg(distinct i.provider), '{}')
    into v_provs
    from auth.identities i
    join public.member_accounts ma on ma.user_id = i.user_id
   where ma.member_no = v_no;

  -- Email／密碼：OAuth 帳號補設密碼「不會」產生 email identity，
  -- 所以直接看有沒有密碼——有 Email 又有密碼，就算已綁定
  if not ('email' = any(coalesce(v_provs, '{}'))) then
    if exists (
      select 1
        from auth.users u2
        join public.member_accounts ma2 on ma2.user_id = u2.id
       where ma2.member_no = v_no
         and coalesce(u2.email, '') <> ''
         and coalesce(u2.encrypted_password, '') <> ''
    ) then
      v_provs := array_append(coalesce(v_provs, '{}'), 'email');
    end if;
  end if;

  select count(*) into v_accounts
    from public.member_accounts where member_no = v_no;

  select count(distinct e.course_id) into v_courses
    from public.enrollments e
    join public.member_accounts ma on ma.user_id = e.user_id
   where ma.member_no = v_no;

  select l.line_user_id, l.display_name, l.picture_url, l.linked_at
    into v_line_id, v_line_name, v_line_pic, v_line_at
    from public.member_line l where l.member_no = v_no limit 1;

  return json_build_object(
    'ok',        true,
    'member_no', v_no,
    'email',     v_email,
    'providers', to_json(coalesce(v_provs,'{}')),
    'accounts',  v_accounts,
    'courses',   v_courses,
    'line', case when v_line_id is null then null else json_build_object(
      'display_name', v_line_name,
      'picture_url',  v_line_pic,
      'linked_at',    v_line_at
    ) end
  );
end;
$$;

-- 後台總覽也用同一套判斷（identities ∪ 有密碼就補 email）
create or replace function public.admin_members_overview()
returns table(
  member_no text, primary_email text, accounts bigint,
  providers text, has_line boolean, line_name text,
  courses bigint, created_at timestamptz
)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '沒有權限：僅限管理員'; end if;
  return query
  select m.member_no,
         m.primary_email,
         (select count(*) from public.member_accounts ma where ma.member_no = m.member_no) as accounts,
         (select string_agg(distinct s.p, ',' order by s.p) from (
            select i.provider as p
              from auth.identities i
              join public.member_accounts ma2 on ma2.user_id = i.user_id
             where ma2.member_no = m.member_no
            union
            select 'email'
              from auth.users u2
              join public.member_accounts ma4 on ma4.user_id = u2.id
             where ma4.member_no = m.member_no
               and coalesce(u2.email,'') <> ''
               and coalesce(u2.encrypted_password,'') <> ''
          ) s) as providers,
         exists(select 1 from public.member_line l where l.member_no = m.member_no) as has_line,
         (select l2.display_name from public.member_line l2 where l2.member_no = m.member_no limit 1) as line_name,
         (select count(distinct e.course_id)
            from public.enrollments e
            join public.member_accounts ma3 on ma3.user_id = e.user_id
           where ma3.member_no = m.member_no) as courses,
         m.created_at
    from public.members m
   order by m.member_no asc;
end;
$$;

-- create or replace 會保留原本的執行權限設定，不用重新 grant。

-- ============================================================
-- 強腦力：會員編號（member_no）+ Email / Google / LINE 三合一綁定
--
-- 目標：同一個人不管用 Email 密碼、Google、還是 LINE 登入，
--       都對應到「同一個會員編號」，而且他在會員中心看得到自己
--       綁了哪幾種登入方式。
--
-- 設計：
--   members          一個「人」= 一個 member_no（SB00001…）
--   member_accounts  auth.users.id → member_no（Email / Google 走這裡）
--   member_line      LINE userId   → member_no（LINE 走這裡）
--
-- 安全：三張表都開 RLS 且不開任何 policy，前端一律走下面的
--       SECURITY DEFINER 函式。不刪除任何既有資料，可重複執行。
-- ============================================================

-- 1) 編號流水號 ------------------------------------------------
create sequence if not exists public.member_no_seq start 1;

-- 2) 資料表 ----------------------------------------------------
create table if not exists public.members (
  member_no     text primary key,
  primary_email text,
  created_at    timestamptz not null default now()
);
alter table public.members enable row level security;

create table if not exists public.member_accounts (
  user_id   uuid primary key,
  member_no text not null references public.members(member_no) on update cascade on delete cascade,
  email     text,
  linked_at timestamptz not null default now()
);
alter table public.member_accounts enable row level security;
create index if not exists member_accounts_no_idx on public.member_accounts (member_no);

create table if not exists public.member_line (
  line_user_id text primary key,
  member_no    text not null references public.members(member_no) on update cascade on delete cascade,
  display_name text,
  picture_url  text,
  email        text,
  linked_at    timestamptz not null default now()
);
alter table public.member_line enable row level security;
create index if not exists member_line_no_idx on public.member_line (member_no);

-- 3) 核心：取得（或建立）某個 auth 帳號的會員編號 --------------
--    同一個 Email 的其他帳號如果已經有編號，一律沿用同一個編號。
create or replace function public.member_ensure(p_uid uuid)
returns text
language plpgsql security definer set search_path = public as $$
declare v_email text; v_no text;
begin
  if p_uid is null then return null; end if;

  select member_no into v_no from public.member_accounts where user_id = p_uid;
  if v_no is not null then return v_no; end if;

  select lower(btrim(coalesce(u.email,''))) into v_email
    from auth.users u where u.id = p_uid;

  -- 同 Email 已經有編號 → 沿用（這就是「三種登入同一個編號」的關鍵）
  if coalesce(v_email,'') <> '' then
    select ma.member_no into v_no
      from public.member_accounts ma
      join auth.users u2 on u2.id = ma.user_id
     where lower(coalesce(u2.email,'')) = v_email
     limit 1;
  end if;

  if v_no is null then
    v_no := 'SB' || lpad(nextval('public.member_no_seq')::text, 5, '0');
    insert into public.members(member_no, primary_email)
    values (v_no, nullif(v_email,''))
    on conflict (member_no) do nothing;
  end if;

  insert into public.member_accounts(user_id, member_no, email)
  values (p_uid, v_no, nullif(v_email,''))
  on conflict (user_id) do update
    set member_no = excluded.member_no,
        email     = coalesce(excluded.email, public.member_accounts.email);

  -- 補一下主要 Email
  update public.members m
     set primary_email = nullif(v_email,'')
   where m.member_no = v_no and coalesce(m.primary_email,'') = '';

  return v_no;
end;
$$;

-- 4) 前台：我的會員編號 + 我綁了哪幾種登入方式 -----------------
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

-- 5) 前台：解除 LINE 綁定（本人操作）---------------------------
create or replace function public.member_unbind_line()
returns json
language plpgsql security definer set search_path = public as $$
declare v_uid uuid; v_no text; v_n int;
begin
  v_uid := auth.uid();
  if v_uid is null then raise exception '請先登入'; end if;
  v_no := public.member_ensure(v_uid);
  delete from public.member_line where member_no = v_no;
  get diagnostics v_n = row_count;
  return json_build_object('ok', true, 'removed', v_n);
end;
$$;

-- 6) 給 Edge Function 用：綁定 LINE / 用 LINE 找回會員 ---------
--    只允許 service_role 呼叫（Edge Function 才有 service key）。
--    前端拿不到 service key，所以無法偽造別人的 LINE userId。
create or replace function public.member_bind_line(
  p_user_id      uuid,
  p_line_user_id text,
  p_display_name text default null,
  p_picture_url  text default null,
  p_email        text default null
) returns json
language plpgsql security definer set search_path = public as $$
declare v_role text; v_no text; v_old text;
begin
  v_role := coalesce(current_setting('request.jwt.claims', true)::json->>'role', '');
  if v_role <> 'service_role' then raise exception '沒有權限'; end if;
  if p_user_id is null or coalesce(btrim(p_line_user_id),'') = '' then
    raise exception '參數不完整';
  end if;

  v_no := public.member_ensure(p_user_id);

  -- 這個 LINE 之前綁在別的會員身上 → 改綁到現在這個人（以本人操作為準）
  select member_no into v_old from public.member_line where line_user_id = p_line_user_id;

  insert into public.member_line(line_user_id, member_no, display_name, picture_url, email)
  values (p_line_user_id, v_no, nullif(btrim(coalesce(p_display_name,'')),''),
          nullif(btrim(coalesce(p_picture_url,'')),''),
          nullif(lower(btrim(coalesce(p_email,''))),''))
  on conflict (line_user_id) do update
    set member_no    = excluded.member_no,
        display_name = coalesce(excluded.display_name, public.member_line.display_name),
        picture_url  = coalesce(excluded.picture_url,  public.member_line.picture_url),
        email        = coalesce(excluded.email,        public.member_line.email),
        linked_at    = now();

  return json_build_object('ok', true, 'member_no', v_no,
                           'moved_from', case when v_old is not null and v_old <> v_no then v_old else null end);
end;
$$;

--    LINE 登入時：用 LINE userId 反查這個人的 Email（好發登入連結）
create or replace function public.member_lookup_line(p_line_user_id text)
returns json
language plpgsql security definer set search_path = public as $$
declare v_role text; v_no text; v_email text;
begin
  v_role := coalesce(current_setting('request.jwt.claims', true)::json->>'role', '');
  if v_role <> 'service_role' then raise exception '沒有權限'; end if;

  select member_no into v_no from public.member_line where line_user_id = p_line_user_id;
  if v_no is null then
    return json_build_object('ok', false, 'reason', 'not_bound');
  end if;

  -- 挑這個會員編號底下最早、且有 Email 的帳號
  select lower(u.email) into v_email
    from public.member_accounts ma
    join auth.users u on u.id = ma.user_id
   where ma.member_no = v_no and coalesce(u.email,'') <> ''
   order by u.created_at asc
   limit 1;

  if v_email is null then
    return json_build_object('ok', false, 'reason', 'no_email');
  end if;
  return json_build_object('ok', true, 'member_no', v_no, 'email', v_email);
end;
$$;

-- 7) 後台：會員編號總覽 ---------------------------------------
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
         (select string_agg(distinct i.provider, ',' order by i.provider)
            from auth.identities i
            join public.member_accounts ma2 on ma2.user_id = i.user_id
           where ma2.member_no = m.member_no) as providers,
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

-- 8) 回填：現有帳號全部配一個會員編號 --------------------------
do $$
declare r record;
begin
  for r in select id from auth.users order by created_at asc loop
    perform public.member_ensure(r.id);
  end loop;
end $$;

-- 9) 權限 ------------------------------------------------------
grant execute on function public.member_me()            to authenticated;
grant execute on function public.member_unbind_line()   to authenticated;
grant execute on function public.admin_members_overview() to authenticated;
revoke all on function public.member_me()          from anon;
revoke all on function public.member_unbind_line() from anon;
revoke all on function public.member_bind_line(uuid,text,text,text,text) from anon, authenticated;
revoke all on function public.member_lookup_line(text)                   from anon, authenticated;
grant execute on function public.member_bind_line(uuid,text,text,text,text) to service_role;
grant execute on function public.member_lookup_line(text)                   to service_role;

-- 完成。前台呼叫 supabase.rpc('member_me') 就能拿到會員編號與綁定狀態。

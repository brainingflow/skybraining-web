-- ============================================================
-- 強腦力：婦女再就業「團隊報名名單」（T313，2026-10-18）
--
-- 做什麼：每個團隊負責人用 LINE 登入 funv-team.html，只看得到自己團隊的
--         報名者「名字、推薦人、顏色標記、狀態、報名時間」，其他欄位
--         （手機、LINE ID、身分證、地址、Email…）一律拿不到。
--         誰是哪個團隊的負責人，由後台「管理員」分頁的「團隊負責人」區塊
--         用會員編號綁定。
--
-- 怎麼貼：Supabase → SQL Editor → New query → 整段貼上 → Run。
--         看到「Success. No rows returned」就完成了。可以重複執行，不刪資料。
--
-- 前提：member_ids.sql、funv_applications.sql、funv_tag.sql、admins.sql
--       都已經跑過（後台婦女再就業報名頁能用、LINE 登入能用，就代表跑過了）。
--
-- 團隊怎麼對：報名表第 18 題「邀請人」（funv_applications.referrer）
--   去掉前後空白後，跟綁定的團隊名「完全一樣」才算這個團隊。
--   固定值：蘇姐團隊、珠珠姐、羅總團隊、龎芸芸、林慧雯、美莉記者團隊。
--
-- 會員編號 → 帳號：同一個會員編號可能有好幾個登入帳號（Email、Google、LINE），
--   綁定時記其中一個帳號，查名單時用「會員編號」比對，所以不管負責人用哪種
--   方式登入都看得到。
-- ============================================================

-- 1) 綁定表：哪個帳號是哪個團隊的負責人 ------------------------
create table if not exists public.funv_team_leads (
  user_id    uuid not null references auth.users(id) on delete cascade,
  team       text not null check (btrim(team) <> ''),
  note       text,
  created_at timestamptz not null default now(),
  primary key (user_id, team)
);
alter table public.funv_team_leads enable row level security;

drop policy if exists funv_team_leads_self_select on public.funv_team_leads;
create policy funv_team_leads_self_select on public.funv_team_leads
  for select using ( user_id = auth.uid() or public.is_admin() );

drop policy if exists funv_team_leads_admin_insert on public.funv_team_leads;
create policy funv_team_leads_admin_insert on public.funv_team_leads
  for insert with check ( public.is_admin() );

drop policy if exists funv_team_leads_admin_update on public.funv_team_leads;
create policy funv_team_leads_admin_update on public.funv_team_leads
  for update using ( public.is_admin() ) with check ( public.is_admin() );

drop policy if exists funv_team_leads_admin_delete on public.funv_team_leads;
create policy funv_team_leads_admin_delete on public.funv_team_leads
  for delete using ( public.is_admin() );

grant select, insert, update, delete on public.funv_team_leads to authenticated;

-- 2) 負責人看自己團隊的名單（只回六個欄位）----------------------
--    p_team：管理員可指定任一團隊；一般負責人帶了也只會在自己的團隊裡篩
--    沒登入、沒綁團隊 → 回 0 列
--    綁了團隊但還沒有人報名 → 該團隊回一列、只有 team 有值（名單頁用來顯示「0 人」，跟「沒綁團隊」分得開）
create or replace function public.funv_team_roster(p_team text default null)
returns table(name text, referrer text, tag text, status text, created_at timestamptz, team text)
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid; v_team text;
begin
  v_uid  := auth.uid();
  if v_uid is null then return; end if;
  v_team := nullif(btrim(coalesce(p_team, '')), '');

  if v_team is not null and public.is_admin() then
    return query
    select a.name, a.referrer, a.tag, a.status, a.created_at, v_team
      from public.funv_applications a
     where btrim(coalesce(a.referrer, '')) = v_team
     order by a.created_at desc;
    return;
  end if;

  return query
  with my_users as (
    select v_uid as user_id
    union
    select ma2.user_id
      from public.member_accounts ma
      join public.member_accounts ma2 on ma2.member_no = ma.member_no
     where ma.user_id = v_uid
  ), my_teams as (
    select distinct btrim(l.team) as team
      from public.funv_team_leads l
     where l.user_id in (select user_id from my_users)
       and (v_team is null or btrim(l.team) = v_team)
  )
  select a.name, a.referrer, a.tag, a.status, a.created_at, t.team
    from my_teams t
    left join public.funv_applications a on btrim(coalesce(a.referrer, '')) = t.team
   order by t.team asc, a.created_at desc;
end;
$$;

-- 3) 後台：目前的綁定清單 ----------------------------------------
create or replace function public.funv_team_leads_admin_list()
returns table(user_id uuid, team text, note text, display_name text, member_no text, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not coalesce(public.is_admin(), false) then raise exception '沒有權限：僅限管理員'; end if;
  return query
  select l.user_id, l.team, l.note,
         (select ml.display_name from public.member_line ml
           where ml.member_no = ma.member_no order by ml.linked_at desc limit 1),
         ma.member_no,
         l.created_at
    from public.funv_team_leads l
    left join public.member_accounts ma on ma.user_id = l.user_id
   order by l.team asc, l.created_at asc;
end;
$$;

-- 4) 後台：用會員編號綁定團隊 ------------------------------------
--    記的帳號跟 LINE 登入用的帳號一致（這個編號底下最早、有 Email 的帳號），
--    沒有就用這個編號底下最早的帳號
create or replace function public.funv_team_lead_bind(p_member_no text, p_team text, p_note text default null)
returns json
language plpgsql security definer set search_path = public as $$
declare v_no text; v_team text; v_uid uuid; v_name text;
begin
  if not coalesce(public.is_admin(), false) then raise exception '沒有權限：僅限管理員'; end if;
  v_no   := upper(btrim(coalesce(p_member_no, '')));
  v_team := btrim(coalesce(p_team, ''));
  if v_no = ''   then raise exception '請輸入會員編號'; end if;
  if v_team = '' then raise exception '請選擇團隊'; end if;

  select ma.user_id into v_uid
    from public.member_accounts ma
    join auth.users u on u.id = ma.user_id
   where ma.member_no = v_no
   order by (coalesce(u.email, '') <> '') desc, u.created_at asc
   limit 1;
  if v_uid is null then raise exception '找不到會員編號 %（請對方先用 LINE 登入一次 skybraining.com）', v_no; end if;

  insert into public.funv_team_leads(user_id, team, note)
  values (v_uid, v_team, nullif(btrim(coalesce(p_note, '')), ''))
  on conflict (user_id, team) do update set note = excluded.note;

  select ml.display_name into v_name
    from public.member_line ml where ml.member_no = v_no order by ml.linked_at desc limit 1;

  return json_build_object('ok', true, 'user_id', v_uid, 'member_no', v_no, 'team', v_team, 'display_name', v_name);
end;
$$;

-- 5) 後台：解除綁定 ----------------------------------------------
create or replace function public.funv_team_lead_unbind(p_user_id uuid, p_team text)
returns json
language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  if not coalesce(public.is_admin(), false) then raise exception '沒有權限：僅限管理員'; end if;
  delete from public.funv_team_leads where user_id = p_user_id and team = p_team;
  get diagnostics v_n = row_count;
  return json_build_object('ok', true, 'removed', v_n);
end;
$$;

-- 6) 權限：只有登入的人叫得動（函式裡再檢查是不是負責人／管理員）---
revoke all on function public.funv_team_roster(text)                  from public, anon;
revoke all on function public.funv_team_leads_admin_list()            from public, anon;
revoke all on function public.funv_team_lead_bind(text, text, text)   from public, anon;
revoke all on function public.funv_team_lead_unbind(uuid, text)       from public, anon;
grant execute on function public.funv_team_roster(text)                to authenticated;
grant execute on function public.funv_team_leads_admin_list()          to authenticated;
grant execute on function public.funv_team_lead_bind(text, text, text) to authenticated;
grant execute on function public.funv_team_lead_unbind(uuid, text)     to authenticated;

notify pgrst, 'reload schema';

-- 檢查（選用）：
--   select proname from pg_proc where proname like 'funv_team%';

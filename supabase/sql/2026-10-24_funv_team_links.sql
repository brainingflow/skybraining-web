-- ============================================================
-- 強腦力：婦女再就業「團隊專屬連結」（T352，2026-10-24）
--
-- 做什麼：每個團隊一條專屬連結 https://skybraining.com/funv-team.html?t=<開通碼>。
--         負責人點開、登入，就自動綁成那個團隊的負責人，看得到自己團隊報名者的
--         「名字、手機、推薦人、顏色標記、狀態、報名時間」；
--         身分證、地址、Email、LINE ID 一律不給。
--         連結在後台「管理員」分頁的「團隊負責人」區塊產生、複製、重新產生。
--
-- 怎麼貼：Supabase → SQL Editor → New query → 整段貼上 → Run。
--         看到「Success. No rows returned」就完成了。可以重複執行，不刪資料。
--
-- 前提：2026-10-18_funv_team_leads.sql 已經跑過（後台有「團隊負責人」區塊、
--       funv-team.html 看得到名單，就代表跑過了）。
--
-- 注意：這份會換掉名單函式 funv_team_roster（多回手機）。以後要重貼請貼這份，
--       不要再貼 2026-10-18 那份（舊的回傳欄位不同，貼了只會報錯，不會壞資料）。
--
-- 重新產生連結：舊連結馬上不能再開通新的人；已經開通的人照樣看得到，
--   要停權請在後台「團隊負責人」清單按「解除」。
-- 管理員自己點連結：只顯示那個團隊的名單，不會被綁進負責人清單。
-- ============================================================

-- 1) 連結表：一個團隊一條（team 是主鍵），token 是開通碼 ---------------
create table if not exists public.funv_team_links (
  team       text primary key check (btrim(team) <> ''),
  token      text not null unique check (length(token) >= 32),
  created_at timestamptz not null default now(),
  revoked_at timestamptz
);
alter table public.funv_team_links enable row level security;

drop policy if exists funv_team_links_admin_select on public.funv_team_links;
create policy funv_team_links_admin_select on public.funv_team_links
  for select using ( coalesce(public.is_admin(), false) );

drop policy if exists funv_team_links_admin_insert on public.funv_team_links;
create policy funv_team_links_admin_insert on public.funv_team_links
  for insert with check ( coalesce(public.is_admin(), false) );

drop policy if exists funv_team_links_admin_update on public.funv_team_links;
create policy funv_team_links_admin_update on public.funv_team_links
  for update using ( coalesce(public.is_admin(), false) ) with check ( coalesce(public.is_admin(), false) );

drop policy if exists funv_team_links_admin_delete on public.funv_team_links;
create policy funv_team_links_admin_delete on public.funv_team_links
  for delete using ( coalesce(public.is_admin(), false) );

-- Supabase 預設把新表的全部權限（含不受 RLS 管的 TRUNCATE）給 anon／authenticated，先收回再只給四種
revoke all on public.funv_team_links from public, anon, authenticated;
grant select, insert, update, delete on public.funv_team_links to authenticated;

-- 2) 後台：產生／重新產生某團隊的連結（管理員），回傳新的開通碼 ----------
--    重新產生＝換一組新的碼，舊連結立刻失效（已開通的負責人不受影響）
create or replace function public.funv_team_link_issue(p_team text)
returns text
language plpgsql security definer set search_path = public as $$
declare v_team text; v_token text;
begin
  if not coalesce(public.is_admin(), false) then raise exception '沒有權限：僅限管理員'; end if;
  v_team := btrim(coalesce(p_team, ''));
  if v_team = '' then raise exception '請選擇團隊'; end if;

  -- gen_random_uuid() 是 Postgres 內建的強亂數，不用另外裝 pgcrypto；兩組串起來 64 碼
  v_token := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');

  insert into public.funv_team_links(team, token)
  values (v_team, v_token)
  on conflict (team) do update
    set token = excluded.token, created_at = now(), revoked_at = null;

  return v_token;
end;
$$;

-- 3) 負責人：帶連結開通（funv-team.html 登入後呼叫），回傳團隊名 ----------
--    連結無效、已重新產生、已停用 → 報錯（訊息直接顯示給對方看）
create or replace function public.funv_team_claim(p_token text)
returns text
language plpgsql security definer set search_path = public as $$
declare v_uid uuid; v_token text; v_team text; v_no text;
begin
  v_uid := auth.uid();
  if v_uid is null then raise exception '請先登入再開通'; end if;

  v_token := btrim(coalesce(p_token, ''));
  if v_token <> '' then
    select l.team into v_team
      from public.funv_team_links l
     where l.token = v_token and l.revoked_at is null;
  end if;
  if v_team is null then
    raise exception '這個連結已經失效或不完整，請向 Sky 老師要新的連結';
  end if;

  -- 管理員本來就能看任何團隊，點連結只是確認，不綁進負責人清單
  if coalesce(public.is_admin(), false) then return v_team; end if;

  -- 同一個會員編號（不管用哪種方式登入）已經是這團的負責人，就不再多綁一列
  v_no := public.member_ensure(v_uid);
  if not exists (
    select 1
      from public.funv_team_leads fl
      left join public.member_accounts ma on ma.user_id = fl.user_id
     where btrim(fl.team) = v_team
       and (fl.user_id = v_uid or (v_no is not null and ma.member_no = v_no))
  ) then
    insert into public.funv_team_leads(user_id, team, note)
    values (v_uid, v_team, '專屬連結開通')
    on conflict (user_id, team) do nothing;
  end if;

  return v_team;
end;
$$;

-- 4) 名單：多回手機 phone，其他照舊（身分證、地址、Email、LINE ID 不回）----
--    回傳欄位變了，Postgres 不能直接 create or replace，要先 drop 再建
drop function if exists public.funv_team_roster(text);
create or replace function public.funv_team_roster(p_team text default null)
returns table(name text, phone text, referrer text, tag text, status text, created_at timestamptz, team text)
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid; v_team text;
begin
  v_uid  := auth.uid();
  if v_uid is null then return; end if;
  v_team := nullif(btrim(coalesce(p_team, '')), '');

  if v_team is not null and coalesce(public.is_admin(), false) then
    return query
    select a.name, a.mobile, a.referrer, a.tag, a.status, a.created_at, v_team
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
  select a.name, a.mobile, a.referrer, a.tag, a.status, a.created_at, t.team
    from my_teams t
    left join public.funv_applications a on btrim(coalesce(a.referrer, '')) = t.team
   order by t.team asc, a.created_at desc;
end;
$$;

-- 5) 權限：只有登入的人叫得動（函式裡再檢查是不是管理員／負責人）---------
revoke all on function public.funv_team_link_issue(text) from public, anon;
revoke all on function public.funv_team_claim(text)      from public, anon;
revoke all on function public.funv_team_roster(text)     from public, anon;
grant execute on function public.funv_team_link_issue(text) to authenticated;
grant execute on function public.funv_team_claim(text)      to authenticated;
grant execute on function public.funv_team_roster(text)     to authenticated;

notify pgrst, 'reload schema';

-- 檢查（選用）：
--   select team, left(token, 8) || '…' as token, created_at, revoked_at
--     from public.funv_team_links order by team;

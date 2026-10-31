-- ============================================================
-- 強腦力：婦女再就業「團隊專屬連結」加「依課程」模式（T425，2026-10-30）
--
-- 做什麼：課程領導人（緹林、史麗仙、芳香協會、小可）各有一條專屬連結，
--         點開、登入後看到的是「報名自己那門課」的全部學員
--         （名字、手機、推薦人、顏色標記、狀態、報名時間），不分是誰邀請的；
--         身分證、地址、Email、LINE ID 一樣一律不給。
--         一般團隊（蘇姐團隊、珠珠姐…）照舊：只看邀請人是自己團隊的報名者。
--         連結在後台「管理員」分頁的「團隊負責人 → 各團隊專屬連結」產生，
--         標「依課程」的四列就是這四位。
--
-- 怎麼貼：Supabase → SQL Editor → New query → 整段貼上 → Run。
--         看到「Success. No rows returned」就完成了。可以重複執行，不刪資料。
--
-- 前提：2026-10-18_funv_team_leads.sql、2026-10-24_funv_team_links.sql 都已經跑過
--       （後台看得到「各團隊專屬連結」表，就代表跑過了）。
--
-- 注意：以後如果又重貼 2026-10-24 那份，貼完一定要再貼這份一次，
--       不然「依課程」會失效、產生連結會報錯。
--
-- 課程怎麼對：報名表第 19 題「選擇課程」（funv_applications.course_choice）
--   裡面「有包含」這條連結的課程關鍵字，就算這門課的學員。
--   關鍵字跟後台婦女再就業各課程分頁用的一樣：
--     緹林（泰式高床）→ 初階泰式高床按摩
--     史麗仙（頌缽）  → 缽動筋膜調理
--     芳香協會（精油按摩）→ 芳香精油
--     小可（牛角筋絡）→ 牛角筋絡調理
-- ============================================================

-- 1) 連結表加一欄：課程關鍵字（空的＝一般團隊，照邀請人比對）-------------
alter table public.funv_team_links add column if not exists course_kw text;

-- 2) 後台：產生／重新產生連結，可以帶課程關鍵字 ---------------------------
--    多了一個參數，Postgres 會當成另一支函式，所以先把只有一個參數的舊版拿掉
--    重新產生時沒帶關鍵字，就沿用這條連結原本的關鍵字（不會不小心變回一般團隊）
drop function if exists public.funv_team_link_issue(text);
create or replace function public.funv_team_link_issue(p_team text, p_course_kw text default null)
returns text
language plpgsql security definer set search_path = public as $$
declare v_team text; v_kw text; v_token text;
begin
  if not coalesce(public.is_admin(), false) then raise exception '沒有權限：僅限管理員'; end if;
  v_team := btrim(coalesce(p_team, ''));
  if v_team = '' then raise exception '請選擇團隊'; end if;
  v_kw := nullif(btrim(coalesce(p_course_kw, '')), '');

  -- gen_random_uuid() 是 Postgres 內建的強亂數，不用另外裝 pgcrypto；兩組串起來 64 碼
  v_token := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');

  insert into public.funv_team_links(team, token, course_kw)
  values (v_team, v_token, v_kw)
  on conflict (team) do update
    set token = excluded.token, created_at = now(), revoked_at = null,
        course_kw = coalesce(excluded.course_kw, public.funv_team_links.course_kw);

  return v_token;
end;
$$;

-- 3) 名單：依課程的團隊改用「選擇課程」比對，多回 course_kw 給名單頁顯示「依課程」 ----
--    回傳欄位變了，Postgres 不能直接 create or replace，要先 drop 再建
drop function if exists public.funv_team_roster(text);
create or replace function public.funv_team_roster(p_team text default null)
returns table(name text, phone text, referrer text, tag text, status text, created_at timestamptz, team text, course_kw text)
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid; v_team text; v_kw text;
begin
  v_uid  := auth.uid();
  if v_uid is null then return; end if;
  v_team := nullif(btrim(coalesce(p_team, '')), '');

  if v_team is not null and coalesce(public.is_admin(), false) then
    select nullif(btrim(coalesce(k.course_kw, '')), '') into v_kw
      from public.funv_team_links k where k.team = v_team;
    return query
    select a.name, a.mobile, a.referrer, a.tag, a.status, a.created_at, v_team, v_kw
      from public.funv_applications a
     where case when v_kw is null then btrim(coalesce(a.referrer, '')) = v_team
                else strpos(coalesce(a.course_choice, ''), v_kw) > 0 end
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
    select distinct btrim(l.team) as tm
      from public.funv_team_leads l
     where l.user_id in (select user_id from my_users)
       and (v_team is null or btrim(l.team) = v_team)
  ), my_teams_kw as (
    -- 連結停用（重新產生）不影響已開通的人，所以這裡不看 revoked_at
    select t.tm, nullif(btrim(coalesce(k.course_kw, '')), '') as kw
      from my_teams t
      left join public.funv_team_links k on k.team = t.tm
  )
  select a.name, a.mobile, a.referrer, a.tag, a.status, a.created_at, t.tm, t.kw
    from my_teams_kw t
    left join public.funv_applications a
      on case when t.kw is null then btrim(coalesce(a.referrer, '')) = t.tm
              else strpos(coalesce(a.course_choice, ''), t.kw) > 0 end
   order by t.tm asc, a.created_at desc;
end;
$$;

-- 4) 權限：只有登入的人叫得動（函式裡再檢查是不是管理員／負責人）---------
revoke all on function public.funv_team_link_issue(text, text) from public, anon;
revoke all on function public.funv_team_roster(text)           from public, anon;
grant execute on function public.funv_team_link_issue(text, text) to authenticated;
grant execute on function public.funv_team_roster(text)           to authenticated;

notify pgrst, 'reload schema';

-- 檢查（選用）：
--   select team, course_kw, left(token, 8) || '…' as token, created_at, revoked_at
--     from public.funv_team_links order by team;
--   四門課的舊報名對不對得到（每門課應該都有數字）：
--   select k.kw, count(a.*) from (values ('初階泰式高床按摩'),('缽動筋膜調理'),('芳香精油'),('牛角筋絡調理')) k(kw)
--     left join public.funv_applications a on strpos(coalesce(a.course_choice, ''), k.kw) > 0 group by k.kw;

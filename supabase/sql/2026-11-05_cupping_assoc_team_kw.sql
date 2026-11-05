-- ============================================================
-- 強腦力：課程領導人專屬連結支援多關鍵字（T627 建、T630 改，2026-11-05）
--
-- 老闆 11/05 定：芳香與溫罐名單分開，芳香協會連結只看芳香精油。
--   溫罐名單（舊補助班「張玉諳【溫罐調理實戰班】」＋新協會班「台灣全人芳香身心養生協會【溫罐調理實戰班】」）
--   用關鍵字「溫罐調理實戰班」比對，兩種都涵蓋。
--
-- 做什麼：
--   1) 課程關鍵字可以放好幾個，用 | 隔開（例：甲課|乙課），報名課程含其中任何一個就算。
--      沒有 | 的舊關鍵字照舊，一個字串比對。
--   2) 芳香協會（精油按摩）那條連結的關鍵字如果被改成過「芳香精油|協會【溫罐調理」
--      （T627 舊版這份 SQL 跑過，或在 T627 版後台按過重新產生），改回「芳香精油」；沒改過就不動。
--
-- 怎麼貼：Supabase → SQL Editor → New query → 整段貼上 → Run。
--         看到「Success. No rows returned」就完成了。可以重複執行，不刪資料。
--
-- 順序：網頁現在沒有任何連結用 |，先上線網頁、晚點再跑這份都可以。
--       以後要讓某條連結看多門課（kw 帶 |），一定要先跑這份，不然那條連結名單會是 0 人。
--
-- 前提：2026-10-30_funv_team_course.sql 已經跑過（後台「各團隊專屬連結」有「依課程」標籤就代表跑過）。
--       以後如果重貼 2026-10-30 那份，貼完要再貼這份一次，不然多關鍵字會失效。
-- ============================================================

-- 1) 比對小工具：報名課程有沒有包含關鍵字裡任何一段 ------------------------
create or replace function public.funv_course_kw_hit(p_choice text, p_kw text)
returns boolean
language sql immutable set search_path = public as $$
  select exists (
    select 1
      from unnest(string_to_array(coalesce(p_kw, ''), '|')) as k(x)
     where btrim(k.x) <> ''
       and strpos(coalesce(p_choice, ''), btrim(k.x)) > 0
  );
$$;

-- 2) 名單：跟 2026-10-30 版一樣，只把 strpos(...) 換成上面的小工具 -------------
--    回傳欄位沒變，可以直接 create or replace
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
                else public.funv_course_kw_hit(a.course_choice, v_kw) end
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
              else public.funv_course_kw_hit(a.course_choice, t.kw) end
   order by t.tm asc, a.created_at desc;
end;
$$;

-- 3) 芳香協會連結如果被改成含溫罐，改回只看芳香精油（沒改過就不會動到任何一列）----
update public.funv_team_links
   set course_kw = '芳香精油'
 where team = '芳香協會（精油按摩）'
   and course_kw = '芳香精油|協會【溫罐調理';

-- 4) 權限：跟 2026-10-30 版一樣 ------------------------------------------------
revoke all on function public.funv_course_kw_hit(text, text) from public, anon;
grant execute on function public.funv_course_kw_hit(text, text) to authenticated;
revoke all on function public.funv_team_roster(text) from public, anon;
grant execute on function public.funv_team_roster(text) to authenticated;

notify pgrst, 'reload schema';

-- 檢查（選用）：
--   select team, course_kw from public.funv_team_links where team = '芳香協會（精油按摩）';
--   select public.funv_course_kw_hit('台灣全人芳香身心養生協會【溫罐調理實戰班】', '芳香精油');          -- false
--   select public.funv_course_kw_hit('芳香精油按摩【技能培訓班】', '芳香精油');                        -- true
--   select public.funv_course_kw_hit('台灣全人芳香身心養生協會【溫罐調理實戰班】', '溫罐調理實戰班');    -- true
--   select public.funv_course_kw_hit('張玉諳【溫罐調理實戰班】', '溫罐調理實戰班');                      -- true
--   select public.funv_course_kw_hit('芳香精油按摩【技能培訓班】', '甲課|芳香精油');                   -- true（多關鍵字）

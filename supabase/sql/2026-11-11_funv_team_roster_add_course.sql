-- ============================================================
-- 強腦力：老師名單 funv_team_roster 多回「報名課程」course_choice（T656 v3，2026-11-11）
--
-- 為什麼：團隊長的學生常分散在不同課，名單「報名情況」要看得到課名才能追蹤。
-- 做什麼：funv_team_roster 回傳最後多一欄 course_choice（報名表第 19 題課程名原文），
--         其他欄位、名單範圍、權限、search_path 跟 2026-11-10_funv_class_date_leader_note.sql 完全一樣；
--         身分證、地址、Email、LINE ID、後台備註一樣不回。
--
-- 怎麼貼：Supabase → SQL Editor → New query → 整段貼上 → Run。可以重複執行，不動任何資料。
-- 前提：2026-11-10_funv_class_date_leader_note.sql 已經跑過（那份現在也已同步成含 course_choice 的版本，重跑那份不會把這欄蓋掉）。
-- 空窗：這份沒跑時，新版名單頁拿不到 course_choice 就只是不顯示課名；舊版名單頁不讀這欄，多一欄也不影響。
--
-- 回滾（拿掉課名欄）：先 drop function if exists public.funv_team_roster(text);
--   再把 2026-11-10 那份檔案「4) 名單」段裡的 , course_choice text 與兩處 , a.course_choice 刪掉後只跑那一段＋第 6 段權限。
-- ============================================================

-- 名單：回傳欄位變了，Postgres 不能直接 create or replace，要先 drop 再建
--    回傳欄位變了，Postgres 不能直接 create or replace，要先 drop 再建
drop function if exists public.funv_team_roster(text);
create or replace function public.funv_team_roster(p_team text default null)
returns table(name text, phone text, referrer text, tag text, status text, created_at timestamptz, team text, course_kw text,
              id uuid, class_date text, leader_note text, leader_note_updated_at timestamptz, leader_paid boolean, course_choice text)
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
    select a.name, a.mobile, a.referrer, a.tag, a.status, a.created_at, v_team, v_kw,
           a.id, a.class_date, a.leader_note, a.leader_note_updated_at, a.leader_paid, a.course_choice
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
  select a.name, a.mobile, a.referrer, a.tag, a.status, a.created_at, t.tm, t.kw,
         a.id, a.class_date, a.leader_note, a.leader_note_updated_at, a.leader_paid, a.course_choice
    from my_teams_kw t
    left join public.funv_applications a
      on case when t.kw is null then btrim(coalesce(a.referrer, '')) = t.tm
              else public.funv_course_kw_hit(a.course_choice, t.kw) end
   order by t.tm asc, a.created_at desc;
end;
$$;


revoke all on function public.funv_team_roster(text) from public, anon;
grant execute on function public.funv_team_roster(text) to authenticated;

notify pgrst, 'reload schema';

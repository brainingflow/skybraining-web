-- ============================================================
-- 強腦力：婦女再就業「上課日期」＋「老師備註」＋「已收款」（T656，2026-11-10）
--
-- 老闆 11/10 原話：
--   「我說我要在後台，在學生檔案上面新增上課日期」
--   「我需要讓老師 看到的學生後台資料 可以輸入備註」
--   「團隊長、老師，可以看到他學生的名字，然後可以在學生名字上輸入備註並且儲存 還有一個已收款的欄位，可以打勾」
--
-- 做什麼：
--   1) 報名表 funv_applications 加欄位：
--        class_date  上課日期（自由文字，例「12/12」「11/21-22」，最多 100 字）
--        leader_note 老師備註（老師名單頁 funv-team 可看可改，最多 500 字）
--        leader_paid 已收款（打勾＝true，預設 false）
--      另加 leader_note_updated_at／leader_note_by（上課日期或老師備註被改時）、
--      leader_paid_at／leader_paid_by（已收款被改時），自動記下時間與改的人。
--   2) 老師名單 funv_team_roster 多回：id、class_date、leader_note、leader_note_updated_at、leader_paid、course_choice（報名課程，11/11 加，同 2026-11-11_funv_team_roster_add_course.sql）。
--      身分證、地址、Email、LINE ID、後台「備註」（note）一律不回，跟以前一樣。
--   3) 新函式（老師用）：
--        funv_team_set_class_info(id, 上課日期, 老師備註)  —— 備註旁的「儲存」
--        funv_team_set_paid(id, true/false)                —— 已收款勾選框，勾了就存
--      兩支都只改自己那幾欄，名單範圍跟 funv_team_roster 同一套
--      （一般團隊＝邀請人是自己團隊；課程領導人＝報名課程含關鍵字）。管理員可改任何一筆。
--   後台 admin-funv*.html 用原本的管理員權限（funv_applications.sql 的 admin_update 政策）直接改，不另開。
--
-- 怎麼貼：Supabase → SQL Editor → New query → 整段貼上 → Run。
--         看到「Success. No rows returned」就完成了。可以重複執行，不刪資料。
--
-- 前提：2026-10-30_funv_team_course.sql 已經跑過（後台「各團隊專屬連結」有「依課程」標籤就代表跑過）。
--       本檔已經內含 2026-11-05_cupping_assoc_team_kw.sql 的比對小工具（多關鍵字 |），
--       那份有沒有跑過都可以直接跑本檔。
--
-- 注意：以後如果又重貼 2026-10-24、2026-10-30 或 2026-11-05 那幾份（都會換掉名單函式），
--       貼完一定要再貼這份一次，不然老師頁的上課日期、備註、已收款會讀不到。
--
-- 最後面第 7 段「把後台備註裡的上課日期抽出來當初稿」預設是註解，不會執行；
-- 要用時看該段說明，先跑預覽、確認抽得對再跑寫入。
--
-- 回滾（要整個拿掉時才用）：
--   第一步：把下面 6 行去掉開頭的 -- 再 Run
--     drop function if exists public.funv_team_set_class_info(uuid, text, text);
--     drop function if exists public.funv_team_set_paid(uuid, boolean);
--     drop function if exists public.funv_team_can_edit(uuid);
--     drop trigger  if exists funv_applications_class_info_stamp on public.funv_applications;
--     drop function if exists public.funv_applications_class_info_stamp();
--     drop function if exists public.funv_team_roster(text);
--   第二步：重貼 2026-11-05_cupping_assoc_team_kw.sql 整份 Run（名單函式回到不含新欄位的舊版；
--           第一步沒先 drop 名單函式，這一步會報「cannot change return type」）。
--   第三步（選用，欄位一刪，填過的上課日期、老師備註、已收款就沒了；只拿掉功能可以不刪欄位）：
--     alter table public.funv_applications drop constraint if exists funv_applications_class_date_len,
--       drop constraint if exists funv_applications_leader_note_len,
--       drop column if exists class_date, drop column if exists leader_note,
--       drop column if exists leader_note_updated_at, drop column if exists leader_note_by,
--       drop column if exists leader_paid, drop column if exists leader_paid_at, drop column if exists leader_paid_by;
-- ============================================================

-- 1) 報名表加欄位 -----------------------------------------------------------
alter table public.funv_applications add column if not exists class_date             text;
alter table public.funv_applications add column if not exists leader_note            text;
alter table public.funv_applications add column if not exists leader_note_updated_at timestamptz;
alter table public.funv_applications add column if not exists leader_note_by         uuid;
alter table public.funv_applications add column if not exists leader_paid            boolean not null default false;
alter table public.funv_applications add column if not exists leader_paid_at         timestamptz;
alter table public.funv_applications add column if not exists leader_paid_by         uuid;

-- 字數上限也擋在資料庫：後台是直接改表，不經過第 5 段的函式
do $$ begin
  alter table public.funv_applications
    add constraint funv_applications_class_date_len check ( class_date is null or char_length(class_date) <= 100 );
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.funv_applications
    add constraint funv_applications_leader_note_len check ( leader_note is null or char_length(leader_note) <= 500 );
exception when duplicate_object then null; end $$;

-- 2) 有變就記下時間與改的人（後台直接改、老師用函式改都會記）------------------
create or replace function public.funv_applications_class_info_stamp()
returns trigger
language plpgsql set search_path = public as $$
begin
  if new.class_date is distinct from old.class_date or new.leader_note is distinct from old.leader_note then
    new.leader_note_updated_at := now();
    new.leader_note_by := auth.uid();
  end if;
  if new.leader_paid is distinct from old.leader_paid then
    new.leader_paid_at := now();
    new.leader_paid_by := auth.uid();
  end if;
  return new;
end;
$$;

drop trigger if exists funv_applications_class_info_stamp on public.funv_applications;
create trigger funv_applications_class_info_stamp
  before update on public.funv_applications
  for each row execute function public.funv_applications_class_info_stamp();

-- 3) 比對小工具（跟 2026-11-05 那份一字不差；重跑不影響）--------------------
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

-- 4) 名單：跟 2026-11-05 版一樣，只多回 id、上課日期、老師備註、老師備註更新時間、已收款、報名課程（2026-11-11 加）----
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

-- 5) 老師能不能改這位學員：管理員全可；其他人看名單範圍（跟第 4 段同一套）-----------
--    只給第 5a、5b 兩支函式內部用，不開給前端直接叫
create or replace function public.funv_team_can_edit(p_id uuid)
returns boolean
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid; v_ok boolean;
begin
  v_uid := auth.uid();
  if v_uid is null or p_id is null then return false; end if;
  if coalesce(public.is_admin(), false) then
    return exists (select 1 from public.funv_applications a where a.id = p_id);
  end if;
  with my_users as (
    select v_uid as user_id
    union
    select ma2.user_id
      from public.member_accounts ma
      join public.member_accounts ma2 on ma2.member_no = ma.member_no
     where ma.user_id = v_uid
  ), my_teams_kw as (
    select distinct btrim(l.team) as tm, nullif(btrim(coalesce(k.course_kw, '')), '') as kw
      from public.funv_team_leads l
      left join public.funv_team_links k on k.team = btrim(l.team)
     where l.user_id in (select user_id from my_users)
  )
  select exists (
    select 1
      from my_teams_kw t
      join public.funv_applications a
        on a.id = p_id
       and case when t.kw is null then btrim(coalesce(a.referrer, '')) = t.tm
                else public.funv_course_kw_hit(a.course_choice, t.kw) end
  ) into v_ok;
  return coalesce(v_ok, false);
end;
$$;

-- 5a) 老師改上課日期與老師備註（funv-team.html 備註旁的「儲存」）-------------------
--     只動 class_date、leader_note 兩欄；空白字串存成 null（＝未填）。回傳改完的值給頁面顯示。
create or replace function public.funv_team_set_class_info(p_id uuid, p_class_date text, p_leader_note text)
returns table(id uuid, class_date text, leader_note text, leader_note_updated_at timestamptz)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare v_cd text; v_ln text;
begin
  if auth.uid() is null then raise exception '請先登入再儲存'; end if;
  if p_id is null then raise exception '缺學員編號，請重新整理再試'; end if;

  v_cd := nullif(btrim(coalesce(p_class_date, '')), '');
  v_ln := nullif(btrim(coalesce(p_leader_note, '')), '');
  if char_length(coalesce(v_cd, '')) > 100 then raise exception '上課日期最多 100 字'; end if;
  if char_length(coalesce(v_ln, '')) > 500 then raise exception '備註最多 500 字'; end if;

  if not public.funv_team_can_edit(p_id) then raise exception '沒有權限：這位學員不在你的名單裡'; end if;

  return query
  update public.funv_applications a
     set class_date = v_cd, leader_note = v_ln
   where a.id = p_id
  returning a.id, a.class_date, a.leader_note, a.leader_note_updated_at;
end;
$$;

-- 5b) 老師勾／取消「已收款」（funv-team.html 名字旁的勾選框，勾了就存）---------------
--     只動 leader_paid 一欄。回傳改完的值。
create or replace function public.funv_team_set_paid(p_id uuid, p_paid boolean)
returns table(id uuid, leader_paid boolean, leader_paid_at timestamptz)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
begin
  if auth.uid() is null then raise exception '請先登入再儲存'; end if;
  if p_id is null or p_paid is null then raise exception '缺學員編號，請重新整理再試'; end if;
  if not public.funv_team_can_edit(p_id) then raise exception '沒有權限：這位學員不在你的名單裡'; end if;

  return query
  update public.funv_applications a
     set leader_paid = p_paid
   where a.id = p_id
  returning a.id, a.leader_paid, a.leader_paid_at;
end;
$$;

-- 6) 權限：只有登入的人叫得動（函式裡再檢查是不是管理員／負責人）；權限小工具不開給前端 ----
revoke all on function public.funv_course_kw_hit(text, text)                from public, anon;
revoke all on function public.funv_team_roster(text)                        from public, anon;
revoke all on function public.funv_team_set_class_info(uuid, text, text)    from public, anon;
revoke all on function public.funv_team_set_paid(uuid, boolean)             from public, anon;
revoke all on function public.funv_team_can_edit(uuid)                      from public, anon, authenticated;
grant execute on function public.funv_course_kw_hit(text, text)             to authenticated;
grant execute on function public.funv_team_roster(text)                     to authenticated;
grant execute on function public.funv_team_set_class_info(uuid, text, text) to authenticated;
grant execute on function public.funv_team_set_paid(uuid, boolean)          to authenticated;

notify pgrst, 'reload schema';

-- 檢查（選用）：
--   select column_name from information_schema.columns
--    where table_name = 'funv_applications' and column_name in ('class_date','leader_note','leader_note_updated_at','leader_note_by','leader_paid','leader_paid_at','leader_paid_by');
--   select proname from pg_proc where proname in ('funv_team_roster','funv_team_set_class_info','funv_team_set_paid','funv_team_can_edit');

-- ============================================================
-- 7) （選用，預設不執行）把後台備註裡的上課日期抽出來，當「上課日期」初稿
--
--   規則（寧可漏抓、不要抓錯）：
--     - 只看「上課日期」還是空的那幾筆，已經有填的一筆都不動。
--     - 後台原本的「備註」（note）只讀不改。
--     - 只抽「日期前面緊貼課程詞」的寫法，例：「短影音12/12」→ 12/12、「上課 11/21-22」→ 11/21-22。
--       課程詞：上課、開課、課程日期、短影音、心智圖、咖啡、按摩、牛角、造型、包租、溫罐、頌缽、缽動、芳香、精油、美容、中餐、成交、泰式。
--       「11/10課程送審」這種日期在前、後面接送審／送件的，不會被抽到（它是送件日，不是上課日）。
--     - 同一筆抽到兩個以上：寫成「短影音 12/12、心智圖 1/5」把課程詞留著；只抽到一個就只寫日期。
--     - 抽不到的維持空白，請助理在後台手動補。
--
--   用法：先只跑 7a 預覽（去掉 7a 每行開頭的 --），看「抽到」那欄對不對；
--         對的話再跑 7b 寫入。跑完後台「上課日期」篩選就看得到。
-- ============================================================

-- 7a) 預覽：不寫入，只列出會填什麼
-- with m as (
--   select a.id, a.name, a.note, r.g, r.ord
--     from public.funv_applications a
--     cross join lateral regexp_matches(a.note,
--       '(上課日期|課程日期|上課|開課|短影音|心智圖|咖啡|按摩|牛角|造型|包租|溫罐|頌缽|缽動|芳香|精油|美容|中餐|成交|泰式)[[:space:]:：]*([0-9]{1,2}/[0-9]{1,2}(?:[-~～][0-9]{1,2}(?:/[0-9]{1,2})?)?)',
--       'g') with ordinality as r(g, ord)
--    where a.class_date is null and coalesce(a.note, '') <> ''
-- ), agg as (
--   select id, name, note, count(*) as n,
--          string_agg(g[2], '、' order by ord) as dates_only,
--          string_agg(g[1] || ' ' || g[2], '、' order by ord) as with_kw
--     from m group by id, name, note
-- )
-- select name, note as 後台備註, case when n = 1 then dates_only else with_kw end as 抽到
--   from agg order by name;

-- 7b) 寫入：只填 class_date 是空的，原備註不動（跟 7a 同一套規則）
-- with m as (
--   select a.id, r.g, r.ord
--     from public.funv_applications a
--     cross join lateral regexp_matches(a.note,
--       '(上課日期|課程日期|上課|開課|短影音|心智圖|咖啡|按摩|牛角|造型|包租|溫罐|頌缽|缽動|芳香|精油|美容|中餐|成交|泰式)[[:space:]:：]*([0-9]{1,2}/[0-9]{1,2}(?:[-~～][0-9]{1,2}(?:/[0-9]{1,2})?)?)',
--       'g') with ordinality as r(g, ord)
--    where a.class_date is null and coalesce(a.note, '') <> ''
-- ), agg as (
--   select id, count(*) as n,
--          string_agg(g[2], '、' order by ord) as dates_only,
--          string_agg(g[1] || ' ' || g[2], '、' order by ord) as with_kw
--     from m group by id
-- )
-- update public.funv_applications a
--    set class_date = left(case when agg.n = 1 then agg.dates_only else agg.with_kw end, 100)
--   from agg
--  where a.id = agg.id and a.class_date is null;

-- ============================================================
-- 強腦力：新朋友直接用 LINE 註冊（T202，2026-10-05）
--
-- 做什麼：以前沒綁過 LINE 的人按「使用 LINE 繼續」會被擋下來
--         （畫面寫「這個 LINE 還沒有綁定會員」）。這支 SQL 加兩個
--         給 Edge Function line-auth 用的函式，line-auth 遇到沒綁過的
--         LINE 就自動建會員、綁上這個 LINE，直接登入。
--
-- 怎麼貼：Supabase → SQL Editor → New query → 整段貼上 → Run。
--         看到「Success. No rows returned」就完成了。
--         要先跑這支，再更新 line-auth 程式碼。
--         （順序反了也不會壞：新朋友會照舊看到「還沒有綁定」。）
--
-- 前提：member_ids.sql 已經跑過（LINE 登入現在能用，就代表跑過了）。
-- 安全：不刪任何資料、可以重複執行。兩個新函式只有 Edge Function
--       （service_role）叫得動，網頁前端叫不動。
--
-- 資料放哪：
--   LINE userId、顯示名稱、頭像 → member_line（line_user_id 是主鍵，
--     同一個 LINE 只會有一筆，所以不會建出第二個帳號）
--   LINE 有給 Email → 用 LINE 的 Email 開帳號
--   LINE 沒給 Email → 用佔位信箱 line_<24 碼英數>@members.skybraining.com，
--     並在 members.email_placeholder 標 true（＝這個會員還沒填 Email）
--   LINE 的 Email 已經是別的會員在用 → 不建帳號，請他用 Email／Google
--     登入後到會員中心綁 LINE（既有的綁定流程）
-- ============================================================

-- 1) 旗標：true ＝ 這個會員的 Email 是佔位信箱（還沒填真的 Email）
alter table public.members
  add column if not exists email_placeholder boolean not null default false;

-- 2) 查某個 Email 有沒有帳號在用；有的話，是不是「同一個 LINE 先前註冊到一半」留下的
--    p_marker 是 line-auth 用 LINE userId 算出來的記號，建帳號時寫進 app_metadata.line_signup
--    （app_metadata 只有 service_role 改得到，使用者自己改不了，所以能拿來認帳號）
create or replace function public.member_line_email_owner(p_email text, p_marker text)
returns json
language plpgsql security definer set search_path = public as $$
declare v_role text; v_email text; v_marker text; v_id uuid; v_mark text;
begin
  v_role := coalesce(current_setting('request.jwt.claims', true)::json->>'role', '');
  if v_role <> 'service_role' then raise exception '沒有權限'; end if;

  v_email  := lower(btrim(coalesce(p_email, '')));
  v_marker := btrim(coalesce(p_marker, ''));
  if v_email = '' or v_marker = '' then raise exception '參數不完整'; end if;

  select u.id, u.raw_app_meta_data->>'line_signup'
    into v_id, v_mark
    from auth.users u
   where lower(coalesce(u.email, '')) = v_email
   order by ((u.raw_app_meta_data->>'line_signup') is not distinct from v_marker) desc,
            u.created_at asc
   limit 1;

  if v_id is null then
    return json_build_object('ok', true, 'exists', false);
  end if;
  if v_mark is not distinct from v_marker then
    return json_build_object('ok', true, 'exists', true, 'line_owned', true, 'user_id', v_id);
  end if;
  return json_build_object('ok', true, 'exists', true, 'line_owned', false);
end;
$$;

-- 3) LINE 註冊建出來的帳號：配會員編號、綁上這個 LINE
--    同一個 LINE 同時兩個請求進來時，用交易鎖排隊；第二個看到已綁好就回 created=false，不建第二筆
create or replace function public.member_line_signup(
  p_user_id           uuid,
  p_line_user_id      text,
  p_marker            text,
  p_display_name      text    default null,
  p_picture_url       text    default null,
  p_email             text    default null,
  p_email_placeholder boolean default false
) returns json
language plpgsql security definer set search_path = public as $$
declare v_role text; v_no text; v_mark text; v_email text; v_n int;
begin
  v_role := coalesce(current_setting('request.jwt.claims', true)::json->>'role', '');
  if v_role <> 'service_role' then raise exception '沒有權限'; end if;
  if p_user_id is null or coalesce(btrim(p_line_user_id), '') = ''
     or coalesce(btrim(p_marker), '') = '' then
    raise exception '參數不完整';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('member_line:' || p_line_user_id, 0));

  -- 已經綁好了（另一個請求先完成，或剛好用綁定流程綁走）→ 不建第二筆，回那個會員
  select member_no into v_no from public.member_line where line_user_id = p_line_user_id;
  if v_no is null then
    -- 只綁 line-auth 為這個 LINE 建的帳號，避免把 LINE 綁到別人身上
    select u.raw_app_meta_data->>'line_signup', lower(u.email)
      into v_mark, v_email
      from auth.users u where u.id = p_user_id;
    if v_mark is distinct from btrim(p_marker) or coalesce(v_email, '') = '' then
      return json_build_object('ok', false, 'reason', 'not_line_signup');
    end if;

    v_no := public.member_ensure(p_user_id);

    insert into public.member_line(line_user_id, member_no, display_name, picture_url, email)
    values (p_line_user_id, v_no,
            nullif(btrim(coalesce(p_display_name, '')), ''),
            nullif(btrim(coalesce(p_picture_url, '')), ''),
            nullif(lower(btrim(coalesce(p_email, ''))), ''))
    on conflict (line_user_id) do nothing;
    get diagnostics v_n = row_count;

    if v_n = 1 then
      if coalesce(p_email_placeholder, false) then
        update public.members set email_placeholder = true where member_no = v_no;
      end if;

      -- 會員中心的「嗨，○○！」讀 profiles.display_name，空的就補 LINE 顯示名稱
      if coalesce(btrim(p_display_name), '') <> '' then
        begin
          update public.profiles set display_name = btrim(p_display_name)
           where id = p_user_id and coalesce(display_name, '') = '';
        exception when undefined_table or undefined_column then null;
        end;
      end if;

      return json_build_object('ok', true, 'created', true, 'member_no', v_no, 'email', v_email,
                               'email_placeholder', coalesce(p_email_placeholder, false));
    end if;

    select member_no into v_no from public.member_line where line_user_id = p_line_user_id;
  end if;

  -- 跟 member_lookup_line 一樣：挑這個會員編號底下最早、且有 Email 的帳號來登入
  select lower(u.email) into v_email
    from public.member_accounts ma
    join auth.users u on u.id = ma.user_id
   where ma.member_no = v_no and coalesce(u.email, '') <> ''
   order by u.created_at asc
   limit 1;
  if v_email is null then
    return json_build_object('ok', false, 'reason', 'no_email');
  end if;
  return json_build_object('ok', true, 'created', false, 'member_no', v_no, 'email', v_email);
end;
$$;

-- 4) 權限：只給 Edge Function（service_role）
revoke all on function public.member_line_email_owner(text, text) from public, anon, authenticated;
revoke all on function public.member_line_signup(uuid, text, text, text, text, text, boolean) from public, anon, authenticated;
grant execute on function public.member_line_email_owner(text, text) to service_role;
grant execute on function public.member_line_signup(uuid, text, text, text, text, text, boolean) to service_role;

-- 跑完可以用這兩行確認（選填）：
--   select column_name from information_schema.columns where table_name = 'members' and column_name = 'email_placeholder';
--   select proname from pg_proc where proname in ('member_line_email_owner', 'member_line_signup');
-- 第一行回 1 列、第二行回 2 列就對了。

-- ============================================================
-- 強腦力後台「課程管理」：欄位 + RPC + 就業力課程搬入資料庫
-- 2026-07-26。可重複執行，不刪任何資料。
-- ============================================================

-- 1) courses 加欄位
alter table public.courses add column if not exists intro_url text;
alter table public.courses add column if not exists default_ratio text not null default '16:9';
alter table public.courses add column if not exists category text not null default 'brain';

-- 2) price 改為可空（null = 洽詢制，如就業力實體課）
do $$ begin
  alter table public.courses alter column price drop not null;
exception when others then null; end $$;

-- 3) 管理員 RPC：列出所有課程（含未上架）
create or replace function public.admin_list_courses()
returns setof public.courses
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '沒有權限：僅限管理員'; end if;
  return query select * from public.courses order by sort_order asc, created_at asc;
end;
$$;

-- 4) 管理員 RPC：新增 / 更新課程（jsonb 進，整列回）
create or replace function public.admin_upsert_course(p jsonb)
returns public.courses
language plpgsql security definer set search_path = public as $$
declare
  src public.courses;
  r   public.courses;
begin
  if not public.is_admin() then raise exception '沒有權限：僅限管理員'; end if;
  if coalesce(trim(p->>'id'),'') = '' then raise exception '缺少課程代號 id'; end if;
  if not ((p->>'id') ~ '^[a-z0-9][a-z0-9-]{1,48}$') then
    raise exception '課程代號只能用小寫英文、數字與 -（2~49 字）';
  end if;
  src := jsonb_populate_record(null::public.courses, p);
  insert into public.courses as c
    (id, name, subtitle, description, price, level, accent, note,
     vimeo_id, episodes, is_published, sort_order, intro_url, default_ratio, category)
  values
    (src.id, coalesce(src.name,''), src.subtitle, src.description, src.price,
     coalesce(src.level,1), coalesce(src.accent,'amber'), src.note,
     src.vimeo_id, src.episodes, coalesce(src.is_published,false),
     coalesce(src.sort_order,50), src.intro_url,
     coalesce(src.default_ratio,'16:9'), coalesce(src.category,'brain'))
  on conflict (id) do update set
    name          = excluded.name,
    subtitle      = excluded.subtitle,
    description   = excluded.description,
    price         = excluded.price,
    level         = excluded.level,
    accent        = excluded.accent,
    note          = excluded.note,
    vimeo_id      = excluded.vimeo_id,
    episodes      = excluded.episodes,
    is_published  = excluded.is_published,
    sort_order    = excluded.sort_order,
    intro_url     = excluded.intro_url,
    default_ratio = excluded.default_ratio,
    category      = excluded.category
  returning * into r;
  return r;
end;
$$;

-- 5) 就業力三堂課搬入資料庫（已存在就跳過）
insert into public.courses
  (id, name, subtitle, description, price, level, accent, is_published, sort_order, intro_url, category)
values
  ('pro-sales','百億成交技術','把「成交」變成可複製的技術','成交不是靠天分或話術，而是一套能拆解、練習、複製的流程。從建立信任、挖掘需求到收單追單，把每一步變成穩定可執行的系統。',null,1,'crimson',true,101,'course-pro-sales.html','career'),
  ('pro-style','整體造型設計','從個人形象到整體造型的系統方法','造型不只是穿搭，而是結合風格、體型、色彩與場合的設計。建立一套能幫自己、也能幫客戶打造整體形象的專業方法。',null,1,'plum',true,102,'course-pro-style.html','career'),
  ('pro-aivideo','AI短影音實戰','用 AI 工具快速產出吸睛短影音','短影音是這個時代最強的曝光工具。用最新 AI 工具，從腳本、生成、剪輯到發布導流，用最少時間做出能吸睛、能帶客戶的短影音。',null,1,'techblue',true,103,'course-pro-aivideo.html','career')
on conflict (id) do nothing;

-- 6) 既有課程補 intro_url（讓課程卡「了解課程」走資料庫欄位）
update public.courses set intro_url='course-memory.html'          where id='super-memory'        and intro_url is null;
update public.courses set intro_url='course-thinking.html'        where id='super-thinking'      and intro_url is null;
update public.courses set intro_url='course-strong-thinking.html' where id='strong-thinking-basic' and intro_url is null;
update public.courses set intro_url='course-onsite-basic.html'    where id='onsite-basic'        and intro_url is null;
update public.courses set intro_url='course-onsite-advanced.html' where id='onsite-advanced'     and intro_url is null;
update public.courses set intro_url='course-bundle.html'          where id='bundle-all'          and intro_url is null;

-- 驗證
select id, name, category, price, accent, is_published, sort_order, intro_url from public.courses order by sort_order;

-- 7) 管理員可讀全部課程（含草稿）——讓草稿能先在觀看頁測試
do $$ begin
  create policy admin_read_all_courses on public.courses for select using ( public.is_admin() );
exception when duplicate_object then null; end $$;

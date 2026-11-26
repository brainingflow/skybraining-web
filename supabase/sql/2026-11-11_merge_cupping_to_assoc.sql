-- ============================================================
-- 強腦力：婦女再就業「張玉諳溫罐」併入「協會溫罐」（T659，2026-11-11）
--
-- 老闆 11/11 原話：「張玉諳溫罐合併至協會的溫罐 以協會溫罐為主」
--                  「張玉諳溫罐刪除，並且從網頁中全數更正，學生資料要完整移動至協會溫罐」
--
-- 做什麼：報名表 funv_applications 的「選擇課程」（course_choice）裡，
--   舊補助班課名「張玉諳【溫罐調理實戰班】」一律改成協會班課名「台灣全人芳香身心養生協會【溫罐調理實戰班】」。
--   只改 course_choice 這一欄；名字、身分證、狀態、標記、備註、上課日期、老師備註、已收款通通不動，
--   所以「學生資料完整搬過去」＝同一筆報名表直接歸到協會班，後台協會溫罐頁就看得到。
--
-- 課名怎麼存：每張報名表的 course_choice 是一段文字（報名頁 data-fixed-value 或單選值），
--   目前沒有多選課。保險起見用「只換掉張玉諳那一段」的寫法：萬一某筆是好幾門課串在一起，
--   其他課的字不會被動到。
--
-- 怎麼跑（三步，都在 Supabase → SQL Editor）：
--   第 1 步：只跑「1) 預覽」那段（反白後 Run），看清單是不是你要搬的那些人、改完的課名對不對。
--   第 2 步：整份 Run。會先把原課名存進備份表 funv_cupping_merge_backup，再改課名，最後列出改了哪些。
--           可以重複執行：已經搬過的不會再被改，備份表也不會重複寫。
--   第 3 步（選用）：跑最後「檢查」那兩行，確認張玉諳舊課名剩 0 筆。
--
-- 還原（要退回時，把「還原」段去掉開頭的 -- 再 Run）：用備份表把原課名寫回去。
--
-- 順序：網頁（後台協會溫罐頁的關鍵字已改成「溫罐調理實戰班」）先上線或後上線都可以；
--       這份跑之前，新舊兩種課名在協會溫罐頁都看得到。課程領導人「張玉諳（溫罐調理）」連結的
--       關鍵字也是「溫罐調理實戰班」，搬移前後都看得到全部溫罐學生，不用改。
-- ============================================================

-- 1) 預覽：哪些報名表會被搬、搬完長怎樣（不寫入）--------------------------------
select a.id, a.name, a.created_at, a.course_choice as 原課名,
       regexp_replace(a.course_choice, '張玉諳【溫罐調理[^】]*】', '台灣全人芳香身心養生協會【溫罐調理實戰班】', 'g') as 改成
  from public.funv_applications a
 where a.course_choice like '%張玉諳【溫罐%'
 order by a.created_at;

-- 2) 備份表：搬之前的原課名（一筆報名表一列，重跑不重複）--------------------------
create table if not exists public.funv_cupping_merge_backup (
  id                  uuid primary key,
  course_choice_old   text not null,
  backed_up_at        timestamptz not null default now()
);
alter table public.funv_cupping_merge_backup enable row level security;
revoke all on public.funv_cupping_merge_backup from public, anon, authenticated;

insert into public.funv_cupping_merge_backup (id, course_choice_old)
select a.id, a.course_choice
  from public.funv_applications a
 where a.course_choice like '%張玉諳【溫罐%'
on conflict (id) do nothing;

-- 3) 搬：只換掉張玉諳那一段課名，其他欄位不動；列出改了哪些 ----------------------
update public.funv_applications a
   set course_choice = regexp_replace(a.course_choice, '張玉諳【溫罐調理[^】]*】', '台灣全人芳香身心養生協會【溫罐調理實戰班】', 'g')
 where a.course_choice like '%張玉諳【溫罐%'
returning a.id, a.name, a.course_choice as 新課名;

-- 檢查（選用）：
--   select count(*) as 張玉諳舊課名剩幾筆 from public.funv_applications where course_choice like '%張玉諳【溫罐%';   -- 應該是 0
--   select count(*) as 協會溫罐總數       from public.funv_applications where course_choice like '%溫罐調理實戰班%';

-- 還原（要退回時才用）：
--   update public.funv_applications a
--      set course_choice = b.course_choice_old
--     from public.funv_cupping_merge_backup b
--    where a.id = b.id;
--   確認還原沒問題後，備份表可以留著，或：drop table public.funv_cupping_merge_backup;

-- =====================================================================
-- 되돌리기: 20261111090000_memo_audio.sql
--
-- 이 마이그레이션이 추가한 것만 지운다. 기존 memos, polish_usage_daily는 건드리지 않는다.
-- 주의: 녹음 파일(정보와 파일)이 모두 사라진다.
--
-- 순서
--   1. (파일이 있다면) memo-audio 버킷을 비운다.
--      Supabase는 storage 테이블을 SQL로 직접 지우는 것을 막으므로 대시보드
--      Storage → memo-audio → 파일 전체 선택 → 삭제, 또는 Storage API로 지운다.
--   2. 이 SQL을 SQL Editor에서 실행한다.
--   3. 마이그레이션 기록을 되돌린다:
--      supabase migration repair --status reverted 20261111090000
-- =====================================================================

begin;

drop policy if exists memo_audio_objects_select_own on storage.objects;
drop policy if exists memo_audio_objects_insert_own on storage.objects;
drop policy if exists memo_audio_objects_delete_own on storage.objects;

drop table if exists public.memo_audio;

drop function if exists public.my_audio_usage();
drop function if exists public.audio_upload_allowed();
drop function if exists public.audio_bytes_used();
drop function if exists public.audio_quota_bytes();

commit;

-- 4. 빈 버킷 삭제: 대시보드 Storage → memo-audio → Delete bucket
--    (또는 SQL Editor에서 Storage API를 통하지 않는 삭제가 막혀 있으면 대시보드를 쓴다)

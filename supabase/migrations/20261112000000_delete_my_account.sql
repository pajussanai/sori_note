-- =====================================================================
-- 소리노트: 계정 삭제 함수 (운영 미적용 — 별도 승인 후 적용)
--
-- add-only: 함수 하나만 추가한다. 기존 테이블·정책·권한은 바꾸지 않는다.
-- 로그인 사용자가 자기 계정을 지우면 auth.users 행이 지워지고,
-- memos·polish_usage_daily는 외래 키(on delete cascade)로 함께 지워진다.
-- 되돌리기: supabase/rollback/20261112000000_delete_my_account_rollback.sql
--
-- 앱은 이 함수가 없으면(적용 전) 메모만 지우고 로그아웃한다.
-- =====================================================================

create function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;
  -- 순서를 분명히 하려고 사용자 데이터를 먼저 지우고 계정을 지운다.
  delete from public.memos where user_id = uid;
  delete from public.polish_usage_daily where user_id = uid;
  delete from auth.users where id = uid;
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

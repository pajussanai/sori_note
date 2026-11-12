-- 되돌리기: 20261112000000_delete_my_account.sql
-- 함수만 지운다. 이미 삭제된 계정은 되돌릴 수 없다.
-- 적용 후: supabase migration repair --status reverted 20261112000000
drop function if exists public.delete_my_account();

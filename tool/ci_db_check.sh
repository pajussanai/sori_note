#!/usr/bin/env bash
# 새 마이그레이션을 운영과 같은 순서로 로컬(임시) Supabase에 적용해 검증한다. CI 전용.
#
#   1. 기존 마이그레이션만 적용한 DB에 메모·AI 사용량 데이터를 넣는다(운영 상태 흉내).
#   2. 새 마이그레이션을 적용한다(supabase migration up).
#   3. 기존 데이터·정책·권한이 그대로인지 비교한다.
#   4. RLS·한도 테스트(supabase/tests)를 실행한다.
#   5. 롤백 SQL을 적용해 새 객체만 사라지고 기존 데이터는 그대로인지 확인한 뒤,
#      다시 적용해도 되는지 확인한다.
#
# 사용법: tool/ci_db_check.sh <새 마이그레이션 버전>   (예: 20261111090000)
set -euo pipefail

VERSION="$1"
NEW="$(ls supabase/migrations/${VERSION}_*.sql)"
ROLLBACK="$(ls supabase/rollback/${VERSION}_*_rollback.sql)"
DB="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
psql_q() { psql "$DB" -v ON_ERROR_STOP=1 -X -q -t -A "$@"; }

snapshot() {
  psql_q -c "
    select 'memos', md5(coalesce(string_agg(m::text, '|' order by id), '')) from public.memos m
    union all
    select 'usage', md5(coalesce(string_agg(u::text, '|' order by user_id, day), ''))
      from public.polish_usage_daily u
    union all
    select 'policies', md5(string_agg(concat_ws(',', tablename, policyname, cmd, roles::text, qual, with_check), '|'
                               order by tablename, policyname))
      from pg_policies where schemaname = 'public' and tablename in ('memos', 'polish_usage_daily')
    union all
    select 'grants', md5(string_agg(concat_ws(',', table_name, grantee, privilege_type), '|'
                             order by table_name, grantee, privilege_type))
      from information_schema.role_table_grants
      where table_schema = 'public' and table_name in ('memos', 'polish_usage_daily')
    union all
    select 'functions', md5(string_agg(p.proname || ':' || md5(p.prosrc), '|' order by p.proname))
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('set_updated_at', 'record_polish_usage');"
}

echo "== 1. 기존 마이그레이션만 적용"
mv "$NEW" /tmp/new_migration.sql
supabase start -x studio,imgproxy,mailpit,edge-runtime,logflare,vector,supavisor,realtime,postgres-meta
psql_q <<'SQL'
insert into auth.users (id, email) values
  ('11111111-0000-4000-8000-000000000001', 'old1@test.local'),
  ('22222222-0000-4000-8000-000000000002', 'old2@test.local');
insert into public.memos (id, user_id, content) values
  ('11111111-1111-4000-8000-000000000001', '11111111-0000-4000-8000-000000000001', '기존 메모 1'),
  ('11111111-1111-4000-8000-000000000002', '11111111-0000-4000-8000-000000000001', '기존 메모 2'),
  ('22222222-1111-4000-8000-000000000001', '22222222-0000-4000-8000-000000000002', '다른 사용자 메모');
select public.record_polish_usage('11111111-0000-4000-8000-000000000001', 120, 80);
SQL
snapshot > /tmp/before.txt
cat /tmp/before.txt

echo "== 2. 새 마이그레이션 적용"
mv /tmp/new_migration.sql "$NEW"
supabase migration up --local

echo "== 3. 기존 데이터·정책·권한 비교"
snapshot > /tmp/after.txt
diff /tmp/before.txt /tmp/after.txt
echo "기존 데이터·정책·권한·함수 변화 없음"

echo "== 4. RLS·한도 테스트"
supabase test db

echo "== 5. 롤백 후 기존 데이터 확인, 다시 적용"
psql_q -f "$ROLLBACK"
test "$(psql_q -c "select to_regclass('public.memo_audio') is null")" = "t"
test "$(psql_q -c "select count(*) from pg_policies where schemaname = 'storage' and policyname like 'memo_audio_%'")" = "0"
snapshot > /tmp/rolled_back.txt
diff /tmp/before.txt /tmp/rolled_back.txt
psql_q -f "$NEW"
test "$(psql_q -c "select to_regclass('public.memo_audio') is not null")" = "t"
echo "롤백과 재적용 확인"

supabase stop --no-backup

#!/usr/bin/env bash
# 운영 DB(sori-note, tkbhtdkhipmsmfwfhhom) 읽기 전용 백업. 마이그레이션 직전에 실행한다.
#
#   bash tool/backup_prod.sh <저장소 밖 폴더>     예) bash tool/backup_prod.sh /c/src/sori_note_backups/20261111
#
# - supabase db query --linked(Management API)로 SELECT만 실행한다. 아무것도 바꾸지 않는다.
# - Free 요금제는 자동 백업이 없고 이 PC에는 Docker·pg_dump가 없어서 이 방법을 쓴다.
# - 결과에는 사용자 메모(개인정보)가 들어 있다. 저장소 안에 두거나 GitHub에 올리지 않는다.
# - 비교용 스냅샷(snapshot.json)은 마이그레이션 뒤 다시 떠서 기존 데이터·정책·권한이 같은지 확인한다.
set -euo pipefail

OUT="${1:?백업 폴더를 지정하세요(저장소 밖)}"
case "$(cd "$(dirname "$OUT")" 2>/dev/null && pwd)/" in
  "$(pwd)"/*) echo "저장소 안에는 백업을 둘 수 없습니다: $OUT" >&2; exit 1 ;;
esac
mkdir -p "$OUT"

q() { supabase db query --linked "$1"; }

echo "== 기존 데이터"
q "select coalesce(json_agg(m order by m.id), '[]') from public.memos m" > "$OUT/memos.json"
q "select coalesce(json_agg(u order by u.user_id, u.day), '[]') from public.polish_usage_daily u" \
  > "$OUT/polish_usage_daily.json"

echo "== 구조와 기록"
q "select version, name from supabase_migrations.schema_migrations order by version" \
  > "$OUT/migrations.json"
q "select id, name, public, file_size_limit from storage.buckets order by id" > "$OUT/buckets.json"
q "select schemaname, tablename, policyname, cmd, roles::text, qual, with_check
     from pg_policies where schemaname in ('public', 'storage') order by 1, 2, 3" > "$OUT/policies.json"

echo "== 비교용 스냅샷(CI의 tool/ci_db_check.sh와 같은 계산)"
q "$(cat <<'SQL'
select 'memos' as item, count(*)::text as n,
       md5(coalesce(string_agg(m::text, '|' order by id), '')) as checksum from public.memos m
union all
select 'usage', count(*)::text, md5(coalesce(string_agg(u::text, '|' order by user_id, day), ''))
  from public.polish_usage_daily u
union all
select 'policies', count(*)::text,
       md5(string_agg(concat_ws(',', tablename, policyname, cmd, roles::text, qual, with_check), '|'
                      order by tablename, policyname))
  from pg_policies where schemaname = 'public' and tablename in ('memos', 'polish_usage_daily')
union all
select 'grants', count(*)::text,
       md5(string_agg(concat_ws(',', table_name, grantee, privilege_type), '|'
                      order by table_name, grantee, privilege_type))
  from information_schema.role_table_grants
  where table_schema = 'public' and table_name in ('memos', 'polish_usage_daily')
union all
select 'functions', count(*)::text, md5(string_agg(p.proname || ':' || md5(p.prosrc), '|' order by p.proname))
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname in ('set_updated_at', 'record_polish_usage')
SQL
)" > "$OUT/snapshot.json"

ls -la "$OUT"
echo "백업 완료: $OUT"

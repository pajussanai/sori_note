-- 2단계(녹음) 마이그레이션의 권한·RLS·한도 테스트. 로컬 DB에서만 실행한다.
--   supabase test db
-- 모든 변경은 트랜잭션 안에서 하고 마지막에 되돌린다.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- 테스트 사용자 A, B와 메모
insert into auth.users (id, email)
values ('aaaaaaaa-0000-4000-8000-000000000001', 'a@test.local'),
       ('bbbbbbbb-0000-4000-8000-000000000002', 'b@test.local');
insert into public.memos (id, user_id, content)
values ('aaaaaaaa-1111-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', 'A 메모'),
       ('bbbbbbbb-1111-4000-8000-000000000002', 'bbbbbbbb-0000-4000-8000-000000000002', 'B 메모');

-- ------------------------------------------------------------- 기존 구조 유지
select policies_are('public', 'memos',
  array['memos_select_own', 'memos_insert_own', 'memos_update_own', 'memos_delete_own'],
  '기존 memos 정책은 그대로');
select policies_are('public', 'polish_usage_daily',
  array['polish_usage_daily_select_own'], '기존 polish_usage_daily 정책은 그대로');
select columns_are('public', 'memos',
  array['id', 'user_id', 'content', 'created_at', 'updated_at'], '기존 memos 열은 그대로');

-- ------------------------------------------------------------- 새 구조
select has_table('public', 'memo_audio', 'memo_audio 테이블');
select is((select relrowsecurity from pg_class where oid = 'public.memo_audio'::regclass),
  true, 'memo_audio RLS 켜짐');
select results_eq(
  $$ select public, file_size_limit, allowed_mime_types from storage.buckets where id = 'memo-audio' $$,
  $$ values (false, 20971520::bigint, array['audio/mp4', 'audio/aac', 'audio/webm', 'audio/ogg']) $$,
  '버킷은 비공개, 파일 20MB, 오디오 형식만');

-- ------------------------------------------------------------- 비로그인(anon)
set local role anon;
select throws_ok($$ select * from public.memo_audio $$, '42501', null, 'anon은 memo_audio 조회 불가');
select is((select count(*) from storage.objects where bucket_id = 'memo-audio'), 0::bigint,
  'anon은 녹음 파일을 볼 수 없음');
select throws_ok($$ select * from public.my_audio_usage() $$, '42501', null,
  'anon은 사용량 함수 실행 불가');
reset role;

-- ------------------------------------------------------------- 사용자 A
set local role authenticated;
set local request.jwt.claims = '{"sub": "aaaaaaaa-0000-4000-8000-000000000001", "role": "authenticated"}';

select lives_ok($$
  insert into storage.objects (bucket_id, name, owner_id, metadata)
  values ('memo-audio',
          'aaaaaaaa-0000-4000-8000-000000000001/aaaaaaaa-1111-4000-8000-000000000001/a1.m4a',
          'aaaaaaaa-0000-4000-8000-000000000001',
          '{"size": 1000, "mimetype": "audio/mp4"}')
$$, 'A는 자기 폴더에 파일을 올릴 수 있다');

select throws_ok($$
  insert into storage.objects (bucket_id, name, owner_id, metadata)
  values ('memo-audio',
          'bbbbbbbb-0000-4000-8000-000000000002/bbbbbbbb-1111-4000-8000-000000000002/x.m4a',
          'aaaaaaaa-0000-4000-8000-000000000001', '{"size": 1000}')
$$, '42501', null, 'A는 B 폴더에 파일을 올릴 수 없다');

select lives_ok($$
  insert into public.memo_audio (id, memo_id, storage_path, mime_type, duration_ms, size_bytes)
  values ('aaaaaaaa-2222-4000-8000-000000000001', 'aaaaaaaa-1111-4000-8000-000000000001',
          'aaaaaaaa-0000-4000-8000-000000000001/aaaaaaaa-1111-4000-8000-000000000001/a1.m4a',
          'audio/mp4', 5000, 1000)
$$, 'A는 자기 메모에 녹음을 연결할 수 있다');

select throws_ok($$
  insert into public.memo_audio (memo_id, storage_path, mime_type, duration_ms, size_bytes)
  values ('bbbbbbbb-1111-4000-8000-000000000002',
          'aaaaaaaa-0000-4000-8000-000000000001/bbbbbbbb-1111-4000-8000-000000000002/x.m4a',
          'audio/mp4', 5000, 1000)
$$, '42501', null, 'A는 B의 메모에 녹음을 연결할 수 없다');

select throws_ok($$
  insert into public.memo_audio (memo_id, storage_path, mime_type, duration_ms, size_bytes)
  values ('aaaaaaaa-1111-4000-8000-000000000001',
          'bbbbbbbb-0000-4000-8000-000000000002/aaaaaaaa-1111-4000-8000-000000000001/x.m4a',
          'audio/mp4', 5000, 1000)
$$, '23514', null, '다른 사람 폴더 경로는 저장할 수 없다');

select throws_ok($$
  insert into public.memo_audio (memo_id, storage_path, mime_type, duration_ms, size_bytes)
  values ('aaaaaaaa-1111-4000-8000-000000000001',
          'aaaaaaaa-0000-4000-8000-000000000001/aaaaaaaa-1111-4000-8000-000000000001/x.exe',
          'application/octet-stream', 5000, 1000)
$$, '23514', null, '오디오가 아닌 형식은 저장할 수 없다');

select throws_ok($$
  insert into public.memo_audio (memo_id, storage_path, mime_type, duration_ms, size_bytes)
  values ('aaaaaaaa-1111-4000-8000-000000000001',
          'aaaaaaaa-0000-4000-8000-000000000001/aaaaaaaa-1111-4000-8000-000000000001/long.m4a',
          'audio/mp4', 1300000, 1000)
$$, '23514', null, '20분(+여유 1분)보다 긴 녹음은 저장할 수 없다');

select throws_ok($$
  insert into public.memo_audio (memo_id, storage_path, mime_type, duration_ms, size_bytes)
  values ('aaaaaaaa-1111-4000-8000-000000000001',
          'aaaaaaaa-0000-4000-8000-000000000001/aaaaaaaa-1111-4000-8000-000000000001/huge.m4a',
          'audio/mp4', 1000, 20971521)
$$, '23514', null, '20MB보다 큰 파일 정보는 저장할 수 없다');

select throws_ok($$
  update public.memo_audio set size_bytes = 1 where id = 'aaaaaaaa-2222-4000-8000-000000000001'
$$, '42501', null, '녹음 정보는 수정할 수 없다');

select results_eq($$ select used_bytes, limit_bytes, file_count from public.my_audio_usage() $$,
  $$ values (1000::bigint, 104857600::bigint, 1) $$, 'A의 사용량');

-- 한도: 정보 행 합계가 100MB를 넘으면 추가할 수 없다(20MB × 5 = 100MB + 1000바이트).
select lives_ok($$
  insert into public.memo_audio (memo_id, storage_path, mime_type, duration_ms, size_bytes)
  select 'aaaaaaaa-1111-4000-8000-000000000001',
         'aaaaaaaa-0000-4000-8000-000000000001/aaaaaaaa-1111-4000-8000-000000000001/q' || g || '.m4a',
         'audio/mp4', 1000, 20971520 - 1000
  from generate_series(1, 5) g
  where g <= 5
$$, '한도 안에서는 여러 개 저장 가능');
select throws_ok($$
  insert into public.memo_audio (memo_id, storage_path, mime_type, duration_ms, size_bytes)
  values ('aaaaaaaa-1111-4000-8000-000000000001',
          'aaaaaaaa-0000-4000-8000-000000000001/aaaaaaaa-1111-4000-8000-000000000001/over.m4a',
          'audio/mp4', 1000, 6000)
$$, '42501', null, '100MB 한도를 넘으면 추가할 수 없다');

-- 파일 한도: 이미 올린 파일 합계가 100MB 이상이면 더 올릴 수 없다.
reset role;
insert into storage.objects (bucket_id, name, owner_id, metadata)
values ('memo-audio',
        'aaaaaaaa-0000-4000-8000-000000000001/aaaaaaaa-1111-4000-8000-000000000001/big.m4a',
        'aaaaaaaa-0000-4000-8000-000000000001', '{"size": 104857600}');
set local role authenticated;
set local request.jwt.claims = '{"sub": "aaaaaaaa-0000-4000-8000-000000000001", "role": "authenticated"}';
select throws_ok($$
  insert into storage.objects (bucket_id, name, owner_id, metadata)
  values ('memo-audio',
          'aaaaaaaa-0000-4000-8000-000000000001/aaaaaaaa-1111-4000-8000-000000000001/a2.m4a',
          'aaaaaaaa-0000-4000-8000-000000000001', '{"size": 1000}')
$$, '42501', null, '파일 합계가 한도에 닿으면 더 올릴 수 없다');

-- ------------------------------------------------------------- 사용자 B
set local request.jwt.claims = '{"sub": "bbbbbbbb-0000-4000-8000-000000000002", "role": "authenticated"}';
select is((select count(*) from public.memo_audio), 0::bigint, 'B는 A의 녹음 정보를 볼 수 없다');
select is((select count(*) from storage.objects where bucket_id = 'memo-audio'), 0::bigint,
  'B는 A의 녹음 파일을 볼 수 없다');
delete from public.memo_audio;   -- RLS 때문에 지워지는 행이 없어야 한다
select results_eq($$ select used_bytes from public.my_audio_usage() $$,
  $$ values (0::bigint) $$, 'B의 사용량은 0');
reset role;
select is((select count(*) from public.memo_audio), 6::bigint, 'B의 삭제 시도로 A의 녹음이 지워지지 않음');

-- ------------------------------------------------------------- A가 자기 녹음 삭제
set local role authenticated;
set local request.jwt.claims = '{"sub": "aaaaaaaa-0000-4000-8000-000000000001", "role": "authenticated"}';
delete from public.memo_audio where id = 'aaaaaaaa-2222-4000-8000-000000000001';
select is((select count(*) from public.memo_audio), 5::bigint, 'A는 자기 녹음 정보를 지울 수 있다');
reset role;

-- ------------------------------------------------------------- 메모를 지우면 녹음 정보도 지워진다
delete from public.memos where id = 'aaaaaaaa-1111-4000-8000-000000000001';
select is((select count(*) from public.memo_audio), 0::bigint, '메모 삭제 시 녹음 정보도 삭제');
select is((select count(*) from public.memos where id = 'bbbbbbbb-1111-4000-8000-000000000002'),
  1::bigint, '다른 사용자 메모는 그대로');

select * from finish();
rollback;

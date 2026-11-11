-- =====================================================================
-- 소리노트 2단계: 원본 음성(녹음 파일) 보관
--
-- add-only 원칙
--   - 기존 memos, polish_usage_daily 테이블·권한·정책과 함수는 바꾸지 않는다.
--   - 새 테이블 memo_audio, 새 함수 5개, 새 Storage 버킷 memo-audio와
--     그 버킷에만 적용되는 Storage 정책 3개를 추가한다.
--   - 되돌리기: supabase/rollback/20261111090000_memo_audio_rollback.sql
--
-- 보안 원칙
--   1. 녹음 파일은 비공개 버킷에 <user_id>/<memo_id>/<audio_id>.<확장자>로 저장한다.
--   2. 로그인 사용자는 자기 폴더의 파일만 올리고, 보고(재생), 지울 수 있다.
--   3. 비로그인 사용자(anon)는 테이블과 파일 어디에도 접근할 수 없다.
--   4. 사용자별 보관 한도(100MB)와 파일 크기 한도(20MB)를 서버에서 막는다.
--   5. 무료 요금제를 넘지 않도록 프로젝트 전체 녹음 합계를 800MB로 막는다.
--      (Supabase Free: 전체 파일 저장 1GB, 파일 하나 최대 50MB)
-- =====================================================================


-- 사용자 한 명이 보관할 수 있는 녹음 파일 합계(바이트): 100MB
create function public.audio_quota_bytes()
returns bigint
language sql
immutable
set search_path = ''
as $$
  select 104857600::bigint;
$$;

-- 프로젝트 전체 녹음 파일 합계 한도(바이트): 800MB.
-- Supabase Free의 파일 저장 1GB를 넘지 않도록 여유를 둔다. 닿으면 새 녹음 저장만 막힌다.
create function public.audio_total_limit_bytes()
returns bigint
language sql
immutable
set search_path = ''
as $$
  select 838860800::bigint;
$$;


-- ---------------------------------------------------------------------
-- memo_audio: 메모에 딸린 녹음 파일 정보(파일 자체는 Storage에 있다)
-- ---------------------------------------------------------------------
create table public.memo_audio (
  id           uuid        primary key default gen_random_uuid(),
  user_id      uuid        not null default auth.uid()
                           references auth.users (id) on delete cascade,
  memo_id      uuid        not null
                           references public.memos (id) on delete cascade,
  storage_path text        not null unique,
  mime_type    text        not null
                           check (mime_type in ('audio/mp4', 'audio/aac', 'audio/webm', 'audio/ogg')),
  -- 녹음 한 번은 최대 20분(앱 AudioLimits.maxDuration). 시간 측정 오차를 위해 1분 여유.
  duration_ms  integer     not null check (duration_ms between 0 and 1260000),
  -- 버킷의 파일 크기 한도와 같은 20MB
  size_bytes   bigint      not null check (size_bytes between 1 and 20971520),
  created_at   timestamptz not null default now(),
  -- 파일 경로는 반드시 본인 폴더, 해당 메모 폴더 아래여야 한다.
  constraint memo_audio_path_owner
    check (storage_path like user_id::text || '/' || memo_id::text || '/%')
);

comment on table public.memo_audio is
  '메모의 원본 음성 파일 정보. 파일은 Storage 버킷 memo-audio에 있다. 본인만 조회·추가·삭제.';

create index memo_audio_memo_id_idx on public.memo_audio (memo_id);
create index memo_audio_user_id_created_at_idx
  on public.memo_audio (user_id, created_at desc);


-- 녹음 정보 한 건(p_size 바이트)을 더해도 본인 한도와 프로젝트 전체 한도 안인지. 추가 정책(RLS)에서 쓴다.
-- 정책 안에서 같은 테이블을 직접 조회하면 무한 재귀가 되므로 security definer 함수로 분리했다.
-- 다른 사람의 사용량이 드러나지 않도록 참/거짓만 돌려준다.
create function public.audio_row_allowed(p_size bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    coalesce(sum(a.size_bytes) filter (where a.user_id = (select auth.uid())), 0) + p_size
      <= public.audio_quota_bytes()
    and coalesce(sum(a.size_bytes), 0) + p_size <= public.audio_total_limit_bytes()
  from public.memo_audio a;
$$;


-- 본인의 녹음 사용량(설정 화면 표시용)
create function public.my_audio_usage()
returns table (used_bytes bigint, limit_bytes bigint, file_count integer)
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(sum(a.size_bytes), 0)::bigint,
         public.audio_quota_bytes(),
         count(*)::integer
  from public.memo_audio a
  where a.user_id = (select auth.uid());
$$;


-- Storage 업로드 정책에서 쓰는 한도 확인: 본인 폴더의 파일 합계와 버킷 전체 파일 합계가
-- 각각 한도 미만인지. storage.objects를 읽어야 하므로 security definer로 만들고,
-- 다른 사람의 사용량이 드러나지 않도록 매개변수 없이 참/거짓만 돌려준다.
create function public.audio_upload_allowed()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    coalesce(sum((o.metadata ->> 'size')::bigint)
               filter (where (storage.foldername(o.name))[1] = (select auth.uid())::text), 0)
      < public.audio_quota_bytes()
    and coalesce(sum((o.metadata ->> 'size')::bigint), 0) < public.audio_total_limit_bytes()
  from storage.objects o
  where o.bucket_id = 'memo-audio';
$$;

revoke all on function public.audio_quota_bytes() from public, anon;
revoke all on function public.audio_total_limit_bytes() from public, anon;
revoke all on function public.my_audio_usage() from public, anon;
revoke all on function public.audio_upload_allowed() from public, anon;
revoke all on function public.audio_row_allowed(bigint) from public, anon;
grant execute on function public.audio_quota_bytes() to authenticated, service_role;
grant execute on function public.audio_total_limit_bytes() to authenticated, service_role;
grant execute on function public.my_audio_usage() to authenticated, service_role;
grant execute on function public.audio_upload_allowed() to authenticated, service_role;
grant execute on function public.audio_row_allowed(bigint) to authenticated, service_role;


-- ---------------------------------------------------------------------
-- 테이블 권한(GRANT)과 RLS: 본인 행만
-- ---------------------------------------------------------------------
revoke all on table public.memo_audio from anon, authenticated;
grant all on table public.memo_audio to service_role;

-- 조회·삭제, 추가(필요한 열만). 수정은 허용하지 않는다(녹음은 바꾸지 않고 지우고 다시 올린다).
grant select, delete on table public.memo_audio to authenticated;
grant insert (id, memo_id, storage_path, mime_type, duration_ms, size_bytes)
  on table public.memo_audio to authenticated;

alter table public.memo_audio enable row level security;

create policy memo_audio_select_own on public.memo_audio
  for select to authenticated
  using ((select auth.uid()) = user_id);

-- 본인 메모에만 붙일 수 있고, 한도를 넘으면 추가할 수 없다.
create policy memo_audio_insert_own on public.memo_audio
  for insert to authenticated
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.memos m
      where m.id = memo_id and m.user_id = (select auth.uid())
    )
    and public.audio_row_allowed(size_bytes)
  );

create policy memo_audio_delete_own on public.memo_audio
  for delete to authenticated
  using ((select auth.uid()) = user_id);


-- =====================================================================
-- Storage: 비공개 버킷과 사용자별 폴더 정책
-- =====================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'memo-audio',
  'memo-audio',
  false,                                              -- 공개 URL 없음(서명된 URL로만 재생)
  20971520,                                           -- 파일 하나 최대 20MB
  array['audio/mp4', 'audio/aac', 'audio/webm', 'audio/ogg']
)
on conflict (id) do nothing;

-- 이 정책들은 memo-audio 버킷에만 적용된다.
create policy memo_audio_objects_select_own on storage.objects
  for select to authenticated
  using (
    bucket_id = 'memo-audio'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy memo_audio_objects_insert_own on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'memo-audio'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and public.audio_upload_allowed()
  );

create policy memo_audio_objects_delete_own on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'memo-audio'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

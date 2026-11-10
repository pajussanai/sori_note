-- =====================================================================
-- 소리노트: 메모와 AI 다듬기 사용량
--
-- 보안 원칙
--   1. 모든 테이블에 RLS를 켜고, 로그인 사용자는 자기 행(user_id = auth.uid())만 다룬다.
--   2. 비로그인 사용자(anon)는 어떤 테이블에도 접근할 수 없다.
--   3. RLS와 별도로 테이블 권한(GRANT)도 필요한 동작·컬럼만 허용한다.
--   4. polish_usage_daily는 서버(Edge Function, service_role)만 쓴다.
--   5. 이 파일에는 API 키나 비밀값이 없다.
-- =====================================================================


-- updated_at 자동 갱신
create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

revoke all on function public.set_updated_at() from public, anon, authenticated;


-- ---------------------------------------------------------------------
-- memos: 사용자별 메모
-- ---------------------------------------------------------------------
create table public.memos (
  id         uuid        primary key default gen_random_uuid(),
  user_id    uuid        not null default auth.uid()
                         references auth.users (id) on delete cascade,
  content    text        not null default '' check (char_length(content) <= 20000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.memos is '사용자별 메모. 본인만 조회·추가·수정·삭제 가능.';

create index memos_user_id_updated_at_idx
  on public.memos (user_id, updated_at desc);

create trigger memos_set_updated_at
  before update on public.memos
  for each row execute function public.set_updated_at();


-- ---------------------------------------------------------------------
-- polish_usage_daily: 날짜별 AI 다듬기 사용량 (서버만 기록)
-- ---------------------------------------------------------------------
create table public.polish_usage_daily (
  user_id       uuid    not null references auth.users (id) on delete cascade,
  -- 한국 시간(Asia/Seoul) 기준 날짜
  day           date    not null,
  request_count integer not null default 0 check (request_count >= 0),
  input_tokens  bigint  not null default 0 check (input_tokens >= 0),
  output_tokens bigint  not null default 0 check (output_tokens >= 0),
  updated_at    timestamptz not null default now(),
  primary key (user_id, day)
);

comment on table public.polish_usage_daily is 'AI 다듬기 일일 사용량. 본인은 조회만. 기록은 서버가 record_polish_usage()로만 한다.';

-- 서버 전용: 다듬기 1건의 사용량을 오늘 합계에 더한다.
create function public.record_polish_usage(
  p_user_id       uuid,
  p_input_tokens  bigint default 0,
  p_output_tokens bigint default 0
)
returns void
language sql
security invoker
set search_path = ''
as $$
  insert into public.polish_usage_daily as u
    (user_id, day, request_count, input_tokens, output_tokens)
  values
    (p_user_id, (now() at time zone 'Asia/Seoul')::date, 1,
     p_input_tokens, p_output_tokens)
  on conflict (user_id, day) do update
    set request_count = u.request_count + 1,
        input_tokens  = u.input_tokens + excluded.input_tokens,
        output_tokens = u.output_tokens + excluded.output_tokens,
        updated_at    = now();
$$;

revoke all on function public.record_polish_usage(uuid, bigint, bigint)
  from public, anon, authenticated;
grant execute on function public.record_polish_usage(uuid, bigint, bigint)
  to service_role;


-- =====================================================================
-- 테이블 권한(GRANT): 동작·컬럼 단위로 필요한 것만 허용
-- (새 프로젝트의 기본 권한이 anon·authenticated에 모두 열려 있을 수 있어 먼저 회수한다)
-- =====================================================================
revoke all on table public.memos, public.polish_usage_daily
  from anon, authenticated;

grant all on table public.memos, public.polish_usage_daily to service_role;

-- memos: 조회·삭제, 추가(id·content), 내용만 수정
grant select, delete on table public.memos to authenticated;
grant insert (id, content) on table public.memos to authenticated;
grant update (content) on table public.memos to authenticated;

-- polish_usage_daily: 조회만
grant select on table public.polish_usage_daily to authenticated;


-- =====================================================================
-- RLS: 본인 행만
-- =====================================================================
alter table public.memos              enable row level security;
alter table public.polish_usage_daily enable row level security;

create policy memos_select_own on public.memos
  for select to authenticated
  using ((select auth.uid()) = user_id);

create policy memos_insert_own on public.memos
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy memos_update_own on public.memos
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy memos_delete_own on public.memos
  for delete to authenticated
  using ((select auth.uid()) = user_id);

create policy polish_usage_daily_select_own on public.polish_usage_daily
  for select to authenticated
  using ((select auth.uid()) = user_id);

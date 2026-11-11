# 2단계(녹음) 운영 DB 변경 계획 — 승인 요청

- 대상: Supabase 프로젝트 **sori-note (`tkbhtdkhipmsmfwfhhom`, 서울)** 한 곳만
- 변경하지 않음: blessing-chatbot 프로젝트, 기존 `memos`·`polish_usage_daily` 테이블과 정책·권한·함수
- 상태: **미적용(승인 대기)**. 운영 마이그레이션 기록에는 `20261110055556`만 있고 `20261111090000`은 대기 중

## 1. 적용할 내용

파일: [supabase/migrations/20261111090000_memo_audio.sql](../supabase/migrations/20261111090000_memo_audio.sql)

| 종류 | 이름 | 내용 |
|---|---|---|
| 새 테이블 | `public.memo_audio` | 녹음 파일 정보(메모 id, 파일 경로, 형식, 길이, 크기). RLS 켬 |
| 새 정책(테이블) | `memo_audio_select_own`, `_insert_own`, `_delete_own` | 본인 행만 조회·추가·삭제. 수정 불가. 추가는 본인 메모에만, 한도 안에서만 |
| 새 권한 | `memo_audio` | anon 없음. authenticated: 조회·삭제, 추가(필요한 열만) |
| 새 함수 | `audio_quota_bytes()` | 사용자 한도 100MB |
| | `audio_total_limit_bytes()` | 프로젝트 전체 한도 800MB(무료 1GB 초과 방지) |
| | `audio_row_allowed(bigint)` | 정보 추가 한도 확인(참/거짓만 반환) |
| | `audio_upload_allowed()` | 파일 올리기 한도 확인(참/거짓만 반환) |
| | `my_audio_usage()` | 본인 사용량(설정 화면) |
| 새 버킷 | `memo-audio` | **비공개**, 파일 하나 20MB, 오디오 형식(mp4·aac·webm·ogg)만 |
| 새 정책(Storage) | `memo_audio_objects_select_own`, `_insert_own`, `_delete_own` | `memo-audio` 버킷에서 본인 폴더(`<user_id>/…`)만 재생·올리기·삭제. 다른 버킷에는 적용되지 않음 |

## 2. 영향 범위

- **기존 데이터·기능**: 바꾸는 행·열·정책이 없다. 현재 운영 앱은 새 테이블을 쓰지 않으므로 그대로 동작한다.
- **잠금**: `memo_audio`가 `memos`를 참조(외래 키)하도록 만들 때 `memos`에 아주 짧은 잠금이 걸린다(쓰기만 잠시 대기, 수 밀리초).
- **삭제 연쇄**: 메모나 계정이 지워지면 그 메모의 녹음 정보 행도 함께 지워진다(새 데이터에만 해당).
  파일은 앱이 메모를 지우기 전에 먼저 지운다.
- **비용**: 0원. Supabase Free 범위(파일 1GB, 파일 하나 50MB, 전송 5GB/월) 안에서 동작하도록 한도를 걸었다.
  전체 녹음이 800MB에 닿으면 새 녹음 저장만 막히고(기기에 보관), 결제나 요금제 변경은 없다.
- **재생 전송량**: 재생할 때마다 파일을 내려받으므로 월 5GB 무료 전송량을 쓴다.
  녹음은 실측 약 103kbps(최대 128kbps 가정)라 1GB ≈ 17~22시간 분량, 월 5GB ≈ 85시간 이상 재생.
  이 한도는 서버에서 막지 않으므로 대시보드 사용량을 보고, 넘을 것 같으면 재생 기능을 제한한다.
- **보관 용량**: 사용자 100MB ≈ 녹음 약 2시간, 전체 800MB ≈ 약 17시간.

## 3. 사전 검증(운영 DB에 연결하지 않음)

GitHub Actions 안의 임시 로컬 Supabase에서 운영과 같은 순서로 검증했다([tool/ci_db_check.sh](../tool/ci_db_check.sh)).

1. 기존 마이그레이션만 적용 → 메모·AI 사용량 샘플 데이터 입력
2. 새 마이그레이션 적용
3. **기존 데이터·정책·권한·함수의 체크섬이 적용 전과 같음**
4. RLS·한도 테스트([supabase/tests/memo_audio_test.sql](../supabase/tests/memo_audio_test.sql)) 전부 통과
   - 비로그인: 테이블·파일·사용량 함수 접근 불가
   - A는 자기 폴더·자기 메모에만 올리고 연결 가능, B 폴더·B 메모 불가, 다른 사용자 녹음 조회·삭제 불가
   - 오디오가 아닌 형식, 20분 넘는 녹음, 20MB 넘는 파일, 사용자 100MB 초과, 전체 800MB 초과 모두 거부
   - 녹음 정보 수정 불가, 메모 삭제 시 녹음 정보 함께 삭제
5. **롤백 SQL 적용 → 새 객체만 사라지고 기존 데이터·정책 체크섬 그대로 → 다시 적용 가능**

## 4. 백업과 복구

Free 요금제는 자동 백업·시점 복구(PITR)가 없고, 이 PC에는 Docker·pg_dump가 없다.
그래서 적용 직전에 **읽기 전용 쿼리로 백업**한다([tool/backup_prod.sh](../tool/backup_prod.sh)).

- 저장 위치: 저장소 밖 `C:\src\sori_note_backups\<날짜>\` (메모 내용이 들어 있어 GitHub에 올리지 않음)
- 내용: `memos`·`polish_usage_daily` 전체(JSON), 마이그레이션 기록, 버킷 목록, 정책 정의, 비교용 체크섬
- Storage 파일: 현재 녹음 기능이 없어 백업할 파일이 없다.

복구 방법

| 상황 | 방법 |
|---|---|
| 새 기능만 되돌리기 | [롤백 SQL](../supabase/rollback/20261111090000_memo_audio_rollback.sql)을 SQL Editor에서 실행 → `supabase migration repair --status reverted 20261111090000` → 버킷 비우고 삭제(대시보드) |
| 기존 데이터 이상(예상하지 않음) | 백업 JSON으로 행을 되살리는 SQL을 만들어 적용(필요하면 작성) |

## 5. 승인 후 적용 순서

1. 백업: `bash tool/backup_prod.sh /c/src/sori_note_backups/<날짜>`
2. 미리 보기: `supabase db push --dry-run` → `20261111090000` 하나만 적용 대상인지 확인
3. 적용: `supabase db push`
4. 확인
   - 비교용 스냅샷을 다시 떠서 기존 데이터·정책·권한 체크섬이 백업과 같은지
   - 비로그인으로 `memo_audio` 조회·버킷 파일 접근이 막히는지
   - `supabase db advisors --linked`로 보안 경고가 새로 생기지 않았는지
5. 2단계 앱을 `main`에 병합 → GitHub Pages 자동 배포
6. 실제 기기 확인(사용자): PC Chrome, Android Chrome, iPhone Safari에서 녹음·재생·삭제

중간에 하나라도 이상하면 멈추고 보고한다.

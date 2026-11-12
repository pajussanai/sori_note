# 소리노트 (sori_note)

말로 기록하는 메모장. 말하면 글자로 바꿔 메모로 저장하고, 버튼 한 번으로 AI가 문장을 다듬어 줍니다.
저장한 메모는 자동으로 분류되고, 일정·할 일과 하루 요약으로 정리됩니다.

## 주요 기능
- **음성 기록:** 녹음 시작 → 일시정지·재개 → 종료 → 글자 확인·고치기 → AI 다듬기 → 메모 저장.
  기기(브라우저) 음성 인식이 말하는 즉시 글자로 바꾸며, **소리 파일은 만들지도 저장하지도 않습니다.**
  음성 인식을 쓸 수 없는 환경에서는 바로 글자로 입력합니다.
- **텍스트 메모:** 첫 줄이 제목. 입력을 멈추면 자동 저장, 메모 화면의 마이크로 받아쓰기.
- **AI 다듬기:** 받아쓰기 오타·띄어쓰기·문장 부호를 고친 결과를 원문과 비교해 보고 적용·되돌리기.
- **자동 분류·태그:** 업무·개인·아이디어·회의·일정·쇼핑·할 일·기타와 핵심 낱말 태그. 내용이 바뀐 메모만
  다시 분류하고, 직접 고친 분류·태그는 덮어쓰지 않습니다.
- **검색:** 제목·본문(서버)과 분류·태그를 함께 찾고, 찾은 곳 주변을 미리보기로 보여 줍니다.
- **하루 정리:** 그날 메모로 주요 내용·진행 상황·결정 사항·이슈·할 일·기억할 내용을 만들고 고치거나 지웁니다.
  메모가 없는 날에는 만들지 않습니다.
- **일정·할 일:** 메모에서 날짜·시간·할 일을 찾아(한국 시간 기준) 확인 후 등록. 모호하면 확인을 요청하고,
  지난 시각·없는 날짜는 등록하지 않습니다. 수정·삭제·완료, 알림 설정과 알림 목록.
- **데이터 관리:** JSON 내보내기, 계정 삭제, AI 사용량·데이터 현황.

### 처리 위치와 한계
| 기능 | 처리 | 비고 |
|---|---|---|
| 메모 | 서버(`memos` 테이블, RLS) | 어느 기기에서나 같음 |
| AI 다듬기 | 서버(Edge Function `polish` → Gemini 무료) | 누를 때만 호출 |
| 분류·태그·하루 요약·일정 찾기 | **기기 안 규칙**(한국어 낱말·날짜 표현) | 메모가 밖으로 나가지 않고 비용 없음 |
| 분류·일정·요약 저장 | **이 기기(브라우저 저장소)** | 운영 DB를 바꾸지 않기 위해. 다른 기기에서는 보이지 않음 |
| 알림 | 브라우저 알림(Notification API) | 소리노트가 열려 있을 때만. 브라우저를 닫으면 오지 않음 |
| 계정 삭제 | 서버 함수 `delete_my_account`(미적용) | 적용 전에는 메모만 지우고 로그인 계정은 남음 |

## 화면
- 휴대폰: 아래 탭(홈·기록·검색·일정·설정), PC(넓은 화면): 왼쪽 메뉴
- 홈: 음성 기록·텍스트 메모 시작, 빠른 검색, 다가오는 일정, 하루 정리, 최근 기록
- 메모 화면: 작성 시각·분류·태그, AI 다듬기, 받아쓰기, 일정 추출·관련 메모(오른쪽 위), 삭제(메뉴)

## 구성
| 부분 | 기술 |
|---|---|
| 앱 | Flutter (웹·Android·iOS) |
| 로그인·저장 | Supabase Auth, Postgres(`memos` 테이블, RLS) |
| 음성 인식 | `speech_to_text` (브라우저 Web Speech API, Android·iOS 기기 인식기) |
| AI 다듬기 | Supabase Edge Function `polish` → Google Gemini (`gemini-3.5-flash-lite`) |
| 기기 저장 | `shared_preferences` (웹: localStorage) |

AI 키(`GEMINI_API_KEY`)는 Edge Function 서버 비밀값으로만 관리하며 앱 코드와 저장소에는 없습니다.
앱에는 공개용 publishable 키만 빌드할 때 넣습니다.

## 운영 DB에 아직 적용하지 않은 변경
- [supabase/migrations/20261112000000_delete_my_account.sql](supabase/migrations/20261112000000_delete_my_account.sql):
  계정 삭제 함수(add-only). 되돌리기: [supabase/rollback/](supabase/rollback/).
  승인 후 `supabase db push`로 적용하면 앱의 계정 삭제가 로그인 계정까지 지웁니다.

## 실행
```sh
flutter pub get
flutter run -d chrome
```
기본으로 소리노트 Supabase 프로젝트(`tkbhtdkhipmsmfwfhhom`)에 연결합니다.
다른 프로젝트로 실행하려면 `--dart-define=SUPABASE_URL=...`과
`--dart-define=SUPABASE_PUBLISHABLE_KEY=...`로 덮어씁니다.

## 웹 배포 (GitHub Pages)
주소: https://pajussanai.github.io/sori_note/

`main`에 푸시하면 [.github/workflows/deploy-pages.yml](.github/workflows/deploy-pages.yml)이
분석·테스트를 통과한 경우에만 `flutter build web --release --base-href /sori_note/`로 빌드해 배포합니다.

처음 한 번 설정:
1. GitHub 저장소 Settings → Pages → Source를 **GitHub Actions**로 바꿉니다.
2. Supabase 대시보드 → Authentication → URL Configuration
   - Site URL: `https://pajussanai.github.io/sori_note/`
   - Redirect URLs에 `https://pajussanai.github.io/sori_note/`와 로컬 개발 주소(예: `http://localhost:*/**`)를 추가합니다.

휴대폰에서는 홈 화면에 추가하면 앱처럼(standalone) 열립니다.
Android Chrome: 메뉴 → 홈 화면에 추가(앱 설치) / iPhone Safari: 공유 → 홈 화면에 추가.

## 서버 설정 (처음 한 번)
```sh
supabase link --project-ref tkbhtdkhipmsmfwfhhom
supabase db push                                   # memos 테이블·RLS
supabase functions deploy polish --use-api --project-ref tkbhtdkhipmsmfwfhhom
```
Supabase 대시보드 → Edge Functions → Secrets에 `GEMINI_API_KEY`를 등록합니다.
선택: `GEMINI_MODEL`(모델 변경), `POLISH_DAILY_LIMIT`(사용자별 하루 다듬기 횟수, 기본 50).

## 알아 둘 점
- AI 다듬기를 누르면 그 메모 내용이 Google Gemini로 전송됩니다. 무료 등급에서는 Google이 제품 개선에 사용할 수 있습니다.
- Gemini 무료 사용량을 넘으면 유료로 넘어가지 않고 오류로 알려 줍니다.
- 웹 음성 인식은 브라우저의 Web Speech API를 씁니다. 지원 여부는 앱이 실행 중에 확인하고, 지원하지 않으면 안내와 함께 '키보드로 입력'을 보여 줍니다.
  - PC·Android: Chrome, Edge에서 동작합니다(Chrome은 음성을 Google 서버로 보내 인식). Firefox는 지원하지 않습니다.
  - iPhone: Safari에서 동작합니다(iOS 설정의 '받아쓰기'가 켜져 있어야 함). 홈 화면에 추가한 앱 모드와 iPhone의 다른 브라우저에서는 iOS 버전에 따라 동작하지 않을 수 있습니다.

## 브랜드(로고·아이콘·컬러)
- 심볼: 왼쪽의 음성 파형이 오른쪽 메모 문서로 이어지는 모양(평면 벡터, 딥 틸·민트)
- 컬러: Primary Teal `#548C83`, Deep Teal `#356B65`(주요 버튼·선택 메뉴), Secondary Mint `#B8D5C9`(태그·상태),
  Background Ivory `#F7F8F3`, Surface White `#FFFFFF`, Text Charcoal `#303A38`, Border `#E8ECE7`
  ([lib/app/theme.dart](lib/app/theme.dart))
- 에셋: [brand/svg](brand/svg)(심볼, 작은 심볼, 앱 아이콘, 한글·영문 워드마크), [brand/png](brand/png)(심볼 32~1024px,
  앱 아이콘 512·1024px, favicon 16·32·48px, 워드마크)

심볼은 [lib/widgets/app_logo.dart](lib/widgets/app_logo.dart)의 `LogoGeometry` 좌표 하나로 그립니다.
앱 안 로고, Android·iOS·PWA 아이콘, favicon, 로딩 화면 이미지, SVG 원본을 모두 여기서 만듭니다.
로고를 바꾼 뒤에는 다시 만듭니다.
```sh
flutter test tool/generate_brand_icons_test.dart   # 아이콘 PNG와 SVG를 만든다
powershell -File tool/flatten_ios_icons.ps1        # iOS 아이콘의 투명도(알파) 제거
powershell -File tool/make_wordmark_png.ps1        # 워드마크 PNG(맑은 고딕·Segoe UI)
```
워드마크 SVG는 글꼴(Pretendard → Noto Sans KR → 시스템 글꼴)을 참조하므로, 인쇄물 등에 쓸 때는 글자를 윤곽선으로 바꿔 쓰세요.

## 테스트
```sh
flutter analyze
flutter test
```

# 소리노트 (sori_note)

말로 기록하는 메모장. 휴대폰이나 PC에서 마이크 버튼을 누르고 말하면 글자로 받아 적고,
버튼 한 번으로 AI가 받아쓰기 오타·띄어쓰기·문장 부호를 문맥에 맞게 다듬어 줍니다.

## 주요 기능
- **말로 메모:** 한국어 음성 인식(STT). 말하는 동안 글자가 바로 나타나고, 쓰던 글의 커서 자리에 끼워 넣습니다.
- **글로 메모:** 일반 입력도 함께 쓸 수 있습니다.
- **자동 저장:** 입력을 멈추면 잠시 뒤 서버에 저장됩니다. 저장 실패 시 다시 시도할 수 있습니다.
- **AI 다듬기:** 다듬은 결과를 원문과 비교해 보고 '적용'할 때만 바뀝니다. 적용 후 '되돌리기'도 됩니다.
- **로그인과 클라우드 저장:** 어느 기기에서든 같은 메모를 봅니다. 본인 메모만 볼 수 있습니다(RLS).
- **검색:** 메모 내용으로 찾습니다.

## 구성
| 부분 | 기술 |
|---|---|
| 앱 | Flutter (웹·Android·iOS) |
| 로그인·저장 | Supabase Auth, Postgres(`memos` 테이블, RLS) |
| 음성 인식 | `speech_to_text` (브라우저 Web Speech API, Android·iOS 기기 인식기) |
| AI 다듬기 | Supabase Edge Function `polish` → Google Gemini (`gemini-3.5-flash-lite`) |

AI 키(`GEMINI_API_KEY`)는 Edge Function 서버 비밀값으로만 관리하며 앱 코드와 저장소에는 없습니다.
앱에는 공개용 publishable 키만 빌드할 때 넣습니다.

## 실행
```sh
flutter pub get
flutter run -d chrome
```
기본으로 소리노트 Supabase 프로젝트(`aexzuuzsdlnnklqklauw`)에 연결합니다.
다른 프로젝트로 실행하려면 `--dart-define=SUPABASE_URL=...`과
`--dart-define=SUPABASE_PUBLISHABLE_KEY=...`로 덮어씁니다.

## 서버 설정 (처음 한 번)
```sh
supabase link --project-ref aexzuuzsdlnnklqklauw
supabase db push                                   # memos 테이블·RLS
supabase functions deploy polish --use-api --project-ref aexzuuzsdlnnklqklauw
```
Supabase 대시보드 → Edge Functions → Secrets에 `GEMINI_API_KEY`를 등록합니다.
선택: `GEMINI_MODEL`(모델 변경), `POLISH_DAILY_LIMIT`(사용자별 하루 다듬기 횟수, 기본 50).

## 알아 둘 점
- AI 다듬기를 누르면 그 메모 내용이 Google Gemini로 전송됩니다. 무료 등급에서는 Google이 제품 개선에 사용할 수 있습니다.
- Gemini 무료 사용량을 넘으면 유료로 넘어가지 않고 오류로 알려 줍니다.
- 웹 음성 인식은 Chrome·Edge에서 동작합니다(Chrome은 음성을 Google 서버로 보내 인식). Firefox는 지원하지 않습니다.

## 테스트
```sh
flutter analyze
flutter test
```

// Edge Function "polish": 로그인한 사용자의 메모 글을 AI(Gemini)로 다듬어 돌려준다.
//
// 요청: POST { text }  (Authorization: Bearer <사용자 JWT>)
// 응답: 성공 → 200 { text, model }
//       실패 → JSON { code } (401 로그인, 400 입력, 429 앱 일일 한도, 502/503 AI 문제)
//
// 메모를 저장하지는 않는다. 다듬은 글을 적용할지는 사용자가 앱에서 정한다.
// 비밀값(GEMINI_API_KEY, service role 키)은 서버 환경 변수로만 읽고,
// 로그에는 오류 코드만 남긴다(메모 내용과 토큰은 남기지 않는다).
import { createClient } from "@supabase/supabase-js";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { AiError, polishWithGemini } from "./gemini.ts";

const MAX_TEXT_LENGTH = 5000;
/** AI 응답을 기다리는 최대 시간(앱은 45초까지 기다린다) */
const DEADLINE_MS = 40_000;

function dailyLimit(): number {
  const value = Number(Deno.env.get("POLISH_DAILY_LIMIT") ?? "50");
  return Number.isInteger(value) && value >= 0 ? value : 50;
}

/** 한국 시간 기준 오늘 날짜(YYYY-MM-DD). record_polish_usage()와 같은 기준. */
function seoulToday(now = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Seoul",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(now);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse(405, { code: "method_not_allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    console.error("polish: server_misconfigured");
    return jsonResponse(500, { code: "server_misconfigured" });
  }
  const db = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // 1. 로그인 확인: Authorization 헤더의 JWT를 Supabase Auth로 검증한다.
  const token = req.headers.get("Authorization")?.match(/^Bearer\s+(.+)$/i)
    ?.[1];
  if (!token) return jsonResponse(401, { code: "unauthorized" });
  const { data: auth, error: authError } = await db.auth.getUser(token);
  if (authError || !auth?.user) {
    return jsonResponse(401, { code: "unauthorized" });
  }
  const userId = auth.user.id;

  // 2. 입력 확인
  let body: { text?: unknown };
  try {
    body = await req.json();
  } catch {
    return jsonResponse(400, { code: "invalid_request" });
  }
  const text = body.text;
  if (
    typeof text !== "string" || text.trim().length === 0 ||
    text.length > MAX_TEXT_LENGTH
  ) {
    return jsonResponse(400, { code: "invalid_request" });
  }

  // 3. AI 키가 서버 비밀값으로 등록되어 있는지
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) {
    console.error("polish: ai_not_configured");
    return jsonResponse(503, { code: "ai_not_configured" });
  }

  // 4. 앱 일일 한도(Google 무료 할당량과는 별개)
  const { data: usage, error: usageError } = await db
    .from("polish_usage_daily")
    .select("request_count")
    .eq("user_id", userId)
    .eq("day", seoulToday())
    .maybeSingle();
  if (usageError) {
    console.error("polish: db_error");
    return jsonResponse(500, { code: "db_error" });
  }
  if ((usage?.request_count ?? 0) >= dailyLimit()) {
    return jsonResponse(429, { code: "daily_limit_reached" });
  }

  // 5. 다듬기
  try {
    const result = await polishWithGemini({
      apiKey,
      text,
      signal: AbortSignal.timeout(DEADLINE_MS),
    });
    const { error: recordError } = await db.rpc("record_polish_usage", {
      p_user_id: userId,
      p_input_tokens: result.inputTokens,
      p_output_tokens: result.outputTokens,
    });
    if (recordError) console.error("polish: usage_failed");
    return jsonResponse(200, { text: result.text, model: result.model });
  } catch (error) {
    const code = error instanceof AiError ? error.code : "internal_error";
    console.error(`polish: ${code}`);
    const status = code === "ai_not_configured"
      ? 503
      : code === "internal_error"
      ? 500
      : 502;
    return jsonResponse(status, { code });
  }
});

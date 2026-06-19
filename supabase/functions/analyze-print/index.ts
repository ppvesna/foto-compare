import Anthropic from "npm:@anthropic-ai/sdk@0.27.0";

const SYSTEM_PROMPT = `Ты эксперт по контролю качества печати.
Тебе передают два изображения:
1. Цифровой оригинал (эталон)
2. Фотография распечатки этого файла

Твоя задача — проанализировать качество печати и найти отличия.
Отвечай ТОЛЬКО валидным JSON без markdown-блоков.`;

const USER_PROMPT = `Сравни эти два изображения. Первое — цифровой оригинал, второе — фото распечатки.

Верни JSON строго в таком формате:
{
  "verdict": "отлично" | "хорошо" | "удовлетворительно" | "плохо",
  "score": число от 0 до 100,
  "summary": "одно предложение — общий вывод",
  "issues": [
    {
      "type": "цвет" | "резкость" | "полосы" | "пятна" | "обрезка" | "яркость" | "другое",
      "severity": "низкая" | "средняя" | "высокая",
      "location": "где на изображении (например: правый нижний угол, центр, по всей площади)",
      "description": "что именно не так"
    }
  ],
  "recommendations": [
    "конкретный совет по улучшению"
  ]
}

Если печать качественная и проблем нет — issues должен быть пустым массивом.`;

Deno.serve(async (req: Request) => {
  // CORS — supabase-js добавляет apikey и x-client-info к каждому вызову
  // functions.invoke(), их нужно явно разрешить, иначе браузер блокирует
  // запрос на этапе preflight (выглядит как "Failed to fetch").
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  try {
    const { refImage, cmpImage, refMediaType, cmpMediaType } =
      await req.json();

    if (!refImage || !cmpImage) {
      return Response.json({ error: "Нужны оба изображения" }, { status: 400 });
    }

    const client = new Anthropic({
      apiKey: Deno.env.get("ANTHROPIC_API_KEY"),
    });

    const message = await client.messages.create({
      model: "claude-opus-4-7",
      max_tokens: 1024,
      system: SYSTEM_PROMPT,
      messages: [
        {
          role: "user",
          content: [
            {
              type: "image",
              source: {
                type: "base64",
                media_type: refMediaType ?? "image/jpeg",
                data: refImage,
              },
            },
            {
              type: "image",
              source: {
                type: "base64",
                media_type: cmpMediaType ?? "image/jpeg",
                data: cmpImage,
              },
            },
            { type: "text", text: USER_PROMPT },
          ],
        },
      ],
    });

    const raw = message.content[0].type === "text" ? message.content[0].text : "";

    // Парсим JSON из ответа
    let analysis;
    try {
      analysis = JSON.parse(raw);
    } catch {
      // Иногда Claude оборачивает в ```json — чистим
      const match = raw.match(/```(?:json)?\s*([\s\S]*?)```/);
      analysis = match ? JSON.parse(match[1]) : { summary: raw, issues: [] };
    }

    return Response.json(
      { analysis },
      { headers: { "Access-Control-Allow-Origin": "*" } }
    );
  } catch (e) {
    return Response.json(
      { error: String(e) },
      { status: 500, headers: { "Access-Control-Allow-Origin": "*" } }
    );
  }
});

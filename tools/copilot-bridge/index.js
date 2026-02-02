import http from "http";
import { CopilotClient } from "@github/copilot-sdk";

const port = Number(process.env.PORT || 32190);

const model = process.env.COPILOT_MODEL || "gpt-5";
let clientPromise = null;
let lastCopilotError = null;

const server = http.createServer(async (req, res) => {
  if (req.method === "GET" && req.url === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(
      JSON.stringify({
        ok: true,
        model,
        lastError: lastCopilotError,
        authReady: lastCopilotError ? false : true
      })
    );
    return;
  }

  if (req.method !== "POST" || req.url !== "/analyze") {
    res.writeHead(404, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Not found" }));
    return;
  }

  let body = "";
  req.on("data", (chunk) => {
    body += chunk;
  });

  req.on("end", async () => {
    try {
      const payload = JSON.parse(body || "{}");
      const texts = Array.isArray(payload.texts) ? payload.texts : [];

      const result = await analyzeWithFallback(texts);
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify(result));
    } catch (error) {
      res.writeHead(400, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "Invalid JSON" }));
    }
  });
});

server.listen(port, "127.0.0.1", () => {
  console.log(`[copilot-bridge] listening on http://127.0.0.1:${port}/analyze`);
  console.log(`[copilot-bridge] Copilot model: ${model}`);
});

async function analyzeWithFallback(texts) {
  try {
    const result = await analyzeWithCopilot(texts);
    if (result) {
      lastCopilotError = null;
      return result;
    }
  } catch (error) {
    lastCopilotError = error?.message || String(error);
    console.error("[copilot-bridge] Copilot analysis failed:", lastCopilotError);
  }

  const fallback = analyzeKeywords(texts);
  return {
    ...fallback,
    error: lastCopilotError
  };
}

async function analyzeWithCopilot(texts) {
  const client = await getClient();
  const session = await client.createSession({ model });

  try {
    const prompt = buildPrompt(texts);
    const response = await session.send({ prompt });
    const content = extractText(response);
    const parsed = parseJson(content);
    if (!parsed) {
      return null;
    }

    return {
      summary: parsed.summary || "Copilot themes",
      themes: Array.isArray(parsed.themes) ? parsed.themes : [],
      confidence: typeof parsed.confidence === "number" ? parsed.confidence : 0.7
    };
  } finally {
    if (typeof session.close === "function") {
      await session.close();
    } else if (typeof session.stop === "function") {
      await session.stop();
    }
  }
}

async function getClient() {
  if (!clientPromise) {
    clientPromise = (async () => {
      try {
        const client = new CopilotClient();
        await client.start();
        return client;
      } catch (error) {
        lastCopilotError = error?.message || String(error);
        throw error;
      }
    })();
  }

  return clientPromise;
}

function buildPrompt(texts) {
  const excerpt = texts.slice(0, 30).join("\n- ");
  return [
    "You are an assistant that analyzes recent dictation and memo text.",
    "Return JSON only with keys: summary (string), themes (array of strings), confidence (0-1).",
    "Be concise and avoid personal data.",
    "",
    "Recent items:",
    `- ${excerpt}`
  ].join("\n");
}

function extractText(response) {
  if (!response) {
    return "";
  }

  if (typeof response === "string") {
    return response;
  }

  if (typeof response.content === "string") {
    return response.content;
  }

  if (typeof response.text === "string") {
    return response.text;
  }

  if (response.message && typeof response.message === "string") {
    return response.message;
  }

  if (response.output && typeof response.output === "string") {
    return response.output;
  }

  return JSON.stringify(response);
}

function parseJson(text) {
  if (!text) {
    return null;
  }

  const trimmed = text.trim();
  try {
    return JSON.parse(trimmed);
  } catch {
    const start = trimmed.indexOf("{");
    const end = trimmed.lastIndexOf("}");
    if (start !== -1 && end !== -1 && end > start) {
      const slice = trimmed.slice(start, end + 1);
      try {
        return JSON.parse(slice);
      } catch {
        return null;
      }
    }
  }

  return null;
}

function analyzeKeywords(texts) {
  const stopwords = new Set([
    "the", "and", "that", "this", "with", "from", "they", "their", "there",
    "about", "would", "could", "should", "what", "when", "where", "which",
    "your", "have", "has", "had", "into", "just", "like", "been", "were",
    "will", "then", "than", "them", "some", "more", "less", "very", "much",
    "over", "under", "also", "only", "using", "used", "use", "my", "our",
    "you", "are", "for", "not", "but", "can", "did", "does", "its", "was"
  ]);

  const tokens = texts
    .join(" ")
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter((token) => token.length > 3 && !stopwords.has(token));

  const counts = new Map();
  for (const token of tokens) {
    counts.set(token, (counts.get(token) || 0) + 1);
  }

  const top = [...counts.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, 6)
    .map(([word]) => word);

  const themes = top.length
    ? [`Frequent topics: ${top.join(", ")}`]
    : ["Not enough recent content to detect themes."];

  return {
    summary: "Bridge keyword scan",
    themes,
    confidence: 0.4
  };
}

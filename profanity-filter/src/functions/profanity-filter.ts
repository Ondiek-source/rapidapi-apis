import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';
import { Filter } from 'bad-words';

const filter = new Filter();

function analyzeText(text: string): { clean: boolean; flagged_words: string[]; cleaned_text: string; severity: 'none' | 'mild' | 'moderate' | 'severe' } {
  const clean = !filter.isProfane(text);
  const cleaned_text = clean ? text : filter.clean(text);

  const flagged_words = text.split(/\s+/).filter(word => filter.isProfane(word));
  const unique = [...new Set(flagged_words.map(w => w.toLowerCase()))];
  let severity: 'none' | 'mild' | 'moderate' | 'severe';

  if (unique.length === 0) {
    severity = 'none';
  } else if (unique.length <= 2) {
    severity = 'mild';
  } else if (unique.length <= 5) {
    severity = 'moderate';
  } else {
    severity = 'severe';
  }

  return {
    clean,
    flagged_words: unique,
    cleaned_text,
    severity
  };
}

export async function profanityFilterHandler(request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  const proxySecret = request.headers.get('x-rapidapi-proxy-secret');
  const expectedSecret = process.env.RAPIDAPI_PROXY_SECRET;

  if (!expectedSecret || !proxySecret || proxySecret !== expectedSecret) {
    return {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ error: 'Unauthorized' })
    };
  }

  try {
    let text: string | undefined;

    if (request.method === 'POST') {
      const body = await request.json() as { text?: string };
      text = body?.text;
    } else {
      text = request.query.get('text') ?? undefined;
    }

    if (!text || typeof text !== 'string') {
      return {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ error: 'Missing required parameter: text' })
      };
    }

    if (text.length > 5000) {
      return {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ error: 'Text exceeds maximum length of 5000 characters' })
      };
    }

    const result = analyzeText(text);

    return {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        clean: result.clean,
        flagged_words: result.flagged_words,
        flagged_count: result.flagged_words.length,
        cleaned_text: result.cleaned_text,
        severity: result.severity,
        char_count: text.length,
        word_count: text.trim().split(/\s+/).length
      })
    };

  } catch (err) {
    context.error('profanity-filter error:', err);
    return {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ error: 'Internal server error' })
    };
  }
}

export async function healthHandler(_request: HttpRequest, _context: InvocationContext): Promise<HttpResponseInit> {
  return {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ status: 'ok' })
  };
}

app.http('profanityFilter', {
  methods: ['GET', 'POST'],
  authLevel: 'anonymous',
  handler: profanityFilterHandler
});

app.http('health', {
  methods: ['GET'],
  route: 'health',
  authLevel: 'anonymous',
  handler: healthHandler
});
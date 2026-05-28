import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';

const insults: string[] = [
  "You're smarter than you look, but that's not saying much.",
  "I admire your confidence in wearing that outfit.",
  "You have the unique ability to make everyone around you feel intelligent.",
  "You're not as bad as people say -- you're much worse.",
  "I love what you've done with your hair. How do you get it to come out of your nostrils like that?",
  "You're proof that evolution can go in reverse.",
  "You have miles of potential -- unfortunately it's all underground.",
  "I've seen people like you before, but I had to pay admission.",
  "You're not stupid; you just have bad luck thinking.",
  "You're always so refreshingly unencumbered by the thought process.",
  "You bring everyone so much joy -- when you leave the room.",
  "I would explain it to you but I left my crayons at home.",
  "You're not the dumbest person alive, but you better hope they don't die.",
  "You have a great face for radio.",
  "I like you. You remind me of when I was young and stupid.",
  "You're the reason they put instructions on shampoo bottles.",
  "You have the attention span of a golden retriever, minus the loyalty.",
  "You're a legend in your own mind.",
  "You are proof that God has a sense of humour.",
  "Your village called. They want their idiot back.",
  "You're not completely useless -- you can always serve as a bad example.",
  "I would agree with you, but then we would both be wrong.",
  "You have a great talent for stating the obvious -- badly.",
  "You're like a cloud. When you disappear, it's a beautiful day.",
  "You are living proof that practice does not always make perfect.",
  "You could grow a garden with all the manure you talk.",
  "You have a mind like a steel trap -- rusty and illegal in 37 countries.",
  "You're so open-minded your brains have fallen out.",
  "You could light up a room -- by leaving it.",
  "You're a great argument for birth order theory -- clearly not the first attempt."
];

export async function insultHandler(request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  const proxySecret = request.headers.get('x-rapidapi-proxy-secret');
  const expectedSecret = process.env.RAPIDAPI_PROXY_SECRET;

  // Reject if secret env var is not configured, or header doesn't match
  if (!expectedSecret || !proxySecret || proxySecret !== expectedSecret) {
    return {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ error: 'Unauthorized' })
    };
  }

  const randomIndex = Math.floor(Math.random() * insults.length);

  return {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      insult: insults[randomIndex],
      index: randomIndex,
      total: insults.length
    })
  };
}

// RapidAPI health check endpoint — no auth, just confirms the service is alive
export async function healthHandler(_request: HttpRequest, _context: InvocationContext): Promise<HttpResponseInit> {
  return {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ status: 'ok' })
  };
}

app.http('insult', {
  methods: ['GET'],
  authLevel: 'anonymous',
  handler: insultHandler
});

app.http('health', {
  methods: ['GET'],
  route: 'health',
  authLevel: 'anonymous',
  handler: healthHandler
});

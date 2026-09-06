export default function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Access-Control-Allow-Origin', '*');

  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET');
    return res.status(405).json({ ok: false, error: 'method_not_allowed' });
  }

  const configured = Boolean(process.env.API_FOOTBALL_KEY);
  res.status(configured ? 200 : 503).json({
    ok: configured,
    service: 'ninetyplus-backend',
    version: '0.2',
    providerConfigured: configured,
    time: new Date().toISOString()
  });
}

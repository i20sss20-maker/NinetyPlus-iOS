export default function handler(_req, res) {
  res.setHeader('Cache-Control', 'no-store');
  res.status(200).json({
    ok: true,
    service: 'ninetyplus-backend',
    providerConfigured: Boolean(process.env.API_FOOTBALL_KEY)
  });
}

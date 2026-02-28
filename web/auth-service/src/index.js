const express = require('express');
const cors = require('cors');
const { ensureRole } = require('./rbac');
const { verifyToken, resolveRole } = require('./middleware');
const authRoutes = require('./routes/auth');
const usersRoutes = require('./routes/users');

const app = express();
const PORT = parseInt(process.env.AUTH_SERVICE_PORT || '18791');

app.use(cors());
app.use(express.json());

// Health check (no auth)
app.get('/auth/health', (req, res) => {
  res.json({ status: 'ok', service: 'trinity-auth' });
});

// Auth middleware for all /auth/* routes (except health)
app.use('/auth', verifyToken, resolveRole);

// Routes
app.use('/auth', authRoutes);
app.use('/auth/users', usersRoutes);

async function ensureDefaultSuperadmin() {
  const enabled = (process.env.ENABLE_DEFAULT_SUPERADMIN || 'true') === 'true';
  if (!enabled) return;

  const rawEmail = process.env.DEFAULT_SUPERADMIN_EMAIL || 'admin@trinity.local';
  const email = rawEmail.includes('@') ? rawEmail : `${rawEmail}@trinity.local`;
  const password = process.env.DEFAULT_SUPERADMIN_PASSWORD || 'admin';
  const gotrueUrl = process.env.SUPABASE_AUTH_URL || 'http://supabase-auth:9999';
  const anonKey = process.env.SUPABASE_ANON_KEY || '';

  try {
    // Attempt signup first (idempotent if email already exists)
    const signupResp = await fetch(`${gotrueUrl}/signup`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(anonKey ? { apikey: anonKey } : {}),
      },
      body: JSON.stringify({ email, password }),
    });

    let userId = null;
    const signupText = await signupResp.text();
    if (signupText) {
      try {
        const signupJson = JSON.parse(signupText);
        userId = signupJson?.user?.id || null;
      } catch (_) {}
    }

    // If signup didn't return user (already exists), login to resolve id
    if (!userId) {
      const tokenResp = await fetch(`${gotrueUrl}/token?grant_type=password`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(anonKey ? { apikey: anonKey } : {}),
        },
        body: JSON.stringify({ email, password }),
      });
      if (tokenResp.ok) {
        const tokenJson = await tokenResp.json();
        userId = tokenJson?.user?.id || null;
      }
    }

    if (!userId) {
      const signupStatus = signupResp.status;
      console.warn(`[auth-service] Could not resolve default superadmin user id (signup status: ${signupStatus})`);
      return;
    }

    await ensureRole(userId, 'superadmin', null);
    await ensureRole(userId, 'admin', null);
    await ensureRole(userId, 'user', null);
    await ensureRole(userId, 'guest', null);

    console.log(`[auth-service] Default superadmin ensured: ${email} (${userId})`);
  } catch (err) {
    console.warn('[auth-service] Default superadmin bootstrap failed:', err.message);
  }
}

app.listen(PORT, '0.0.0.0', () => {
  console.log(`[auth-service] listening on port ${PORT}`);
  ensureDefaultSuperadmin();
});

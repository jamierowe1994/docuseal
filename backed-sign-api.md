# backed.sign × backed.crm — Integration API

This document describes everything the **backed.sign** (DocuSeal-based) side exposes for the
backed.crm OAuth 2.0 integration, and how the two platforms talk to each other.

---

## Overview

```
backed.crm                                         backed.sign (DocuSeal)
─────────────────────────────────────────────────────────────────────────
1.  User clicks "Connect to backed.sign"
    ──────────────────────────────────────────────►  GET /api/integrations/crm/authorize
                                                      • User logs in (if needed)
                                                      • One-time auth code generated
    ◄──────────────────────────────────────────────  302 → CRM_REDIRECT_URI?code=…&state=…

2.  CRM server exchanges code for a JWT
    POST /api/integrations/crm/token  ────────────►
    { client_id, client_secret, code }
    ◄──────────────────────────────────────────────  { access_token, token_type, expires_in }

3.  CRM fetches templates
    GET /api/integrations/crm/templates  ─────────►  (Authorization: Bearer <jwt>)
    ◄──────────────────────────────────────────────  { data: [...], pagination: {...} }

4.  CRM pre-fills a template
    GET /api/integrations/crm/templates/:id  ─────►  (Authorization: Bearer <jwt>)
    ◄──────────────────────────────────────────────  full template JSON
```

---

## Endpoints

### 1. `GET /api/integrations/crm/authorize`

Starts the OAuth 2.0 Authorization Code flow.  
backed.crm must redirect the **user's browser** to this URL.

#### Query Parameters

| Name           | Required | Description                                              |
|----------------|----------|----------------------------------------------------------|
| `client_id`    | ✅        | The `uid` of the registered OAuth application           |
| `redirect_uri` | ✅        | The CRM callback URL to send the code back to           |
| `state`        | ☑        | CSRF-prevention opaque value (recommended)              |

#### Behaviour

1. If the user is not signed in to backed.sign they are sent to the sign-in page and
   automatically redirected back after a successful login.
2. A single-use authorization code valid for **10 minutes** is created.
3. The user is redirected to:
   ```
   {redirect_uri}?code={code}&state={state}
   ```

---

### 2. `POST /api/integrations/crm/token`

Exchange the authorization code for a JWT access token.  
Called **server-to-server** by backed.crm (never from the browser).

#### Request Body (JSON or form-encoded)

| Field           | Required | Description                            |
|-----------------|----------|----------------------------------------|
| `client_id`     | ✅        | OAuth application UID (`CRM_CLIENT_ID`)|
| `client_secret` | ✅        | OAuth application secret               |
| `code`          | ✅        | Authorization code received in step 1  |

#### Success Response `200 OK`

```json
{
  "access_token": "<jwt>",
  "token_type":   "Bearer",
  "expires_in":   3600,
  "scope":        "read"
}
```

#### Error Responses

| Status | Body                                              | Reason                          |
|--------|---------------------------------------------------|---------------------------------|
| 401    | `{"error":"Invalid client credentials"}`          | Unknown client_id / wrong secret|
| 401    | `{"error":"Invalid or expired authorization code"}`| Code not found or already used  |

---

### 3. `GET /api/integrations/crm/templates`

Returns a list of active templates for the authenticated user.

#### Authentication

```
Authorization: Bearer <access_token>
```

#### Success Response `200 OK`

```json
{
  "data": [
    {
      "id": 42,
      "name": "NDA – Standard",
      "slug": "abc123",
      "created_at": "2025-01-10T09:00:00.000Z",
      "updated_at": "2025-04-01T12:00:00.000Z",
      "submitters": [{"name": "Signer", "uuid": "..."}],
      "fields": [...],
      "documents": [{"id": 1, "uuid": "...", "url": "https://...", "filename": "nda.pdf"}]
    }
  ],
  "pagination": {
    "count": 1,
    "next": 42,
    "prev": 42
  }
}
```

---

### 4. `GET /api/integrations/crm/templates/:id`

Returns the full body of a single template (including all fields) for pre-filling.

#### Authentication

```
Authorization: Bearer <access_token>
```

#### Success Response `200 OK`

Same structure as a single item in the `data` array above, with full `fields` detail
including names, types, positions, and options — everything needed to pre-populate
values before creating a submission.

#### Error Response

| Status | Body                            |
|--------|---------------------------------|
| 401    | `{"error":"Not authenticated"}` |
| 404    | `{"error":"Template not found"}`|

---

## Environment Variables

Set these on the **backed.sign** server:

| Variable            | Required | Description                                                        |
|---------------------|----------|--------------------------------------------------------------------|
| `CRM_CLIENT_ID`     | ☑        | OAuth UID for the CRM app. Defaults to `backed-crm` if not set.   |
| `CRM_CLIENT_SECRET` | ☑        | OAuth secret. Auto-generated on first boot if not set (log it!).  |
| `CRM_REDIRECT_URI`  | ☑        | Allowed redirect URI(s) for the CRM (space-separated for multiple).|
| `CRM_ORIGIN`        | ☑        | `Access-Control-Allow-Origin` header value. Defaults to `*`.       |

Set this on the **backed.crm** server:

| Variable          | Description                                              |
|-------------------|----------------------------------------------------------|
| `SIGN_URL`        | Base URL of backed.sign, e.g. `https://sign.backed.app` |
| `SIGN_CLIENT_ID`  | Value of `CRM_CLIENT_ID` above                          |
| `SIGN_CLIENT_SECRET` | Value of `CRM_CLIENT_SECRET` above                   |
| `SIGN_REDIRECT_URI` | The CRM callback URL (must match `CRM_REDIRECT_URI`)  |

---

## Registering the OAuth Application

On first boot, backed.sign auto-creates the CRM OAuth application from the env vars above.
Alternatively you can seed it manually in a Rails console:

```ruby
OauthApplication.create!(
  name:         'backed.crm',
  uid:          ENV['CRM_CLIENT_ID'],
  secret:       ENV['CRM_CLIENT_SECRET'],
  redirect_uri: ENV['CRM_REDIRECT_URI']
)
```

---

## backed.crm Implementation (Express.js)

Install dependencies:

```bash
npm install axios jsonwebtoken express
```

### Environment

```dotenv
SIGN_URL=https://sign.backed.app
SIGN_CLIENT_ID=backed-crm
SIGN_CLIENT_SECRET=<your-secret>
SIGN_REDIRECT_URI=https://crm.backed.app/auth/sign/callback
```

### Routes

```js
const express  = require('express');
const axios    = require('axios');
const router   = express.Router();

const SIGN_URL    = process.env.SIGN_URL;
const CLIENT_ID   = process.env.SIGN_CLIENT_ID;
const CLIENT_SECRET = process.env.SIGN_CLIENT_SECRET;
const REDIRECT_URI  = process.env.SIGN_REDIRECT_URI;

// ── Step 1: Start the OAuth flow ─────────────────────────────────────────────
// GET /auth/sign/start
router.get('/auth/sign/start', (req, res) => {
  const state = require('crypto').randomBytes(16).toString('hex');
  req.session.oauthState = state;   // store for CSRF check

  const url = new URL(`${SIGN_URL}/api/integrations/crm/authorize`);
  url.searchParams.set('client_id',    CLIENT_ID);
  url.searchParams.set('redirect_uri', REDIRECT_URI);
  url.searchParams.set('state',        state);

  res.redirect(url.toString());
});

// ── Step 2: OAuth callback ────────────────────────────────────────────────────
// GET /auth/sign/callback?code=…&state=…
router.get('/auth/sign/callback', async (req, res) => {
  const { code, state } = req.query;

  if (state !== req.session.oauthState) {
    return res.status(400).send('State mismatch – possible CSRF');
  }

  const { data } = await axios.post(
    `${SIGN_URL}/api/integrations/crm/token`,
    { client_id: CLIENT_ID, client_secret: CLIENT_SECRET, code },
    { headers: { 'Content-Type': 'application/json' } }
  );

  // Persist the access token for the current user session / CRM account
  req.session.signAccessToken = data.access_token;
  res.redirect('/dashboard');
});

// ── Step 3: Fetch templates ───────────────────────────────────────────────────
// GET /api/sign/templates
router.get('/api/sign/templates', async (req, res) => {
  const { data } = await axios.get(
    `${SIGN_URL}/api/integrations/crm/templates`,
    { headers: { Authorization: `Bearer ${req.session.signAccessToken}` } }
  );
  res.json(data);
});

// ── Step 4: Fetch a single template ──────────────────────────────────────────
// GET /api/sign/templates/:id
router.get('/api/sign/templates/:id', async (req, res) => {
  const { data } = await axios.get(
    `${SIGN_URL}/api/integrations/crm/templates/${req.params.id}`,
    { headers: { Authorization: `Bearer ${req.session.signAccessToken}` } }
  );
  res.json(data);
});

module.exports = router;
```

### JWT Verification Middleware (optional — for backend-to-backend trust)

```js
const jwt = require('jsonwebtoken');

function verifySignJwt(req, res, next) {
  const token = req.headers.authorization?.replace(/^Bearer\s+/, '');
  if (!token) return res.status(401).json({ error: 'No token' });
  try {
    req.signPayload = jwt.decode(token); // backed.sign signs with its own secret
    next();
  } catch {
    res.status(401).json({ error: 'Invalid token' });
  }
}
```

---

## CORS

backed.sign sets `Access-Control-Allow-Origin` to the value of `CRM_ORIGIN` (default `*`).
Set `CRM_ORIGIN=https://crm.backed.app` in production.

All three JSON endpoints respond to `OPTIONS` pre-flight requests automatically.

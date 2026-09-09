---
name: beasiswa-codebase
description: >-
  Current implementation state, established code patterns, and key file map
  for the Aplikasi Pendaftaran Beasiswa Pelatihan microservices project.
  Activate whenever working on any service in this repository.
---

# Beasiswa Codebase — State & Patterns Reference

Last surveyed: 2026-09-08

---

## 1. Overall Phase Status

The project is at **"Phase Foundation complete, business logic = 0%"**:
- All 6 services are scaffolded with identical structure and conventions
- `GET /health` is the only implemented endpoint on each backend service
- api-gateway: FULLY functional (JWT verify RS256, CORS, rate-limit, proxy routing all wired)
- frontend: 2 pages only (`BerandaPage` health-check, `NotFoundPage`)
- `docs/PROGRESS.md` is empty (template only — no phase entries written yet)

---

## 2. Service Status Table

| Service | Port | DB | Schema | Seed | Business Logic | Routes |
|---|---|---|---|---|---|---|
| service-rbac | 3001 | MySQL db_rbac | ✅ | ✅ roles+menus+admin | ❌ | /health only |
| service-master | 3002 | MySQL db_master | ✅ | ✅ sample beasiswa | ❌ | /health only |
| service-transaksi | 3003 | MySQL db_transaksi | ✅ | ✅ no-op | ❌ | /health only |
| service-dokumen | 3004 | PostgreSQL db_dokumen | ✅ | ✅ no-op | ❌ | /health only |
| api-gateway | 8080 | none | N/A | N/A | ✅ JWT+CORS+RL+proxy | Full routing wired |
| frontend | 5173 | N/A | N/A | N/A | ❌ | / and * only |

---

## 3. Established Code Structure (must follow for new modules)

Every backend service follows this exact structure:

```
src/
  app.ts              — createApp() factory: helmet, json, requestId, routes
  server.ts           — loadPublicKey at boot, graceful shutdown, unhandledRejection
  config/
    env.ts            — Zod-validated env loader (process.exit(1) on failure)
    database.ts       — PrismaClient singleton
  middlewares/
    auth.ts           — requireAuth(), requireRole() — reads X-User-Id/X-User-Role headers
    error-handler.ts  — Central: AppError, ZodError, SyntaxError → clean envelope
    request-id.ts     — X-Request-Id propagation + child logger per request
    validate.ts       — validate(zodSchema, 'body'|'query'|'params') middleware
    index.ts          — Re-exports
  modules/
    health/
      controller.ts   — healthController (no DB touch)
    <feature>/        — NEW modules go here
      controller.ts
      service.ts
      repository.ts
      schema.ts       — Zod schemas for request validation
  routes/
    index.ts          — router.use('/health', healthRoutes); add new routes here
    health.routes.ts
  types/
    express.d.ts      — Request augmented with requestId, log, user:{id,role}
  utils/
    bigint.ts         — BigInt JSON patch (imported first in app.ts — don't remove)
    errors.ts         — AppError hierarchy (see below)
    logger.ts         — Structured JSON logger with redaction
    response.ts       — sendSuccess(), sendError(), buildPagination()
```

**Adding a new feature module checklist:**
1. Create `src/modules/<feature>/{controller,service,repository,schema}.ts`
2. Create `src/routes/<feature>.routes.ts`
3. Register in `src/routes/index.ts`
4. If new Prisma models needed: add to `prisma/schema.prisma` and run `prisma migrate dev`

---

## 4. Key Utility APIs (already built, use as-is)

### Response helpers (`src/utils/response.ts`)
```typescript
sendSuccess(res, data, message?, statusCode?)   // → {success:true, data, message}
sendError(res, message, errors?, statusCode?)    // → {success:false, message, errors:[]}
buildPagination(page, limit, total)             // → {page, limit, total, total_pages}
```

### Error classes (`src/utils/errors.ts`)
```typescript
throw new AppError(message, statusCode)
throw new ValidationError(message, errors?)
throw new UnauthorizedError(message?)
throw new ForbiddenError(message?)
throw new NotFoundError(message?)
throw new ConflictError(message?)
throw new PayloadTooLargeError(message?)
throw new UnprocessableEntityError(message?)
```
These are caught by `error-handler.ts` and automatically formatted.

### Validate middleware (`src/middlewares/validate.ts`)
```typescript
router.post('/endpoint', validate(MyZodSchema, 'body'), myController)
```

### Auth middleware (`src/middlewares/auth.ts`)
```typescript
router.use(requireAuth())             // checks X-User-Id header (set by Gateway)
router.use(requireRole('ADMIN'))      // checks X-User-Role header
```
**Never read role from request body or JWT directly in services — Gateway injects headers.**

---

## 5. Important Gotchas & Decisions Already Made

### MySQL active_flag (service-transaksi)
The "1 active pendaftaran per user" constraint uses a MySQL GENERATED column `active_flag`
that cannot be expressed in Prisma schema syntax. It lives in:
`service-transaksi/prisma/sql/001_pendaftaran_active_flag.sql`

This SQL **must be manually inserted into the first migration file** before running
`prisma migrate deploy`. Steps:
1. `npx prisma migrate dev --name init` → creates migration file
2. Open the generated migration SQL file
3. Append the contents of `prisma/sql/001_pendaftaran_active_flag.sql`
4. Re-run migration

### No Prisma Migrations Yet
`prisma/migrations/` does not exist in any service. Schemas are written and seeds are ready.
First time setup for each service: `npx prisma migrate dev --name init && npx prisma db seed`

### Cross-Service References (no FK across databases)
- `pendaftaran.user_id` — no FK to db_rbac.users (intentional, cross-DB)
- `pendaftaran.beasiswa_id` — no FK to db_master.beasiswa (intentional)
- `pendaftaran_dokumen.dokumen_uuid` — references db_dokumen.dokumen.id by value only
- On create pendaftaran: fetch beasiswa from SERVICE_MASTER_URL and snapshot into `beasiswa_snapshot` JSON

### service-transaksi knows two other services
Env vars: `SERVICE_MASTER_URL=http://service-master:3002`, `SERVICE_DOKUMEN_URL=http://service-dokumen:3004`
Use these for cross-service HTTP calls (e.g., fetching beasiswa for snapshot, validating dokumen).

### Only service-rbac has argon2
`@node-rs/argon2` is only in service-rbac. Password hashing never happens in other services.

### Status Machine — NOT YET CREATED
`src/domain/status-machine.ts` with `assertTransition(from, to, role)` must be created in
service-transaksi before any status changes. Every status change must:
1. Call `assertTransition()` — throws ForbiddenError on illegal transition
2. Write one row to `audit_status`

### kode_pendaftaran Generation
Format: `REG-{YYYY}-{NNNN zero-padded}`. Sequence resets per year.
Strategy: MAX(kode_pendaftaran) WHERE year=current + increment, wrapped in transaction.

### Beasiswa kode Auto-Generation
`beasiswa.kode` is auto-generated from `nama` as a slug (kebab-case). Not a user input.

### Submit endpoint includes persetujuan data
`POST /api/pendaftaran/:id/submit` body carries `setuju_keabsahan` and `setuju_ketentuan`
(single checkbox on frontend maps to both). See ASUMSI-18.

### Login channel field
`POST /api/auth/login` body must include `channel: "PUBLIK" | "INTERNAL"`.
Frontend sends this automatically based on which login page is being used.
Backend uses it to enforce role restrictions (PUBLIK rejects internal roles, INTERNAL rejects CALON_PESERTA).

### Document upload flow (ASUMSI-17)
Upload is two separate calls:
1. `POST /api/dokumen/upload` → returns `dokumen_uuid`
2. `PUT /api/pendaftaran/:id/section/3` → body with `[{persyaratan_id, dokumen_uuid}]`

---

## 6. Key File Locations

| Purpose | Path |
|---|---|
| Gateway routing table | `api-gateway/src/routes/index.ts` |
| Gateway JWT middleware | `api-gateway/src/middlewares/verify-jwt.ts` |
| Gateway proxy (header injection) | `api-gateway/src/proxy/create-proxy.ts` |
| RBAC Prisma schema | `service-rbac/prisma/schema.prisma` |
| RBAC seed (roles, menus, admin) | `service-rbac/prisma/seed.ts` |
| Transaksi Prisma schema | `service-transaksi/prisma/schema.prisma` |
| active_flag SQL migration | `service-transaksi/prisma/sql/001_pendaftaran_active_flag.sql` |
| Dokumen Prisma schema | `service-dokumen/prisma/schema.prisma` |
| Docker Compose | `infra/docker-compose.yml` |
| RSA keys | `infra/keys/private.pem`, `infra/keys/public.pem` |
| Full API spec | `docs/OPENAPI.yaml` |
| DB design | `docs/ERD.md` |
| Design decisions | `docs/ASUMSI.md` |
| Mockups (UI source of truth) | `docs/mockup/*.html` |

---

## 7. Frontend Current State

- Axios client: `src/api/client.ts` — access token in **memory** (not localStorage, XSS protection)
- Dev proxy: `/api` → `http://localhost:8080` (configured in `vite.config.ts`)
- Only routes: `/` → `BerandaPage`, `*` → `NotFoundPage`
- `src/components/`, `src/hooks/`, `src/layouts/`, `src/types/` — all EMPTY

Bootstrap 5.3 is imported in `main.tsx`. Follow mockup HTML classes exactly.

---

## 8. What's Missing (Everything to Build)

**service-rbac:**
- POST /api/auth/register (create user, send verify email async)
- GET /api/auth/verify-email
- POST /api/auth/login (RS256 JWT, HttpOnly cookie for refresh)
- POST /api/auth/refresh (rotate refresh token)
- GET /api/auth/me
- GET /api/auth/my-menus
- CRUD /api/users, /api/roles, /api/menus (ADMIN only)
- Email sending (nodemailer, async, failure does NOT fail transaction)

**service-master:**
- CRUD /api/beasiswa (soft delete, auto-generate kode slug)
- CRUD /api/persyaratan
- GET /api/beasiswa/aktif (public, no auth)

**service-transaksi:**
- `src/domain/status-machine.ts` with assertTransition()
- POST /api/pendaftaran
- GET /api/pendaftaran/saya
- PUT /api/pendaftaran/:id/section/:n (sections 1-3)
- POST /api/pendaftaran/:id/submit
- GET /api/verifikasi/antrian, GET /api/verifikasi/:id
- POST /api/verifikasi/:id/keputusan (VERIFIKATOR)
- GET /api/wawancara/antrian
- POST /api/wawancara/:id/penilaian (LEMBAGA_SELEKSI, nilai_akhir computed server-side)
- GET /api/dashboard/statistik (ADMIN)
- GET /api/hasil-seleksi/export (Excel, ADMIN)

**service-dokumen:**
- POST /api/dokumen/upload (magic bytes check → ClamAV optional → SHA-256 → rename to UUID)
- GET /api/dokumen/:uuid (stream with auth check — NO static file serving)
- DELETE /api/dokumen/:uuid (only during DRAFT/REVISI)

**frontend:**
- Auth context + token refresh interceptor
- All 10 pages from docs/mockup/
- Dynamic sidebar from GET /api/auth/my-menus


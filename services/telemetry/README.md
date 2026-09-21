# Casino Brawyal — telemetry

The ingest API the game POSTs to, and the dashboard the designer reads.

The game **never** connects to Postgres. It spools events to a file under
`user://` and, when it sees the internet, POSTs a batch here. This service is
the only thing that holds a database credential, and it is what stamps the
player's IP onto a play — a desktop client cannot see its own public address,
and one it claimed would be a claim rather than a fact.

```
game.exe --HTTPS + X-Api-Key--> casino-telemetry --5432--> voicevikkidb/casino_brawyal
                                       |
                                       +-- GET /  the designer's dashboard
```

## One-time setup

**Already done** — `casino_brawyal` exists, the `casino_telemetry` role owns it
and reaches nothing else on `voicevikkidb`, and the schema is applied. This
section is here for the day it has to be redone.

Port 5432 on `voicevikkidb` is **not reachable from the office network**, so
the provisioning runs inside Azure rather than from a developer machine. Set
two one-shot secrets on the container app and restart it:

```bash
az containerapp secret set -n casino-telemetry -g abra-data-ai \
  --secrets admin-pg-url="postgresql://vikkiadmin:<pw>@voicevikkidb.postgres.database.azure.com/postgres?sslmode=require" \
            role-password="<new role password>"
az containerapp update -n casino-telemetry -g abra-data-ai \
  --set-env-vars CB_ADMIN_PG_URL=secretref:admin-pg-url \
                 CB_TELEMETRY_ROLE_PASSWORD=secretref:role-password
```

`bootstrap()` in `server.mjs` then creates the database and the role, hands
both to `casino_telemetry`, and logs what it did. It is idempotent, and it is
gated entirely on `CB_ADMIN_PG_URL` being present.

**Remove both the moment it has run.** An administrator credential for a server
that hosts ten other applications should not sit in a container app any longer
than the minute it is needed:

```bash
az containerapp update -n casino-telemetry -g abra-data-ai \
  --remove-env-vars CB_ADMIN_PG_URL CB_TELEMETRY_ROLE_PASSWORD
az containerapp secret remove -n casino-telemetry -g abra-data-ai \
  --secret-names admin-pg-url role-password
```

`provision.py` does the same job from a machine that *can* reach 5432, and
writes `CB_TELEMETRY_PG_URL` into the repo's gitignored `.env`. Neither path
applies the schema — the service does that on boot, so there is only one place
that knows the shape of the database.

## Run it locally

```bash
cd services/telemetry
npm install
CB_TELEMETRY_PG_URL="postgresql://..." \
CB_INGEST_KEY=some-write-key \
CB_DASHBOARD_KEY=some-view-key \
npm start
# dashboard: http://localhost:8080/?key=some-view-key
```

Against a throwaway database instead of the real one:

```bash
docker run -d --name cb-pg -e POSTGRES_PASSWORD=testpw \
  -e POSTGRES_DB=casino_brawyal -p 55433:5432 postgres:16-alpine
CB_TELEMETRY_PG_URL="postgresql://postgres:testpw@127.0.0.1:55433/casino_brawyal" \
CB_INGEST_KEY=testkey CB_DASHBOARD_KEY=viewkey PORT=8099 npm start
```

## Deploy

Everything lives in the resource group that already holds the database.

```bash
az containerapp up \
  --name casino-telemetry \
  --resource-group abra-data-ai \
  --environment abra-data-ai \
  --registry-server voicevikkiacr2026.azurecr.io \
  --source services/telemetry \
  --ingress external --target-port 8080 \
  --env-vars CB_TELEMETRY_PG_URL=secretref:pg-url \
             CB_INGEST_KEY=secretref:ingest-key \
             CB_DASHBOARD_KEY=secretref:view-key
```

`--source` builds through ACR Tasks, so no local Docker is needed. The server
already has an `AllowAzureServices` firewall rule, so no networking change is
required. Set `--min-replicas 0` to scale to zero; the first request after an
idle period pays a ~2 s cold start, which is invisible for a background flush.

## Endpoints

| | |
|---|---|
| `POST /v1/ingest` | `X-Api-Key` header, JSON batch. Returns `202 {accepted, duplicate}`. |
| `GET /healthz` | Liveness, and the client's connectivity probe. |
| `GET /` | The dashboard. `?key=` must match `CB_DASHBOARD_KEY`. |
| `GET /api/stats` | The JSON behind the dashboard. Same key. |
| `DELETE /api/install/<uuid>` | Erases one player: the install row and, by cascade, every play, run, combat and move under it. Same key. Returns `{erased: 0\|1}`. |

An install id becomes personal data the moment the service stamps an IP on it
(CJEU C-582/14), so there has to be a way to remove one — and nobody outside
Azure can open a `psql` session against this server. The accepted `batch_id`s
are deliberately left behind: a client that resends an old batch after an
erasure writes nothing, so the data cannot come back on its own.

## About the keys

`CB_INGEST_KEY` ships inside the game and **is not a secret** — the PCK is
unencrypted, so anyone who unzips the build can read it. What it buys them is
the ability to POST junk rows into this one database: no read access, no reach
into the other ten databases on the server, no Postgres credential. Abuse is
bounded by a per-IP rate limit and hard size caps; rotating it is a one-line
container update plus a one-line change in the game.

`CB_DASHBOARD_KEY` is separate and does not ship anywhere.

## Delivery guarantees

At-least-once on the wire, exactly-once in storage. The client keeps spooled
lines until it sees a 2xx, so a lost response means a resend — and every batch
carries a `batch_id` (PK on `ingest_batches`) while every move carries
`(run_id, seq)` (unique). A replay writes nothing.

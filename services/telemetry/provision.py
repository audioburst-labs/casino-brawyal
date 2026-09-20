#!/usr/bin/env python3
"""One-shot: create the telemetry role on voicevikkidb and hand it the database.

Run this ONCE, yourself, because it needs the server administrator password and
that should not pass through anything but your own shell.

    pip install psycopg[binary]
    python services/telemetry/provision.py

It reads the admin credential from an existing .env (default: the
procurement-demo repo's), creates a `casino_telemetry` role that can reach
`casino_brawyal` and nothing else on the server, and writes the resulting
connection string into this repo's gitignored .env as CB_TELEMETRY_PG_URL.

The schema itself is NOT applied here — the ingest service runs
`migrations/*.sql` on boot, so there is only ever one place that knows the
shape of the database.
"""
import argparse
import io
import os
import re
import secrets
import string
import sys
import urllib.parse as up

try:
    import psycopg
except ImportError:
    sys.exit("psycopg is required:  pip install psycopg[binary]")

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_ADMIN_ENV = os.path.join(
    os.path.expanduser("~"), "OneDrive - abra-IT", "repos", "procurement-demo", ".env")
DB = "casino_brawyal"
ROLE = "casino_telemetry"


def read_admin_url(path: str) -> str:
    if not os.path.exists(path):
        sys.exit("admin .env not found: %s" % path)
    for line in io.open(path, encoding="utf-8"):
        if line.startswith("DATABASE_URL="):
            return line.split("=", 1)[1].strip().strip('"').strip("'")
    sys.exit("no DATABASE_URL in %s" % path)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--admin-env", default=DEFAULT_ADMIN_ENV,
                    help="a .env holding DATABASE_URL for the server admin")
    ap.add_argument("--game-env", default=os.path.join(REPO, ".env"),
                    help="where to write CB_TELEMETRY_PG_URL")
    args = ap.parse_args()

    parts = up.urlparse(read_admin_url(args.admin_env))
    admin = {
        "host": parts.hostname,
        "port": parts.port or 5432,
        "user": up.unquote(parts.username or ""),
        "password": up.unquote(parts.password or ""),
        "sslmode": "require",
    }
    print("server   : %s" % admin["host"])
    print("admin    : %s" % admin["user"])

    alphabet = string.ascii_letters + string.digits
    password = "".join(secrets.choice(alphabet) for _ in range(40))

    with psycopg.connect(dbname="postgres", autocommit=True, **admin) as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT 1 FROM pg_database WHERE datname = %s", (DB,))
            if cur.fetchone() is None:
                cur.execute('CREATE DATABASE "%s"' % DB)
                print("database : %s created" % DB)
            else:
                print("database : %s already there" % DB)

            cur.execute("SELECT 1 FROM pg_roles WHERE rolname = %s", (ROLE,))
            if cur.fetchone() is None:
                cur.execute('CREATE ROLE "%s" WITH LOGIN PASSWORD %%s' % ROLE,
                            (password,))
                print("role     : %s created" % ROLE)
            else:
                cur.execute('ALTER ROLE "%s" WITH LOGIN PASSWORD %%s' % ROLE,
                            (password,))
                print("role     : %s already existed, password rotated" % ROLE)

            # It owns its own database and has no rights anywhere else.
            cur.execute('GRANT CONNECT ON DATABASE "%s" TO "%s"' % (DB, ROLE))
            cur.execute('ALTER DATABASE "%s" OWNER TO "%s"' % (DB, ROLE))
            print("grants   : %s owns %s, and nothing else" % (ROLE, DB))

    url = "postgresql://%s:%s@%s:%d/%s?sslmode=require" % (
        ROLE, up.quote(password, safe=""), admin["host"], admin["port"], DB)
    existing = ""
    if os.path.exists(args.game_env):
        existing = io.open(args.game_env, encoding="utf-8").read()
    existing = re.sub(r"(?m)^CB_TELEMETRY_PG_URL=.*\n?", "", existing)
    if existing and not existing.endswith("\n"):
        existing += "\n"
    io.open(args.game_env, "w", encoding="utf-8", newline="\n").write(
        existing + "CB_TELEMETRY_PG_URL=" + url + "\n")
    print("wrote    : CB_TELEMETRY_PG_URL -> %s  (gitignored)" % args.game_env)
    print("\nNext:  cd services/telemetry && npm install && npm start")


if __name__ == "__main__":
    main()

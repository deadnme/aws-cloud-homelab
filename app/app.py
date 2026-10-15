"""Harbor Point client portal: a deliberately tiny web app for the AWS lab.

Routes:
  /        HTML page showing which instance and Availability Zone answered
  /health  plain "ok" for the load balancer health check (no database check,
           on purpose: one slow database must not make every server "unhealthy")
  /db      reads the database settings from SSM Parameter Store and runs a query

Standard library only, apart from boto3 and psycopg, which are imported inside
/db so that / and /health keep working even when the database part is broken.
Runs on Python 3.9+ (the Amazon Linux 2023 default).
"""
import html
import os
import socket
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = os.environ.get("HOST", "127.0.0.1")  # nginx proxies to us on the instance
PORT = int(os.environ.get("PORT", "8080"))
IMDS = "http://169.254.169.254/latest"

PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Harbor Point Client Portal</title>
<style>body{font-family:system-ui,sans-serif;max-width:40rem;margin:3rem auto;padding:0 1rem;color:#1d2b36}
code{background:#eef2f5;padding:.1rem .3rem;border-radius:4px}</style></head>
<body><h1>Harbor Point Client Portal</h1>
<p>Served by <code>%(instance)s</code> in <code>%(az)s</code> (host <code>%(host)s</code>).</p>
<p>Refresh a few times: the load balancer spreads requests across both Availability Zones.</p>
<p><a href="/db">Database check</a> &middot; <a href="/health">Health check</a></p>
</body></html>
"""


def imds(path):
    """Read instance metadata with IMDSv2 (token first). Returns "unknown" off EC2."""
    try:
        token_req = urllib.request.Request(
            IMDS + "/api/token", method="PUT",
            headers={"X-aws-ec2-metadata-token-ttl-seconds": "60"})
        token = urllib.request.urlopen(token_req, timeout=1).read().decode()
        req = urllib.request.Request(
            IMDS + "/meta-data/" + path, headers={"X-aws-ec2-metadata-token": token})
        return urllib.request.urlopen(req, timeout=1).read().decode()
    except OSError:
        return "unknown"


def db_status():
    import boto3
    import psycopg

    names = ["/harbor/db/host", "/harbor/db/name", "/harbor/db/user", "/harbor/db/password"]
    resp = boto3.client("ssm").get_parameters(Names=names, WithDecryption=True)
    if resp["InvalidParameters"]:
        return 503, "Database not configured yet (missing %s). Build doc 06 first." % (
            ", ".join(resp["InvalidParameters"]))
    p = {x["Name"].rsplit("/", 1)[1]: x["Value"] for x in resp["Parameters"]}

    with psycopg.connect(host=p["host"], dbname=p["name"], user=p["user"],
                         password=p["password"], connect_timeout=5) as conn:
        conn.execute("CREATE TABLE IF NOT EXISTS clients (id serial PRIMARY KEY, name text NOT NULL)")
        if conn.execute("SELECT count(*) FROM clients").fetchone()[0] == 0:
            conn.execute("INSERT INTO clients (name) VALUES "
                         "('Reyes Bakery'), ('Lim Hardware'), ('Santos Dental Clinic')")
        rows = conn.execute("SELECT count(*) FROM clients").fetchone()[0]
        version = conn.execute("SHOW server_version").fetchone()[0]
    return 200, "Connected to PostgreSQL %s at %s. The clients table has %d rows." % (
        version, p["host"], rows)


class Handler(BaseHTTPRequestHandler):
    def reply(self, code, body, ctype):
        data = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype + "; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/health":
            return self.reply(200, "ok\n", "text/plain")
        if self.path == "/db":
            try:
                code, msg = db_status()
            except Exception as e:  # lab only: show the real error, it's a troubleshooting lab
                code, msg = 500, "Database error: %s: %s" % (type(e).__name__, e)
            return self.reply(code, msg + "\n", "text/plain")
        if self.path == "/":
            page = PAGE % {k: html.escape(v) for k, v in {
                "instance": imds("instance-id"),
                "az": imds("placement/availability-zone"),
                "host": socket.gethostname()}.items()}
            return self.reply(200, page, "text/html")
        self.reply(404, "not found\n", "text/plain")


if __name__ == "__main__":
    print("Harbor Point portal listening on %s:%d" % (HOST, PORT), flush=True)
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()

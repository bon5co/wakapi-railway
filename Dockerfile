# Wakapi for Railway.
#
# Wakapi (muety/wakapi, MIT) is a self-hosted, WakaTime-compatible backend for coding statistics: editors send
# heartbeats to its REST API and it reports time per project, language and editor. The upstream image is distroless
# (a single static binary, no shell), correct as shipped, but a fresh public Railway deploy driven by an agent needs
# things it does not do:
#
# 1. A new Wakapi instance has no users and open registration: the first visitor to the public URL registers and
#    becomes the administrator. railway-entrypoint.sh creates the administrator and closes sign-up before the server
#    listens on the public port.
# 2. Wakapi's API accepts only a per-user API key that is generated at registration and shown in the web interface,
#    so a deploy has no API credential until someone signs in. The entrypoint seeds the administrator's API key
#    from WAKAPI_API_KEY.
# 3. Wakapi reads its listen port from WAKAPI_PORT, not PORT, and binds loopback by default; the entrypoint maps
#    Railway's injected PORT and binds IPv4 and IPv6 so the edge and the private network can both reach it.
# 4. The script fails fast on a missing or malformed secret instead of booting an instance nobody can reach by API.
#
# The application is otherwise unchanged: same binary, same migrations, same configuration keys. The binary is
# copied out of the pinned upstream image into a base with a shell, curl and the sqlite3 client.
# upstream: muety/wakapi
FROM ghcr.io/muety/wakapi:2.18.2@sha256:7a14217db1b6a47816c8d8d0590cc40fa12fd409dfed6c194bbb4cd50f43d913 AS upstream

# upstream: none (Alpine base for the shell the distroless upstream image lacks)
FROM alpine:3.22
RUN apk add --no-cache curl sqlite ca-certificates tzdata
COPY --from=upstream /app /app
COPY railway-entrypoint.sh /app/railway-entrypoint.sh
RUN chmod +x /app/railway-entrypoint.sh && mkdir -p /data

WORKDIR /app
ENV ENVIRONMENT=prod \
    WAKAPI_DB_TYPE=sqlite3 \
    WAKAPI_DB_NAME=/data/wakapi.db \
    WAKAPI_ALLOW_SIGNUP=false \
    WAKAPI_INVITE_CODES=false

EXPOSE 3000
ENTRYPOINT ["/app/railway-entrypoint.sh"]

# wakapi-railway

Wrapper over the upstream `muety/wakapi` image (2.18.2) for Railway. It adds a shell and the sqlite3 client to the distroless upstream image, creates the administrator on first boot, seeds its API key from `WAKAPI_API_KEY`, closes sign-up and binds Railway's `PORT`. Published to `ghcr.io/bon5co/wakapi-railway`.

package com.marina.marina.data.auth

/**
 * Local (offline) administrator credential rule for the login screen.
 *
 * The app is local-first: Room is the source of truth and the Cloudflare
 * Worker is a sync backend. Authenticating the built-in administrator
 * must therefore never depend on network availability — the check below
 * runs before any remote call so `admin` / `admin` always unlocks the app,
 * even in airplane mode or when the Worker is unreachable.
 *
 * Any other username/password combination still goes through the remote
 * `/api/auth/login` flow unchanged.
 */
object LocalAdminAuth {

    const val ADMIN_USERNAME = "admin"
    const val ADMIN_PASSWORD = "admin"

    /**
     * Token persisted after a successful local admin login so that
     * [com.marina.marina.data.auth.AuthRepositoryImpl.restoreSession]
     * can rebuild the session across process restarts. It is deliberately
     * namespaced (`local:`) to be distinguishable from Worker JWTs.
     */
    const val LOCAL_ADMIN_TOKEN = "local:admin-session"

    /**
     * True when the supplied credentials are exactly the built-in
     * administrator pair. The username is trimmed defensively (the login
     * use-case already trims it); the password must match exactly.
     */
    fun matches(username: String, password: String): Boolean =
        username.trim() == ADMIN_USERNAME && password == ADMIN_PASSWORD

    /** True for tokens minted by [LOCAL_ADMIN_TOKEN] (vs. Worker JWTs). */
    fun isLocalAdminToken(token: String?): Boolean =
        token == LOCAL_ADMIN_TOKEN
}

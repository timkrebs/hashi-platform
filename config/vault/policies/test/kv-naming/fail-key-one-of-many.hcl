# Ein einziger schlechter Key unter mehreren guten reicht. Ohne diesen Fall
# koennte `any` statt `all` in der Policy stehen und niemand merkte es.
global "request" {
  value = {
    operation = "create"
    path      = "kv/data/backend/auth-service/signing-secret"
    data = {
      data = {
        APP_TOKEN   = "…"
        APP_DB_USER = "…"
        LEGACY_KEY  = "…"
      }
    }
  }
}

test {
  rules = {
    main                  = false
    keys_match_convention = false
  }
}

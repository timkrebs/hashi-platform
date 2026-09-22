# update wird genauso geprueft wie create.
global "request" {
  value = {
    operation = "update"
    path      = "kv/data/frontend/web/api-token-secret"
    data      = { data = { APP_TOKEN = "…" } }
  }
}

test { rules = { main = true } }

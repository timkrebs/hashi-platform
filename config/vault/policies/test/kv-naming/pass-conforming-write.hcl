# Der Normalfall: drei Segmente, bekanntes Team, -secret am Ende, Keys in
# UPPER_SNAKE_CASE mit APP_-Praefix.
global "request" {
  value = {
    operation = "create"
    path      = "kv/data/backend/auth-service/signing-secret"
    data = {
      data = {
        APP_SIGNING_KEY = "…"
        APP_DB_PASSWORD = "…"
      }
    }
  }
}

test { rules = { main = true } }

# Anforderung 1 nennt patch ausdruecklich neben create und update: ein KV-v2
# Patch fuegt Keys zu einem bestehenden Secret hinzu und kann damit genauso
# einen nicht konformen Key einschleusen. Ohne diesen Fall koennte patch aus
# write_operations verschwinden, ohne dass ein Test es merkt.
global "request" {
  value = {
    operation = "patch"
    path      = "kv/data/backend/auth-service/signing-secret"
    data      = { data = { legacy_key = "…" } }
  }
}

test {
  rules = {
    main                  = false
    is_kv_write           = true
    keys_match_convention = false
  }
}

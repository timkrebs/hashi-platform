# "large" is allowed since the dev cluster moved to t3.large. Pins the new
# boundary: without this, only the fail cases exist and the ceiling could be
# raised again without a test noticing.
mock "tfplan/v2" {
  module {
    source = "../../testdata/tfplan-large-allowed.sentinel"
  }
}

test {
  rules = {
    main = true
  }
}

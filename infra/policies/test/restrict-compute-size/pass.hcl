mock "tfplan/v2" {
  module {
    source = "../../testdata/tfplan-compliant.sentinel"
  }
}

test {
  rules = {
    main = true
  }
}

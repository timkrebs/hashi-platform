mock "tfplan/v2" {
  module {
    source = "../../testdata/tfplan-missing-tags.sentinel"
  }
}

test {
  rules = {
    main = false
  }
}

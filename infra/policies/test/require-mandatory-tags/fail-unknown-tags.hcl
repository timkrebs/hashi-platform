mock "tfplan/v2" {
  module {
    source = "../../testdata/tfplan-unknown-tags.sentinel"
  }
}

test {
  rules = {
    main = false
  }
}

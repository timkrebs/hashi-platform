mock "tfplan/v2" {
  module {
    source = "../../testdata/tfplan-unknown-compute.sentinel"
  }
}

test {
  rules = {
    main = false
  }
}

mock "tfplan/v2" {
  module {
    source = "../../testdata/tfplan-large-compute.sentinel"
  }
}

test {
  rules = {
    main = false
  }
}

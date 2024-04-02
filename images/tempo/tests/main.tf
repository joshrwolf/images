terraform {
  required_providers {
    oci       = { source = "chainguard-dev/oci" }
    imagetest = { source = "chainguard-dev/imagetest" }
  }
}

variable "digests" {
  description = "The image digest to run tests over."
  type = object({
    tempo = string
  })
}

data "oci_string" "ref" {
  for_each = var.digests
  input    = each.value
}

data "imagetest_inventory" "this" {}

resource "imagetest_harness_k3s" "this" {
  name      = "tempo"
  inventory = data.imagetest_inventory.this
}

module "helm" {
  source = "../../../tflib/imagetest/helm"

  name      = "tempo"
  namespace = "tempo"
  repo      = "https://grafana.github.io/helm-charts"
  chart     = "tempo"

  values = {
    tempo = {
      repository = data.oci_string.ref["tempo"].registry_repo
      tag        = data.oci_string.ref["tempo"].pseudo_tag
    }
  }
}

resource "imagetest_feature" "basic" {
  name        = "Basic"
  description = "Test a basic installation of the tempo with Helm chart."
  harness     = imagetest_harness_k3s.this

  steps = [
    {
      name = "Helm install"
      cmd  = module.helm.install_cmd
    }
  ]

  labels = {
    type = "k8s",
  }
}




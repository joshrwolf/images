terraform {
  required_providers {
    oci       = { source = "chainguard-dev/oci" }
    helm      = { source = "hashicorp/helm" }
    imagetest = { source = "chainguard-dev/imagetest" }
  }
}

variable "digests" {
  description = "The image digests to run tests over."
  type = object({
    server                  = string
    agent                   = string
    oidc-discovery-provider = string
  })
}

data "oci_string" "ref" {
  for_each = var.digests
  input    = each.value
}

resource "imagetest_harness_k3s" "this" {}
resource "imagetest_harness_teardown" "this" { harness = imagetest_harness_k3s.this.id }

module "helm_crd" {
  source = "../../../tflib/imagetest/helm"

  name  = "spire-crds"
  chart = "spire-crds"
  repo  = "https://spiffe.github.io/helm-charts-hardened/"
}

module "helm" {
  source = "../../../tflib/imagetest/helm"

  name      = "spire"
  namespace = "spire-system"
  chart     = "spire"
  repo      = "https://spiffe.github.io/helm-charts-hardened/"

  values = {
    spire-server = {
      enabled = true
      image = {
        registry   = data.oci_string.ref["server"].registry
        repository = data.oci_string.ref["server"].repo
        tag        = data.oci_string.ref["server"].pseudo_tag
      }
    }
    spire-agent = {
      enabled = true
      image = {
        registry   = data.oci_string.ref["agent"].registry
        repository = data.oci_string.ref["agent"].repo
        tag        = data.oci_string.ref["agent"].pseudo_tag
      }
    }
    spiffe-oidc-discovery-provider = {
      enabled = true
      image = {
        registry   = data.oci_string.ref["oidc-discovery-provider"].registry
        repository = data.oci_string.ref["oidc-discovery-provider"].repo
        tag        = data.oci_string.ref["oidc-discovery-provider"].pseudo_tag
      }
      config = {
        acme = {
          tosAccepted = true
        }
      }
    }
  }
}

resource "imagetest_feature" "basic" {
  name        = "SpireBasic"
  description = "Basic spire/spiffe functionality via the helm chart."

  setup {
    cmd = module.helm_crd.install_cmd
  }

  setup {
    cmd = module.helm.install_cmd
  }
}

resource "imagetest_env" "this" {
  harness = imagetest_harness_k3s.this.id

  test {
    features = [
      imagetest_feature.basic.id,
    ]
  }

  labels = {
    cloud = "any"
    size  = "small"
    type  = "k8s"
  }
}

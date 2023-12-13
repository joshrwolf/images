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
    acmesolver = string
    cainjector = string
    controller = string
    webhook    = string
  })
}

variable "skip_crds" {
  description = "Used to deconflict between multiple installations within the same cluster."
  default     = false
}

data "oci_string" "ref" {
  for_each = var.digests
  input    = each.value
}

resource "imagetest_harness_k3s" "this" {}
resource "imagetest_harness_teardown" "this" { harness = imagetest_harness_k3s.this.id }

module "helm" {
  source = "../../../tflib/imagetest/helm"

  name  = "cert-manager"
  chart = "cert-manager"
  repo  = "https://charts.jetstack.io"

  values = {
    installCRDs = true
    image = {
      repository = data.oci_string.ref["controller"].registry_repo
      tag        = data.oci_string.ref["controller"].pseudo_tag
    }
    acmesolver = {
      image = {
        repository = data.oci_string.ref["acmesolver"].registry_repo
        tag        = data.oci_string.ref["acmesolver"].pseudo_tag
      }
    }
    cainjector = {
      image = {
        repository = data.oci_string.ref["cainjector"].registry_repo
        tag        = data.oci_string.ref["cainjector"].pseudo_tag
      }
    }
    webhook = {
      image = {
        repository = data.oci_string.ref["webhook"].registry_repo
        tag        = data.oci_string.ref["webhook"].pseudo_tag
      }
    }
  }
}

resource "imagetest_feature" "basic" {
  name        = "CertManagerBasic"
  description = "Basic cert-manager functionality."

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

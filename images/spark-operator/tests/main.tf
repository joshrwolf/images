terraform {
  required_providers {
    oci       = { source = "chainguard-dev/oci" }
    imagetest = { source = "chainguard-dev/imagetest" }
  }
}

variable "digest" {
  description = "The image digest to run tests over."
}

data "oci_string" "ref" {
  input = var.digest
}

# resource "random_pet" "suffix" {}
#
# resource "helm_release" "spark" {
#   name             = "spark"
#   repository       = "oci://registry-1.docker.io/bitnamicharts"
#   chart            = "spark"
#   namespace        = "spark-${random_pet.suffix.id}"
#   create_namespace = true
#
#   values = [jsonencode({
#     worker = {
#       replicaCount = 1
#     }
#   })]
# }
#
# resource "helm_release" "operator" {
#   depends_on       = [resource.helm_release.spark]
#   name             = "spark-operator"
#   repository       = "https://googlecloudplatform.github.io/spark-on-k8s-operator"
#   chart            = "spark-operator"
#   namespace        = resource.helm_release.spark.namespace
#   create_namespace = true
#   values = [jsonencode({
#     image = {
#       registry   = ""
#       repository = data.oci_string.ref.registry_repo,
#       tag        = data.oci_string.ref.pseudo_tag
#     },
#   })]
# }
#
# data "oci_exec_test" "run-tests" {
#   depends_on  = [resource.helm_release.operator]
#   digest      = var.digest
#   script      = "./test-spark.sh"
#   working_dir = path.module
#
#   env {
#     name  = "NAMESPACE"
#     value = resource.helm_release.spark.namespace
#   }
#   env {
#     name  = "IMAGE"
#     value = "${data.oci_string.ref.registry_repo}:${data.oci_string.ref.pseudo_tag}"
#   }
# }

data "imagetest_inventory" "this" {}

resource "imagetest_harness_k3s" "this" {
  name      = "spark-operator"
  inventory = data.imagetest_inventory.this

  sandbox = {
    mounts = [
      {
        source      = path.module
        destination = "/tests"
      }
    ]

    envs = {
      NAMESPACE = "spark"
      IMAGE     = "${data.oci_string.ref.registry_repo}:${data.oci_string.ref.pseudo_tag}"
    }
  }
}

module "spark_helm" {
  source = "../../../tflib/imagetest/helm"

  name      = "spark"
  namespace = "spark"
  repo      = "https://charts.bitnami.com/bitnami"
  chart     = "spark"

  values = {
    worker = {
      replicaCount = 1
    }
  }
}

module "operator_helm" {
  source = "../../../tflib/imagetest/helm"

  name      = "spark-operator"
  namespace = "spark"
  repo      = "https://googlecloudplatform.github.io/spark-on-k8s-operator"
  chart     = "spark-operator"

  values = {
    image = {
      registry   = ""
      repository = data.oci_string.ref.registry_repo
      tag        = data.oci_string.ref.pseudo_tag
    }
  }
}

resource "imagetest_feature" "basic" {
  harness     = imagetest_harness_k3s.this
  name        = "Basic"
  description = "Basic functionality of the cert-manager helm chart."

  steps = [
    {
      name = "Install spark"
      cmd  = module.spark_helm.install_cmd
    },
    {
      name = "Install spark operator"
      cmd  = module.operator_helm.install_cmd
    },
    {
      name = "Run tests"
      cmd  = "/tests/test-spark.sh"
    },
  ]

  labels = {
    type = "k8s"
  }
}

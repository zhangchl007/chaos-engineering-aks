# Reviewed Linux baseline; ZIP hashes from official publisher SHA256SUMS.
provider "registry.terraform.io/azure/azapi" {
  version     = "2.14.0"
  constraints = "2.14.0"
  hashes = ["zh:5b29d4767193fd159f537aa210d4d0440eea5b56509ea419ae23d2016e45529d"]
}
provider "registry.terraform.io/hashicorp/azurerm" {
  version     = "4.55.0"
  constraints = "4.55.0"
  hashes = [
    "h1:Kn9pyZEYGAAfo8q3LwIUfRUULkXgoBjVykpkslSps2o=",
    "zh:58daec6f8ab1ebf60755585084a3390a25fbae2f11b39ea925037b0d510faf9b",
  ]
}

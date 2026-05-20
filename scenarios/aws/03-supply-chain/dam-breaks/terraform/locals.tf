resource "random_id" "scenario_suffix" {
  byte_length = 4
}

locals {
  suffix = random_id.scenario_suffix.hex
  name   = var.scenario_name
}

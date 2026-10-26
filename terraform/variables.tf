variable "region" {
  description = "AWS Region for every lab resource. Sydney: the Region assigned to this new-AWS-experience project, and the only one it can build in (see docs/design-decisions.md D-01)."
  type        = string
  default     = "ap-southeast-2"
}

variable "instance_type" {
  description = "App server size. t4g.micro is Arm (Graviton): about 20% cheaper than the x86 t3.micro."
  type        = string
  default     = "t4g.micro"
}

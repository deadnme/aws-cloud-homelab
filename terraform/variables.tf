variable "region" {
  description = "AWS Region for every lab resource. Singapore: the oldest Southeast Asia Region and parent of the Manila Local Zone (see docs/design-decisions.md D-01)."
  type        = string
  default     = "ap-southeast-1"
}

variable "instance_type" {
  description = "App server size. t4g.micro is Arm (Graviton): about 20% cheaper than the x86 t3.micro."
  type        = string
  default     = "t4g.micro"
}

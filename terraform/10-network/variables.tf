variable "region" {
  description = "AWS region of the whole project."
  type        = string
  default     = "eu-west-1"
}

variable "vpc_cidr" {
  description = "IP range of the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

# The NAT gateway costs ~$1/day, set to false when nothing private needs the internet
variable "enable_nat_gateway" {
  description = "Daily switch: true creates the NAT gateway (about $1 a day); false removes it."
  type        = bool
  default     = true
}

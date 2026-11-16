variable "region" {
  description = "AWS region of the whole project."
  type        = string
  default     = "eu-west-1"
}

variable "domain" {
  description = "The public DNS zone (it must already exist in Route 53)."
  type        = string
  default     = "manovaturi.com"
}

variable "vault_data_az" {
  description = "Availability zone of the Vault data volume; the EKS node group must run in the same zone."
  type        = string
  default     = "eu-west-1a"
}

variable "budget_email" {
  description = "Where the budget alarms are sent."
  type        = string
}

variable "daily_budget_usd" {
  description = "A day that costs more than this e-mails you (a working day is about 3 to 4 dollars, a forgotten shutdown about 9)."
  type        = string
  default     = "6"
}

variable "monthly_budget_usd" {
  description = "A month that reaches 80 percent of this (or is forecast to exceed it) e-mails you."
  type        = string
  default     = "60"
}

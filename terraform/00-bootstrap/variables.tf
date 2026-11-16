variable "region" {
  description = "AWS region of the whole project."
  type        = string
  default     = "eu-west-1"
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket that holds the state of every layer."
  type        = string
  default     = "mano-tf-state-bucket"
}

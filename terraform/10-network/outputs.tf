output "vpc_id" {
  description = "ID of the VPC."
  value       = module.vpc.vpc_id
}
output "vpc_cidr" {
  description = "IP range of the VPC."
  value       = module.vpc.vpc_cidr_block
}
output "public_subnet_ids" {
  description = "IDs of the public subnets."
  value       = module.vpc.public_subnets
}
output "private_subnet_ids" {
  description = "IDs of the private subnets, in the order of the zones (the first one is eu-west-1a)."
  value       = module.vpc.private_subnets
}
output "database_subnet_group_name" {
  description = "Name of the database subnet group (for RDS, not used yet)."
  value       = module.vpc.database_subnet_group_name
}
output "nat_public_ips" {
  description = "Public IPs of the NAT gateway (they change every day; GitLab and Jenkins allow them)."
  value       = module.vpc.nat_public_ips
}
# DEFINE DEFAULT VARIABLES HERE

variable "instance_type" {
  description = "Instance Type"
  type        = string
}

variable "ami" {
  description = "AMI ID"
  type        = string
}

variable "key_name" {
  description = "Key Pair"
  type        = string
}

variable "volume_size" {
  description = "Volume size (GiB)"
  type        = number
  default     = 30
}

variable "region_name" {
  description = "AWS Region"
  type        = string
}

variable "server_name" {
  description = "EC2 Server Name"
  type        = string
}

variable "admin_cidr" {
  description = "CIDR (single IP or range) allowed to SSH to the server (e.g. \"203.0.113.5/32\"). Set to a trusted IP or CIDR. Do NOT leave as 0.0.0.0/0 in production."
  type        = string
  default     = "203.0.113.5/32"
}
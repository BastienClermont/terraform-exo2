variable "aws_region" {
  type = string
  default = "us-east-1"
}

variable "aws_access_key" {
  sensitive = true
  default = "YOUR_ACCESS_KEY"
}
variable "aws_secret_key" {
  sensitive = true
  default = "YOUR_SECRET_KEY"
}

variable "ami_id" {
  default = "ami-0a5d78b22a14f0151"
}

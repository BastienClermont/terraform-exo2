variable "aws_access_key" {
  sensitive = true
  type =  string
  default = "YOUR_ACCESS_KEY"
}
variable "aws_secret_key" {
  sensitive = true
  type =  string
  default = "YOUR_SECRET_KEY"
}

source "amazon-ebs" "exo2" {
  access_key      = var.aws_access_key
  secret_key      = var.aws_secret_key
  ssh_timeout     = "30s"
  region          = "us-east-1"
  // amazon linux 2
  source_ami      = "ami-026b57f3c383c2eec"
  ssh_username    = "ec2-user"
  ami_name        = "exo2-packer-nginx"
  instance_type   = "t2.micro"
  skip_create_ami = false

}

build {
  sources = [
    "source.amazon-ebs.exo2"
  ]
  provisioner "ansible" {
    use_proxy = false
    playbook_file = "playbook.yaml"
    #extra_arguments = ["--key-file='./bastien.pem'"]
  }
}
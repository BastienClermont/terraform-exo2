terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

resource "aws_vpc" "exo2" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "exo2"
    Description = "sample vpc with 2 public subnets in 2 availability zones and a network load balancer for high availability"
  }

}

resource "aws_internet_gateway" "inet" {
  vpc_id = aws_vpc.exo2.id
  tags = {
    Name = "exo2 internet gateway"
  }
}

resource "aws_default_route_table" "public" {
  default_route_table_id = aws_vpc.exo2.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.inet.id
  }

  tags = {
    Name = "public route table"
  }
}

resource "aws_subnet" "a" {
  vpc_id            = aws_vpc.exo2.id
  cidr_block        = "10.0.0.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "public subnet a"
  }

  map_public_ip_on_launch = true
}

resource "aws_subnet" "b" {
  vpc_id            = aws_vpc.exo2.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1b"


  tags = {
    Name = "public subnet b"
  }

  map_public_ip_on_launch = true
}

resource "aws_default_security_group" "internal" {
  vpc_id = aws_vpc.exo2.id

  tags = {
    Name = "default internal sg"
  }

  ingress {
    protocol    = -1
    self        = true
    from_port   = 0
    to_port     = 0
    description = "self ref"
  }

  egress {
    protocol    = -1
    self        = true
    from_port   = 0
    to_port     = 0
    description = "self ref"
  }

}

resource "aws_security_group" "web" {
  vpc_id = aws_vpc.exo2.id

  tags = {
    Name = "web sg for nginx"
  }

  ingress {
    description      = "http traffic"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

}

resource "aws_s3_bucket" "logs" {
  bucket = "m2iformationexo2logs"
  acl    = "private"
  force_destroy = true
  tags = {
    Name        = "nginx cluster access logs"
    Environment = "Dev"
  }
}


data "aws_elb_service_account" "main" {
    region = "us-east-1"
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Id": "allow-elb-logs",
    "Statement": [
        {
            "Sid": "RegionRootArn",
            "Effect": "Allow",
            "Principal": {
                "AWS": "${data.aws_elb_service_account.main.arn}"
            },
            "Action": "s3:PutObject",
            "Resource": "${aws_s3_bucket.logs.arn}/*"
        },
        {
            "Sid": "AWSLogDeliveryWrite",
            "Effect": "Allow",
            "Principal": {
                "Service": "delivery.logs.amazonaws.com"
            },
            "Action": "s3:PutObject",
            "Resource": "${aws_s3_bucket.logs.arn}/*",
            "Condition": {
                "StringEquals": {
                    "s3:x-amz-acl": "bucket-owner-full-control"
                }
            }
        },
        {
            "Sid": "AWSLogDeliveryAclCheck",
            "Effect": "Allow",
            "Principal": {
                "Service": "delivery.logs.amazonaws.com"
            },
            "Action": "s3:GetBucketAcl",
            "Resource": "${aws_s3_bucket.logs.arn}"
        }
    ]
}
  POLICY
}

resource "aws_lb" "web" {
  name               = "exo2-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups = [
    aws_default_security_group.internal.id,
    aws_security_group.web.id,
  ]
  subnets = [
    aws_subnet.a.id,
    aws_subnet.b.id
  ]
}

resource "aws_lb_target_group" "web" {
  name     = "web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.exo2.id
}


resource "aws_lb_listener" "web" {
  load_balancer_arn = aws_lb.web.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

resource "aws_placement_group" "web" {
  name     = "web-pl"
  strategy = "partition"
}

resource "aws_launch_template" "web" {
  name_prefix   = "web-lt-"
  image_id      = var.ami_id
  instance_type = "t2.micro"
  vpc_security_group_ids = [
    aws_default_security_group.internal.id,
  ]
}

resource "aws_autoscaling_group" "web" {
  name                = "webscale"
  vpc_zone_identifier = [aws_subnet.a.id, aws_subnet.b.id]
  desired_capacity    = 2
  max_size            = 4
  min_size            = 2
  placement_group     = aws_placement_group.web.id
  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }
  lifecycle {
    ignore_changes = [load_balancers, target_group_arns]
  }
}

resource "aws_autoscaling_attachment" "web" {
  autoscaling_group_name = aws_autoscaling_group.web.id
  alb_target_group_arn   = aws_lb_target_group.web.arn
}
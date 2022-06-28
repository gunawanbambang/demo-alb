terraform {
  cloud {
    organization = "bgunawan-learning"
    workspaces {
      name = "demo-alb"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

variable "server_port" {
  type = number
  description = "the port number of the webserver"
  default = 8080
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}


resource "aws_launch_configuration" "example" {
  image_id = "ami-0fb653ca2d3203ac1"
  instance_type = "t2.micro"
  security_groups = [aws_security_group.instance.id]

  user_data = <<-EOF
              #!/bin/bash
              echo "Hello, World v2" > index.html
              nohup busybox httpd -f -p ${var.server_port} &
              EOF
  lifecycle {
    create_before_destroy = true
  }
}



resource "aws_autoscaling_group" "example" {
  launch_configuration = aws_launch_configuration.example.name
  vpc_zone_identifier = data.aws_subnets.default.ids

  target_group_arns = [aws_lb_target_group.asg.arn]
  health_check_type = "ELB"

  min_size = 2
  max_size = 10

  tag {
    key = "Name"
    value = "terraform-asg-example"
    propagate_at_launch = true
  }
}




resource "aws_lb" "example" {
  name = "terraform-alb-example"
  load_balancer_type = "application"
  subnets = data.aws_subnets.default.ids
  security_groups = [aws_security_group.alb.id]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port = 80
  protocol = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code  = 404
    }
  }
}

resource "aws_lb_target_group" "asg" {
  name = "terraform-alb-example"
  port = var.server_port
  protocol = "HTTP"
  vpc_id = data.aws_vpc.default.id

  health_check {
    path = "/"
    protocol = "HTTP"
    matcher = "200"
    interval = 15
    timeout = 3
    healthy_threshold = 2
    unhealthy_threshold = 2
  }
}

resource "aws_alb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http.arn
  priority = 100

  condition {
    path_pattern {
      values = ["*"]
    }
  }

  action {
    type = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}




resource "aws_security_group" "instance" {
  name = "terraform-example-instance"

  ingress = [ {
    cidr_blocks          = [ "0.0.0.0/0" ]
    description          = "open 8080 for example"
    from_port            = var.server_port
    protocol             = "tcp"
    to_port              = var.server_port
    ipv6_cidr_blocks     = []
    prefix_list_ids      = []
    security_groups      = []
    self                 = false
  } ]
}

resource "aws_security_group" "alb" {
  name = "terraform-example-alb"

  ingress = [ {
    cidr_blocks          = [ "0.0.0.0/0" ]
    description          = "open 80 for ALB"
    from_port            = 80
    protocol             = "tcp"
    to_port              = 80
    ipv6_cidr_blocks     = []
    prefix_list_ids      = []
    security_groups      = []
    self                 = false
  } ]

  egress = [ {
    cidr_blocks = [ "0.0.0.0/0" ]
    description = "allow to perform health check to target group"
    from_port = 0
    ipv6_cidr_blocks = []
    prefix_list_ids = []
    protocol = "-1"
    security_groups = []
    self = false
    to_port = 0
  } ]
}





output "alb_dns_name" {
  value = aws_lb.example.dns_name
  description = "dns name of the ALB"
}


/*
output "public_ip" {
  description            = "public ip of the webserver"
  value                  = aws_instance.example.public_ip
}
*/
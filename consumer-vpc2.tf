#CONSUMER VPC2
resource "aws_vpc" "vpc2consumer" {
  cidr_block = "172.17.0.0/16"
  tags = {
    Name = "vpc2-consumer"
  }
}

#Private Subnet 1
resource "aws_subnet" "vpc2consumerprisub1" {
  cidr_block        = "172.17.1.0/24"
  vpc_id            = aws_vpc.vpc2consumer.id
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name = "vpc2consumerprisub1"
  }
}

#Private Route Table
resource "aws_route_table" "vpc2consumerroutetableprivate" {
  vpc_id = aws_vpc.vpc2consumer.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_ec2_transit_gateway.tgw.id
  }
  tags = {
    Name = "vpc2consumerroutetableprivate"
  }
}

#Associate Private Route Table to Private Subnet
resource "aws_route_table_association" "vpcoutboundroutetableprivateVPC2" {
  subnet_id      = aws_subnet.vpc2consumerprisub1.id
  route_table_id = aws_route_table.vpc2consumerroutetableprivate.id
}

resource "aws_ec2_transit_gateway_vpc_attachment" "vpc2consumervpcattachment" {
  subnet_ids                                      = [aws_subnet.vpc2consumerprisub1.id]
  transit_gateway_id                              = aws_ec2_transit_gateway.tgw.id
  vpc_id                                          = aws_vpc.vpc2consumer.id
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
  tags = {
    Name = "VPC2Attachment"
  }
}

resource "aws_ec2_transit_gateway_route_table_association" "vpc2association" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.vpc2consumervpcattachment.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.consumerroutetable.id
}

#----------- Instances ---------------------------

#------ Security group consumer vpc2 private instance --------------------

resource "aws_security_group" "consumer_vpc2_private_sg" {
  name        = "vpc2-consumer-private-sg"
  description = "allow ssh from jumpbox and icmp"
  vpc_id      = aws_vpc.vpc2consumer.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.10.0.0/24"]
  }

  ingress {
    from_port   = 8 # the ICMP type number for 'Echo'
    to_port     = 0 # the ICMP code
    protocol    = "icmp"
    cidr_blocks = ["172.16.0.0/16"]
  }

  ingress {
    from_port   = 8 # the ICMP type number for 'Echo'
    to_port     = 0 # the ICMP code
    protocol    = "icmp"
    cidr_blocks = ["10.10.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }


  tags = {
    Name = "consumer-vpc2-private-sg"

  }
}

#--------------------------------------------------

resource "aws_instance" "consumervpc2-instance" {
  ami                         = data.aws_ami.latest-amazon-linux-image.id
  instance_type               = "t2.micro"
  associate_public_ip_address = true
  count                       = 1
  subnet_id                   = aws_subnet.vpc2consumerprisub1.id
  vpc_security_group_ids = [aws_security_group.consumer_vpc2_private_sg.id]
  key_name               = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDVVK13zqDa1zJFZMyZnySmGWecODRQxVH0BVqjYPYqSY9p+q4NxLjEwzpT0DKJiz2CYUBArPEkRlJBsz+dLwd8NX8JZoAxiRq2F7ddKOC9Z6x5LKKaFHwEsbEYukpnKtkaXWZpzzWixFJP517MwwyKZhCk3uB0Fw+ytJtBWo2xz6jLEBdQZXxU6JD6+l2LQoaEYkB4SzO+uoocDRxjm0HVGV6kvI4om877AaU991yBoM/cl0IlyeIWjcsoNClme6zsoorZTObWTxuCLD8EyRCJV2uO2o7MBHYwnFsjAUAyTXWpL6h1cYV91pImV1KjKWujuJdDbI5oFKeB/CZlPSGShOVemMjmCc8T8k+6HI8FzYb6+u8ZfGrDHYMOwIk6qf2kr/g2Lt1pHNyPrW7MhxiVE0UeQ6JI3yoaL8NxfGM5zKbri84MEqas1zqb4LSnEfVW9Ov0ruw/MNhZOIINZ5QBJgsKLVSE70PVWhMoBcjD6BV9+h5ZzR2B1eLNQLU6Z3k= nilesh@mx"
  
  #user_data = file("entry_script.sh")

  tags = {
    Name = "consumer-vpc2-instance"

  }
}


data "aws_availability_zones" "available" {}

resource "aws_vpc" "vpcoutbound" {
  cidr_block = "10.10.0.0/16"
  tags = {
    Name = "vpc-outbound"
  }
}

#SUBNETS
#Public Subnet 1
resource "aws_subnet" "vpcoutboundpubsub1" {
  cidr_block              = "10.10.0.0/24"
  vpc_id                  = aws_vpc.vpcoutbound.id
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]
  tags = {
    Name = "vpc-outbound-pubsub-1"
  }
}

#GATEWAYS
#elastic IP for NAT Gateway resource
resource "aws_eip" "nat" {
  vpc = true
  tags = {
  Name = "vpc-outbound-nat" }
}

#NAT Gateway object and attachment of the Elastic IP Address from above 
resource "aws_nat_gateway" "ngw" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.vpcoutboundpubsub1.id
  depends_on    = [aws_internet_gateway.igw]
  tags = {
    Name = "ngw-outbound"
  }
}

#Internet Gateway 
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpcoutbound.id
  tags = {
    Name = "igw-outbound"
  }
}

#--------------------- Routes Public subnet -------------------------------
#Public Route Table Entry - Internet Bound
#send all traffic to the Internet out through the Internet Gateway
resource "aws_route_table" "vpcoutboundroutetablepublic" {
  vpc_id = aws_vpc.vpcoutbound.id
  route {                                                   
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  #send all VPC1 Consumer traffic through the Transit Gateway
  route { 
    cidr_block = aws_vpc.vpc1consumer.cidr_block
    gateway_id = aws_ec2_transit_gateway.tgw.id
  }
  #send all VPC2 Consumer traffic through the Transit Gateway 
  route { 
    cidr_block = aws_vpc.vpc2consumer.cidr_block
    gateway_id = aws_ec2_transit_gateway.tgw.id
  }
}


#Associate Public Route Table to Public Subnet
resource "aws_route_table_association" "vpcoutboundroutetablepublicas1" {
  subnet_id      = aws_subnet.vpcoutboundpubsub1.id
  route_table_id = aws_route_table.vpcoutboundroutetablepublic.id
}


#--------------------- Routes Private subnet -------------------------------

#Private Subnet 1
resource "aws_subnet" "vpcoutboundprisub1" {
  cidr_block        = "10.10.2.0/24"
  vpc_id            = aws_vpc.vpcoutbound.id
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name = "vpcoutboundprisub1"
  }
}

#Private Route Table
resource "aws_route_table" "vpcoutboundroutetableprivate" {
  vpc_id = aws_vpc.vpcoutbound.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.ngw.id
  }
  tags = {
    Name = "vpcoutboundroutetableprivate"
  }
}

#Associate Private Route Table to Private Subnet
resource "aws_route_table_association" "vpcoutboundroutetableprivateas1" {
  subnet_id      = aws_subnet.vpcoutboundprisub1.id
  route_table_id = aws_route_table.vpcoutboundroutetableprivate.id
}


#--------------- TRANSIT GATEWAYS ----------------------------------
resource "aws_ec2_transit_gateway" "tgw" {
  #for security reasons, we dont want to have attached VPCs to use the default route table    
  default_route_table_association = "disable"
  #for security reasons, we dont want to have attached VPCs to propogate their networks to the route tables
  default_route_table_propagation = "disable"
  auto_accept_shared_attachments = "enable"
  tags = {
    Name = "tgw"
  }
}

#outbound vpc attachment
resource "aws_ec2_transit_gateway_vpc_attachment" "outboundvpcattachment" {
  subnet_ids                                      = [aws_subnet.vpcoutboundprisub1.id]
  transit_gateway_id                              = aws_ec2_transit_gateway.tgw.id
  vpc_id                                          = aws_vpc.vpcoutbound.id
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
  tags = {
    Name = "OutboundAttachment"
  }
}


#------------- TGW Routes --------------------
#tgw outbound route table
resource "aws_ec2_transit_gateway_route_table" "egressroutetable" {
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  tags = {
    Name = "OutboundRouteTable"
  }
}

#tgw outbound route table association
resource "aws_ec2_transit_gateway_route_table_association" "outboundvpcassociation" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.outboundvpcattachment.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.egressroutetable.id
}

#route to the consumer 1 via vpc1 attachment
resource "aws_ec2_transit_gateway_route" "egressroutetableRouteVPC1" {
  destination_cidr_block         = aws_vpc.vpc1consumer.cidr_block
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.vpc1consumervpcattachment.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.egressroutetable.id
}

#route to the consumer 2 via vpc2 attachment
resource "aws_ec2_transit_gateway_route" "egressroutetableRouteVPC2" {
  destination_cidr_block         = aws_vpc.vpc2consumer.cidr_block
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.vpc2consumervpcattachment.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.egressroutetable.id
}

#----------- Instances ---------------------------

#------ Security group outbound public instance --------------------

resource "aws_security_group" "vpcoutbound_public_sg" {
  name        = "vpc-outbound-public-sg"
  description = "allow ssh from internet and icmp"
  vpc_id      = aws_vpc.vpcoutbound.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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
    cidr_blocks = ["172.17.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }


  tags = {
    Name = "vpcoutbound-public-sg"

  }
}

#--------------------------------------------------

#ami to choose
data "aws_ami" "latest-amazon-linux-image" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-kernel-*-x86_64-gp2"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}


resource "aws_instance" "outboundvpc-jumphost" {
  ami                         = data.aws_ami.latest-amazon-linux-image.id
  instance_type               = "t2.micro"
  associate_public_ip_address = true
  count                       = 1
  subnet_id                   = aws_subnet.vpcoutboundpubsub1.id
  vpc_security_group_ids = [aws_security_group.vpcoutbound_public_sg.id]
  key_name               = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDVVK13zqDa1zJFZMyZnySmGWecODRQxVH0BVqjYPYqSY9p+q4NxLjEwzpT0DKJiz2CYUBArPEkRlJBsz+dLwd8NX8JZoAxiRq2F7ddKOC9Z6x5LKKaFHwEsbEYukpnKtkaXWZpzzWixFJP517MwwyKZhCk3uB0Fw+ytJtBWo2xz6jLEBdQZXxU6JD6+l2LQoaEYkB4SzO+uoocDRxjm0HVGV6kvI4om877AaU991yBoM/cl0IlyeIWjcsoNClme6zsoorZTObWTxuCLD8EyRCJV2uO2o7MBHYwnFsjAUAyTXWpL6h1cYV91pImV1KjKWujuJdDbI5oFKeB/CZlPSGShOVemMjmCc8T8k+6HI8FzYb6+u8ZfGrDHYMOwIk6qf2kr/g2Lt1pHNyPrW7MhxiVE0UeQ6JI3yoaL8NxfGM5zKbri84MEqas1zqb4LSnEfVW9Ov0ruw/MNhZOIINZ5QBJgsKLVSE70PVWhMoBcjD6BV9+h5ZzR2B1eLNQLU6Z3k= nilesh@mx"
  
  #user_data = file("entry_script.sh")

  tags = {
    Name = "vpc-outbound-jumphost"

  }
}


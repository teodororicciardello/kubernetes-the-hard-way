#! /bin/bash


## create vpc 
aws ec2 create-vpc --cidr-block 10.240.0.0/16 | tee out
VPC_ID=$(cat out | jq '. | .Vpc.VpcId' | sed 's/"//g')

## add dns hostname resolution 
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames "{\"Value\":true}"

## create subnet
aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.240.0.0/24 | tee out
SUBNET_ID=$(cat out | jq '. | .Subnet.SubnetId' | sed 's/"//g')

## create security group 
aws ec2 create-security-group --group-name kthw-sg --description "security group for kthw" --vpc-id $VPC_ID | tee out
SG_ID=$(cat out | jq '. | .GroupId'  | sed 's/"//g')

## create sg rules  
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol all --cidr 10.200.0.0/16 

aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 6443 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol icmp --port -1 --cidr 0.0.0.0/0

### NEEDED FOR AWS TO SSH/SCP
## create igw
aws ec2 create-internet-gateway | tee out
IGW_ID=$(cat out | jq '. | .InternetGateway.InternetGatewayId' | sed 's/"//g')

## attach igw to vpc 
aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID

## create route table
aws ec2 create-route-table --vpc-id $VPC_ID | tee out
ROUTE_ID=$(cat out | jq '. | .RouteTable.RouteTableId' | sed 's/"//g')

## create route to internet gateway
aws ec2 create-route --route-table-id $ROUTE_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID

## associate route table to subnet
aws ec2 associate-route-table  --subnet-id $SUBNET_ID --route-table-id $ROUTE_ID


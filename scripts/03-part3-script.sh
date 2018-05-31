#! /bin/bash

## Create LB 
LB=kthw-lb
aws elb create-load-balancer --load-balancer-name $LB --subnets $SUBNET_ID \
  --listeners "Protocol=tcp,LoadBalancerPort=6443,InstanceProtocol=tcp,InstancePort=6443" | tee out 
KUBERNETES_PUBLIC_ADDRESS=$(cat out | jq '.DNSName' | sed 's/"//g')

# aws elb attach-load-balancer-to-subnets --load-balancer-name $LB --subnets $SUBNET2_ID

## (Optional configure health check)
aws elb configure-health-check --load-balancer-name $LB --health-check Target=HTTPS:6443/version,Interval=30,UnhealthyThreshold=2,HealthyThreshold=2,Timeout=3

## Register instances with LB 
aws elb register-instances-with-load-balancer --load-balancer-name $LB --instances ${CONTR_ID[@]}

## enable cross zone lb
#aws elb modify-load-balancer-attributes --load-balancer-name $LB --load-balancer-attributes "{\"CrossZoneLoadBalancing\":{\"Enabled\":true}}"

## create LB security group 
aws ec2 create-security-group --group-name LBGroup --description "LB kthw security group" --vpc-id $VPC_ID | tee out
SG_LB_ID=$(cat out | jq '. | .GroupId' | sed 's/"//g')

## associate the LB with the security Group 
aws elb apply-security-groups-to-load-balancer --load-balancer-name $LB --security-groups $SG_LB_ID 

## Rule on LB SG 
LISTENER=6443
HEALTH=6443
aws ec2 authorize-security-group-ingress --group-id $SG_LB_ID --protocol tcp --port $LISTENER --cidr 0.0.0.0/0
#aws ec2 authorize-security-group-ingress --group-id $SG_LB_ID --protocol tcp --port 443 --cidr 0.0.0.0/0

## rules on instances security group for LB ## not needed
#aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port $LISTENER --source-group $SG_LB_ID 
#aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port $HEALTH --source-group $SG_LB_ID 



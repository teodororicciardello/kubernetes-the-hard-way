#! /bin/bash

## Setting variables for cidr
POD_CIDR=(10.200.0.0/24 10.200.1.0/24 10.200.2.0/24)

## create route to worker interface 
for i in 0 1 2; do
instance=ip-10-240-0-2$i
  IP=$(aws ec2 describe-instances --instance-id ${WORK_ID[i]} --query 'Reservations[].Instances[].PublicIpAddress'| jq .[0] | sed 's/"//g')
  IF=$(aws ec2 describe-instances --instance-id ${WORK_ID[i]} --query 'Reservations[].Instances[].NetworkInterfaces[].NetworkInterfaceId'| jq .[0] | sed 's/"//g')

  aws ec2 create-route --route-table-id $ROUTE_ID --destination-cidr-block ${POD_CIDR[i]} --network-interface-id $IF
done

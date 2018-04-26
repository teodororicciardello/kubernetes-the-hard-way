#! /bin/bash

## Variable for server AMI 
AMI=ami-f90a4880

### Create VMs

## launch Controller instances 
for i in 0 1 2; do 
	aws ec2 run-instances \
	--image-id $AMI \
	--count 1 \
	--instance-type t2.micro \
	--key-name default-key \
	--security-group-ids $SG_ID \
	--subnet-id $SUBNET_ID \
	--private-ip-address 10.240.0.1${i} \
	--associate-public-ip-address \
	--user-data file://controller_bootstrap.sh \
	| tee out 
	CONTR_ID[i]=$(cat out | jq '. | .Instances[0].InstanceId' | sed 's/"//g') 
	#aws ec2 modify-instance-attribute --instance-id ${CONTR_ID[i]} --source-dest-check "{\"Value\": false}"
done 

## launch Worker instances 
for i in 0 1 2; do 
	aws ec2 run-instances \
	--image-id $AMI \
	--count 1 \
	--instance-type t2.micro \
	--key-name default-key \
	--security-group-ids $SG_ID \
	--subnet-id $SUBNET_ID \
	--private-ip-address 10.240.0.2${i} \
	--associate-public-ip-address \
	--user-data file://worker_bootstrap.sh \
	| tee out 
	WORK_ID[i]=$(cat out | jq '. | .Instances[0].InstanceId' | sed 's/"//g')
	aws ec2 modify-instance-attribute --instance-id ${WORK_ID[i]} --source-dest-check "{\"Value\": false}"
done 


# Cleaning Up

In this lab you will delete the compute resources created during this tutorial.

## Compute Instances

Delete the controller and worker compute instances:

```
aws ec2 terminate-instances --instance-ids ${CONTR_ID[@]} 

aws ec2 terminate-instances --instance-ids ${WORK_ID[@]} 
```

## Networking

Delete the external load balancer:
```
aws elb delete-load-balancer --load-balancer-name $LB 
```


Delete the security groups for load balancer and instances:
```
aws ec2 delete-security-group --group-id $SG_LB_ID

aws ec2 delete-security-group --group-id $SG_ID
```

Delete the Pod network routes: 

```
for i in 0 1 2; do
  POD_CIDR=10.200.$i.0/24
  aws ec2 delete-route --route-table-id $ROUTE_ID --destination-cidr-block $POD_CIDR 
done 
```

Delete the subnet:

```
aws ec2 delete-subnet --subnet-id $SUBNET_ID
```

Delete the route table:

```
aws ec2 delete-route-table --route-table-id $ROUTE_ID
```

Detach and delete the internet gateway:

```
aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID

aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID
```

Finally delete the VPC:

```
aws ec2 delete-vpc --vpc-id $VPC_ID
```

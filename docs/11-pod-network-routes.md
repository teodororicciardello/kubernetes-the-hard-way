# Provisioning Pod Network Routes

Pods scheduled to a node receive an IP address from the node's Pod CIDR range. At this point pods can not communicate with other pods running on different nodes due to missing network [routes](https://cloud.google.com/compute/docs/vpc/routes).

In this lab you will create a route for each worker node that maps the node's Pod CIDR range to the node's internal IP address.

> There are [other ways](https://kubernetes.io/docs/concepts/cluster-administration/networking/#how-to-achieve-this) to implement the Kubernetes networking model.

## Routes

Create network routes for each worker instance:

```
for i in 0 1 2; do
  instance=ip-10-240-0-2$i
  POD_CIDR=10.200.$i.0/24
  IP=$(aws ec2 describe-instances --instance-id ${WORK_ID[i]} \
    --query 'Reservations[].Instances[].PublicIpAddress'\
    | jq .[0] | sed 's/"//g')
  IF=$(aws ec2 describe-instances --instance-id ${WORK_ID[i]} \
    --query 'Reservations[].Instances[].NetworkInterfaces[].NetworkInterfaceId'\
    | jq .[0] | sed 's/"//g')
  aws ec2 create-route --route-table-id $ROUTE_ID \
    --destination-cidr-block $POD_CIDR \ 
    --network-interface-id $IF
done
```

> In AWS the route to the hosts must be set using the Interface Id


List the routes in the VPC network:
```
aws ec2 describe-route-tables --route-table-ids $ROUTE_ID --query \
  "RouteTables[].Routes[].{DEST: DestinationCidrBlock, GATEWAY: GatewayId, HOP: NetworkInterfaceId, \
  STATUS: State}" --output table
```

> output

```
-------------------------------------------------------------------------------
|                             DescribeRouteTables                             |
+---------------+-------------------------+-------------------------+---------+
|     DEST      |         GATEWAY         |           HOP           | STATUS  |
+---------------+-------------------------+-------------------------+---------+
|  10.200.0.0/24|  None                   |  eni-xxxxxxxxxxxxxxxxx  |  active |
|  10.200.1.0/24|  None                   |  eni-xxxxxxxxxxxxxxxxx  |  active |
|  10.200.2.0/24|  None                   |  eni-xxxxxxxxxxxxxxxxx  |  active |
|  10.240.0.0/16|  local                  |  None                   |  active |
|  0.0.0.0/0    |  igw-xxxxxxxxxxxxxxxxx  |  None                   |  active |
+---------------+-------------------------+-------------------------+---------+

```

Next: [Deploying the DNS Cluster Add-on](12-dns-addon.md)

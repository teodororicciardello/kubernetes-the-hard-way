# Provisioning Compute Resources

Kubernetes requires a set of machines to host the Kubernetes control plane and the worker nodes where containers are ultimately run. In this lab you will provision the compute resources required for running a secure and highly available Kubernetes cluster across a single [region](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-regions-availability-zones.html).

> Ensure a default region have been set as described in the [Prerequisites](01-prerequisites.md#set-a-default-compute-region-and-zone) lab. For AWS is not required to specify the availability zone during the resource provisioning. 

## Networking

The Kubernetes [networking model](https://kubernetes.io/docs/concepts/cluster-administration/networking/#kubernetes-model) assumes a flat network in which containers and nodes can communicate with each other. In cases where this is not desired [network policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/) can limit how groups of containers are allowed to communicate with each other and external network endpoints.

> Setting up network policies is out of scope for this tutorial.

### Virtual Private Cloud Network

In this section a dedicated [Virtual Private Cloud](https://docs.aws.amazon.com/AmazonVPC/latest/UserGuide/VPC_Introduction.html) (VPC) network will be setup to host the Kubernetes cluster.
The VPC must be sufficient to allocate the subnets required for each kubernetes nodes.

Create a VPC passing the proper cidr range:

```
aws ec2 create-vpc --cidr-block 10.240.0.0/16
```
Retrieve the VpcId from the output of the command, we will refer to it as $VPC_ID in the following instructions.
By default in AWS, VPC doesn't have DNS resolution. Enable the DNS resolution:
```
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames "{\"Value\":true}"
``` 

A [subnet](https://docs.aws.amazon.com/AmazonVPC/latest/UserGuide/VPC_Subnets.html) must be provisioned with an IP address range large enough to assign a private IP address to each node in the Kubernetes cluster.

Create a subnet in the previous VPC:

```
aws ec2 create-subnet --vpc-id $VPC_ID \
  --cidr-block 10.240.0.0/24
```
Retrieve the SubnetId from the output of the command, we will refer to it as $SUBNET_ID in the following instructions.

> The `10.240.0.0/24` IP address range can host up to 254 compute instances.

### Security Group

In AWS firewall rules are set within security groups. 
First create the security group `kthw-sg`:

```
aws ec2 create-security-group --group-name kthw-sg --description "security group for kthw" --vpc-id $VPC_ID
```
Retrieve the GroupId from the output of the command, we will refer to it as $SG_ID in the following instructions.

By default in AWS, VMs in SG cannot communicate each other, so first you need to create rule that allows internal communications:

```
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol all --source-group $SG_ID 
```

Create now a firewall rule that allows communication across all protocols for the pods:

```
aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol all --cidr 10.200.0.0/16 
```

Create the firewall rules that allows external SSH, ICMP, and HTTPS:

```
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 6443 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol icmp --port -1 --cidr 0.0.0.0/0
```

> A load balancer(TODO) will be used to expose the Kubernetes API Servers to remote clients.

In order to enable access via SSH to the nodes, in AWS it is necessary an Internet Gateway for the VPC with the proper routes. 
Create an internet gateway:
```
aws ec2 create-internet-gateway 
```
Retrieve the InternetGatewayId from the output of the command, we will refer to it as $IGW_ID in the following instructions.

Associate the Internet Gateway to the VPC:
```
aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID
```

Create a route table for the VPC:
```
aws ec2 create-route-table --vpc-id $VPC_ID
```
Retrieve the RouteTableId from the output of the command, we will refer to it as $ROUTE_ID in the following instructions.

Create the route to the Internet Gateway:
```
aws ec2 create-route --route-table-id $ROUTE_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
```

Finally associate the table with the previous subnet:
```
aws ec2 associate-route-table  --subnet-id $SUBNET_ID --route-table-id $ROUTE_ID
```

### Kubernetes Public IP Address
(TODO)
(In AWS the configuration of the load balancer is more complicated than in GCE and is not feasible allocate a public IP to it).


## Compute Instances

The compute instances in this lab will be provisioned using [Ubuntu Server](https://www.ubuntu.com/server) 16.04, which has good support for the [cri-containerd container runtime](https://github.com/containerd/cri-containerd). Each compute instance will be provisioned with a fixed private IP address to simplify the Kubernetes bootstrapping process.
> In the below commands the variable `$AMI` will be used for the AMI id of the Ubuntu 16.04. It is suggested to take the last AMI id from the console or via API to have the latest updates. 


### Kubernetes Controllers

First we create the instance to host the Kubernetes control plane. In this and the next paragraph the id will be retrieved for each instance and stored in an array variable.
 
Create three compute instances for the controllers:

```
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
  | tee out 
  CONTR_ID[i]=$(cat out | jq '. | .Instances[0].InstanceId' | sed 's/"//g') 
done
```
The array variable ${CONTR_ID} will contain the ids for the instances created. We will use them later to connect to the instance. 

### Kubernetes Workers

You then create the instance to host the Kubernetes worker nodes. Each node will need to propagate the traffic from the pod subnets to the other nodes like a NAT. In AWS for this purpose it is necessary disable the source-dest-check flag.
Create three compute instances disabling the source-dest-check:

```
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
  | tee out 
  WORK_ID[i]=$(cat out | jq '. | .Instances[0].InstanceId' | sed 's/"//g')
  aws ec2 modify-instance-attribute --instance-id ${WORK_ID[i]} --source-dest-check "{\"Value\": false}"
done
```
The array variable ${WORK_ID} will contain the ids for the instances created. We will use them later to connect to the instance.

### Verification

List the compute instances in your default compute zone:

(TODO)
```

```

> output

```
NAME          ZONE        MACHINE_TYPE   PREEMPTIBLE  INTERNAL_IP  EXTERNAL_IP     STATUS
10-240-0-10   us-west1-c  n1-standard-1               10.240.0.10  XX.XXX.XXX.XXX  RUNNING
10-240-0-11   us-west1-c  n1-standard-1               10.240.0.11  XX.XXX.X.XX     RUNNING
10-240-0-12   us-west1-c  n1-standard-1               10.240.0.12  XX.XXX.XXX.XX   RUNNING
10-240-0-20   us-west1-c  n1-standard-1               10.240.0.20  XXX.XXX.XXX.XX  RUNNING
10-240-0-21   us-west1-c  n1-standard-1               10.240.0.21  XX.XXX.XX.XXX   RUNNING
10-240-0-22   us-west1-c  n1-standard-1               10.240.0.22  XXX.XXX.XX.XX   RUNNING
```

Next: [Provisioning a CA and Generating TLS Certificates](04-certificate-authority.md)

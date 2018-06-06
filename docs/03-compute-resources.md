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
Retrieve the VpcId from the output of the command, it will be referred to it as $VPC_ID in the following instructions.
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
Retrieve the SubnetId from the output of the command, it will be referred to it as $SUBNET_ID in the following instructions.

> The `10.240.0.0/24` IP address range can host up to 254 compute instances.

### Security Group

In AWS firewall rules are set within security groups. 
First create the security group `kthw-sg`:

```
aws ec2 create-security-group --group-name kthw-sg --description "security group for kthw" --vpc-id $VPC_ID
```
Retrieve the GroupId from the output of the command, it will be referred to it as $SG_ID in the following instructions.

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

In order to enable access via SSH to the nodes, in AWS it is necessary an Internet Gateway for the VPC with the proper routes. 
Create an internet gateway:
```
aws ec2 create-internet-gateway 
```
Retrieve the InternetGatewayId from the output of the command, it will be referred to it as $IGW_ID in the following instructions.

Associate the Internet Gateway to the VPC:
```
aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID
```

Create a route table for the VPC:
```
aws ec2 create-route-table --vpc-id $VPC_ID
```
Retrieve the RouteTableId from the output of the command, it will be referred to it as $ROUTE_ID in the following instructions.

Create the route to the Internet Gateway:
```
aws ec2 create-route --route-table-id $ROUTE_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
```

Finally associate the table with the previous subnet:
```
aws ec2 associate-route-table  --subnet-id $SUBNET_ID --route-table-id $ROUTE_ID
```

## Compute Instances

The compute instances in this lab will be provisioned using [Ubuntu Server](https://www.ubuntu.com/server) 18.04, which has good support for the [containerd container runtime](https://github.com/containerd/containerd). Each compute instance will be provisioned with a fixed private IP address to simplify the Kubernetes bootstrapping process.
> In the below commands the variable `$AMI` will be used for the AMI id of the Ubuntu 18.04. It is suggested to take the last AMI id from the console or via API to have the latest updates. 

### Kubernetes Controllers

First you create the instance to host the Kubernetes control plane. In this and the next paragraph the id will be retrieved for each instance and stored in an array variable.
 
Create three compute instances for the controllers:

```
for i in 0 1 2; do
  aws ec2 run-instances \
    --image-id $AMI \
    --count 1 \
    --instance-type t2.small \
    --key-name default-key \
    --security-group-ids $SG_ID \
    --subnet-id $SUBNET_ID \
    --private-ip-address 10.240.0.1${i} \
    --associate-public-ip-address \
  | tee out 
  CONTR_ID[i]=$(cat out | jq '. | .Instances[0].InstanceId' | sed 's/"//g') 
done
```
The array variable ${CONTR_ID} will contain the ids for the instances created. It will be used later to connect to the instances. 

### Kubernetes Workers

You then create the instance to host the Kubernetes worker nodes. Each node will need to propagate the traffic from the pod subnets to the other nodes like a NAT. In AWS for this purpose it is necessary disable the source-dest-check flag.
Create three compute instances disabling the source-dest-check:

```
for i in 0 1 2; do
  aws ec2 run-instances \
    --image-id $AMI \
    --count 1 \
    --instance-type t2.small \
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
The array variable ${WORK_ID} will contain the ids for the instances created. It will be used later to connect to the instances.

### Verification

List the compute instances in your compute zone:

```
aws ec2 describe-instances --query "Reservations[*].Instances[*].{ZONE: Placement.AvailabilityZone, \
  MACHINE_TYPE: InstanceType, INTERNAL_IP: PrivateIpAddress, EXTERNAL_IP: PublicIpAddress, \
  STATUS: State.Name}" --output table
```

> output

```
----------------------------------------------------------------------------
|                             DescribeInstances                            |
+----------------+--------------+---------------+-----------+--------------+
|   EXTERNAL_IP  | INTERNAL_IP  | MACHINE_TYPE  |  STATUS   |    ZONE      |
+----------------+--------------+---------------+-----------+--------------+
|  XX.XXX.XXX.XX |  10.240.0.10 |  t2.small     |  running  |  eu-west-1b  |
|  XX.XXX.XXX.XXX|  10.240.0.11 |  t2.small     |  running  |  eu-west-1b  |
|  XX.XXX.XXX.X  |  10.240.0.12 |  t2.small     |  running  |  eu-west-1b  |
|  XX.XXX.X.XX   |  10.240.0.20 |  t2.small     |  running  |  eu-west-1b  |
|  XX.XXX.XX.XXX |  10.240.0.21 |  t2.small     |  running  |  eu-west-1b  |
|  XX.XXX.XX.XXX |  10.240.0.22 |  t2.small     |  running  |  eu-west-1b  |
+----------------+--------------+---------------+-----------+--------------+
```

## The Kubernetes Frontend Load Balancer
In this section you will provision an external load balancer to front the Kubernetes API Servers.

### Provision an External Load Balancer

An AWS [Elastic Load Balancer (LB)](https://docs.aws.amazon.com/elasticloadbalancing/latest/userguide/what-is-load-balancing.html) will be used to distribute traffic across the three API servers and allow each API server to terminate TLS connections and validate client certificates. 

Create a `kthw-lb` LB passing the subnet and defining a listener on port 6443:
```
LB=kthw-lb
aws elb create-load-balancer --load-balancer-name $LB --subnets $SUBNET_ID \
  --listeners "Protocol=tcp,LoadBalancerPort=6443,InstanceProtocol=tcp,InstancePort=6443" 
```

Retrieve the DNSName from the output of the command, it will be referred to it as $KUBERNETES_PUBLIC_ADDRESS in the following instructions.

### Enable HTTP Health Checks

The AWS load balancer supports HTTPS health checks so the HTTPS endpoint of the API server can be used also as health check for the instances. Configure the health check for the LB for HTTPS protocol on port 6443:
```
aws elb configure-health-check --load-balancer-name $LB --health-check Target=HTTPS:6443/version,Interval=30,UnhealthyThreshold=2,HealthyThreshold=2,Timeout=3
```

Register the controller instances with the LB: 
```
aws elb register-instances-with-load-balancer --load-balancer-name $LB --instances ${CONTR_ID[@]}
```

Finally create a security group specifically for the LB and set the rule for port 6443:
```
aws ec2 create-security-group --group-name LBGroup --description "LB kthw security group" --vpc-id $VPC_ID 
SG_LB_ID=$(cat out | jq '. | .GroupId' | sed 's/"//g')
```
Retrieve the GroupId from the output of the command, it will be referred to it as $SG_LB_ID in the following instructions.

```
aws elb apply-security-groups-to-load-balancer --load-balancer-name $LB --security-groups $SG_LB_ID 

LISTENER=6443
aws ec2 authorize-security-group-ingress --group-id $SG_LB_ID --protocol tcp --port $LISTENER --cidr 0.0.0.0/0
```


## Configuring SSH Access

SSH will be used to configure the controller and worker instances. When connecting to compute instances for the first time SSH keys will be generated for you and stored in the project or instance metadata as describe in the [connecting to instances](https://cloud.google.com/compute/docs/instances/connecting-to-instance) documentation.

Test SSH access to the `controller-0` compute instances:

```
gcloud compute ssh controller-0
```

If this is your first time connecting to a compute instance SSH keys will be generated for you. Enter a passphrase at the prompt to continue:

```
WARNING: The public SSH key file for gcloud does not exist.
WARNING: The private SSH key file for gcloud does not exist.
WARNING: You do not have an SSH key for gcloud.
WARNING: SSH keygen will be executed to generate a key.
Generating public/private rsa key pair.
Enter passphrase (empty for no passphrase):
Enter same passphrase again:
```

At this point the generated SSH keys will be uploaded and stored in your project:

```
Your identification has been saved in /home/$USER/.ssh/google_compute_engine.
Your public key has been saved in /home/$USER/.ssh/google_compute_engine.pub.
The key fingerprint is:
SHA256:nz1i8jHmgQuGt+WscqP5SeIaSy5wyIJeL71MuV+QruE $USER@$HOSTNAME
The key's randomart image is:
+---[RSA 2048]----+
|                 |
|                 |
|                 |
|        .        |
|o.     oS        |
|=... .o .o o     |
|+.+ =+=.+.X o    |
|.+ ==O*B.B = .   |
| .+.=EB++ o      |
+----[SHA256]-----+
Updating project ssh metadata...-Updated [https://www.googleapis.com/compute/v1/projects/$PROJECT_ID].
Updating project ssh metadata...done.
Waiting for SSH key to propagate.
```

After the SSH keys have been updated you'll be logged into the `controller-0` instance:

```
Welcome to Ubuntu 18.04 LTS (GNU/Linux 4.15.0-1006-gcp x86_64)

...

Last login: Sun May 13 14:34:27 2018 from XX.XXX.XXX.XX
```

Type `exit` at the prompt to exit the `controller-0` compute instance:

```
$USER@controller-0:~$ exit
```
> output

```
logout
Connection to XX.XXX.XXX.XXX closed
```

Next: [Provisioning a CA and Generating TLS Certificates](04-certificate-authority.md)

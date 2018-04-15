# Prerequisites

## Amazon Web Services

This tutorial leverages the [Amazon Web Services (AWS)](https://aws.amazon.com/) to streamline provisioning of the compute infrastructure required to bootstrap a Kubernetes cluster from the ground up.

> The compute resources required for this tutorial exceed the AWS free tier.

## AWS CLI

### Install the AWS CLI

Follow the Amazon CLI [documentation](https://aws.amazon.com/cli/) to install and configure the `aws` command line utility.

Verify the AWS CLI version is 1.14.27 or higher:

```
aws --version
```

### Set a Default Compute Region 

This tutorial assumes a default compute region has been configured.

If you are using the `aws` command-line tool for the first time `configure` is the easiest way to do this:

```
aws configure
```

Otherwise set a default compute region:

```
aws configure set default.region us-west-2
```

> Use the `aws ec2 describe-regions --output table` command to view additional regions.

Next: [Installing the Client Tools](02-client-tools.md)

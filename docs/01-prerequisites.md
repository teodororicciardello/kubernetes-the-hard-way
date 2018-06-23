# Prerequisites

## Amazon Web Services

This tutorial leverages [Amazon Web Services (AWS)](https://aws.amazon.com/) to streamline provisioning of the compute infrastructure required to bootstrap a Kubernetes cluster from the ground up.

> The compute resources required for this tutorial exceed the AWS free tier.

## AWS CLI

### Install the AWS CLI

Follow the Amazon CLI [documentation](https://docs.aws.amazon.com/cli/latest/userguide/installing.html) to install and configure the `aws` command line utility.

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
aws configure set default.region eu-west-1
```

> Use the `aws ec2 describe-regions --output table` command to view additional regions.

## Extract ids from json output with jq 

[jq](https://stedolan.github.io/jq/) is a JSON processor that will be used to extract the ids from the aws cli output. The tool is not strictly needed to execute the tutorial as the ids can be retrieved also manually from the output. 
To install jq follow the instructions for your system from the [download](https://stedolan.github.io/jq/download/) link.

Verify the jq version is 1.5 or higher:

```
jq --version
```


## Running Commands in Parallel with tmux

[tmux](https://github.com/tmux/tmux/wiki) can be used to run commands on multiple compute instances at the same time. Labs in this tutorial may require running the same commands across multiple compute instances, in those cases consider using tmux and splitting a window into multiple panes with `synchronize-panes` enabled to speed up the provisioning process.

> The use of tmux is optional and not required to complete this tutorial.

![tmux screenshot](images/tmux-screenshot.png)

> Enable `synchronize-panes`: `ctrl+b` then `shift :`. Then type `set synchronize-panes on` at the prompt. To disable synchronization: `set synchronize-panes off`.



Next: [Installing the Client Tools](02-client-tools.md)

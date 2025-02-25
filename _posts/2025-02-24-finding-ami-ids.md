---
layout: resource
title: "How to find AMI IDs for Amazon Linux and Ubuntu"
description: "Learn the different ways to automatically find the IDs of common Amazon-managed AMIs such as Amazon Linux and Ubuntu, using tools such as the AWS CLI, OpenTofu, and Packer."
thumbnail_path: "/resources/finding-ami-ids/amis.png"
---

When you launch a server (_EC2 instance_) in AWS, you have to pick the _Amazon Machine Image (AMI)_ to run on that
instance, which specifies what operating system and other software will be installed. When you're using the AWS Web 
Console, the web UI makes it easy to find the latest versions of AMIs that Amazon manages, such as Amazon Linux and 
Ubuntu. However, when you are trying to launch instances programmatically, you need the ID of the AMI to use, and that 
ID can be surprisingly tricky to find, as (a) it's not easy to find the ID in the web UI and (b) even 
if you find it, you wouldn't want to hard-code the ID anyway, as it is different in each region, and changes each time 
AWS updates its AMIs (e.g., with security fixes). In this blog post, I'll show you several recipes for how to 
programmatically find the latest ID of Amazon-managed AMIs, with each recipe making use of one of the following
tools:

* [AWS CLI](#aws-cli)
* [OpenTofu / Terraform](#opentofu--terraform)
* [Packer](#packer)
* [Ansible](#ansible)
* [SSM Parameter Store Aliases](#ssm-parameter-store-aliases)

Let's get started with the AWS CLI.

## AWS CLI

The first recipe uses the [AWS CLI](https://aws.amazon.com/cli/) to find the AMI ID using the [describe-images
command](https://docs.aws.amazon.com/cli/latest/reference/ec2/describe-images.html):

```bash
aws ec2 describe-images \
  --region <REGION> \
  --owners <OWNER> \
  --filters 'Name=name,Values=<NAME>' \
  --query 'reverse(sort_by(Images, &CreationDate))[:1] | [0].ImageId' \
  --output text
```

Where: 

- `<REGION>` is the AWS region (e.g., `us-east-2`).
- `<OWNER>` is the owner of the AMI, which will be `amazon` for Amazon Linux and `099720109477` (Canonical) for Ubuntu. 
- `<NAME>` is the name of the AMI, which will be `al2023-ami-2023.*-x86_64` for Amazon Linux and 
  `ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*` for Ubuntu 24.04.

For example, to look up the ID of the most recent Amazon Linux 2023 AMI in `us-east-2`, 
[authenticate to AWS](https://www.fundamentals-of-devops.com/resources/2025/01/25/authenticate-to-aws-with-iam-identity-center/),
and then run the following command:

```bash
aws ec2 describe-images \
  --region us-east-2 \
  --owners amazon \
  --filters 'Name=name,Values=al2023-ami-2023.*-x86_64' \
  --query 'reverse(sort_by(Images, &CreationDate))[:1] | [0].ImageId' \
  --output text
```

And to look up the ID of the most recent Ubuntu 24.04 AMI in `us-east-2`, run the following:

```bash
aws ec2 describe-images \
  --region us-east-2 \
  --owners 099720109477 \
  --filters 'Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*' \
  --query 'reverse(sort_by(Images, &CreationDate))[:1] | [0].ImageId' \
  --output text
```

When you run these commands, they will print the ID of the most recent matching AMI to `stdout`. You can store this AMI 
ID in a variable called `ami_id` as follows:

```bash
ami_id=$(aws ec2 describe-images \
  --region us-east-2 \
  --owners 099720109477 \
  --filters 'Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*' \
  --query 'reverse(sort_by(Images, &CreationDate))[:1] | [0].ImageId' \
  --output text)
```

You can then use the variable in other commands, such as the following command for launching an EC2 instance with the
AMI you just found:

```bash
aws ec2 run-instances \
  --region us-east-2 \
  --image-id "$ami_id" \
  --instance-type "t2.micro"
```

## OpenTofu / Terraform

The second recipe is for [OpenTofu](https://opentofu.org/) and [Terraform](https://www.terraform.io/), infrastructure 
provisioning tools which allow you to find AMIs using the [`aws_ami` data 
source](https://search.opentofu.org/provider/hashicorp/aws/latest/docs/datasources/ami):[^1]

```terraform
provider "aws" {
  region = "<REGION>"
}

data "aws_ami" "image" {
  filter {
    name   = "name"
    values = ["<NAME>"]
  }
  owners      = ["<OWNER>"]
  most_recent = true
}

output "ami_id" {
  value = data.aws_ami.image.id
}
```

You'll need to fill in `<REGION>`, `<NAME>`, and `<OWNER>` the same way as in the [AWS CLI section](#aws-cli). For 
example, to look up the ID of the most recent Amazon Linux 2023 AMI in `us-east-2`, you'd fill in the following 
values:

```bash
provider "aws" {
  region = "us-east-2"
}

data "aws_ami" "image" {
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
  owners      = ["amazon"]
  most_recent = true
}

output "ami_id" {
  value = data.aws_ami.image.id
}
```

And to look up the ID of the most recent Ubuntu 24.04 AMI in `us-east-2`, you'd fill in the following:

```bash
provider "aws" {
  region = "us-east-2"
}

data "aws_ami" "image" {
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  owners      = ["099720109477"]
  most_recent = true
}

output "ami_id" {
  value = data.aws_ami.image.id
}
```

You can then run `tofu init` and `tofu apply`, and the `ami_id` output will write the AMI ID to `stdout`:

```bash
tofu init
tofu apply
```

You can also use the AMI ID value in the rest of your OpenTofu code, such as the following code for launching an EC2 
instance with the AMI you just found:

```terraform
resource "aws_instance" "example" {
  ami           = data.aws_ami.image.id
  instance_type = "t2.micro"
}
```

## Packer

The third recipe is for [Packer](https://www.packer.io/), a tool that you can use to create machine images (such as your
own custom AMIs), which allows you to find AMIs using the [`amazon-ami` data
source](https://developer.hashicorp.com/packer/integrations/hashicorp/amazon/latest/components/data-source/ami):

```hcl
packer {
  required_plugins {
    amazon = {
      version = ">= 1.3.1"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

data "amazon-ami" "image" {
  filters = {
    name = "<NAME>"
  }
  owners      = ["<OWNER>"]
  most_recent = true
  region      = "<REGION>"
}
```

You'll need to fill in `<REGION>`, `<NAME>`, and `<OWNER>` the same way as in the [AWS CLI section](#aws-cli). For
example, to look up the ID of the most recent AMD Amazon Linux 2023 AMI in `us-east-2`, you'd fill in the following
values:

```hcl
data "amazon-ami" "image" {
  filters = {
    name = "al2023-ami-2023.*-x86_64"
  }
  owners      = ["amazon"]
  most_recent = true
  region      = "us-east-2"
}
```

And to look up the ID of the most recent Ubuntu 24.04 AMI in `us-east-2`, you'd fill in the following:

```hcl
data "amazon-ami" "image" {
  filters = {
    name = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
  }
  owners      = ["099720109477"]
  most_recent = true
  region      = "us-east-2"
}
```

You can use the ID this data source returns in your builders, such as the following code for creating a custom 
AMI:

```hcl
source "amazon-ebs" "example" {
  ami_name        = "custom-ami"
  ami_description = "Example of a custom AMI built using Packer."
  instance_type   = "t2.micro"
  region          = "us-east-2"
  source_ami      = data.amazon-ami.image.id
  ssh_username    = "ec2-user"
}

build {
  sources = ["source.amazon-ebs.example"]
  
  provisioner "shell" {
    inline = ["echo 'Hello, World!'"]
  }
}
```

If this code was in a Packer template called _custom-ami.pkr.hcl_, you'd build your custom AMI by running the following
commands:

```bash
packer init custom-ami.pkr.hcl
packer build custom-ami.pkr.hcl
```

## Ansible

The fourth recipe is for [Ansible](https://docs.ansible.com/), a configuration management tool which allows you to 
find AMIs using the [`ec2_ami_info` 
module](https://docs.ansible.com/ansible/latest/collections/amazon/aws/ec2_ami_info_module.html):

{% raw %}
```yaml
- name: Example Playbook
  hosts: localhost
  gather_facts: no
  tasks:
    - name: 'Get AMI IDs'
      amazon.aws.ec2_ami_info:
        owners: <OWNER>
        region: <REGION>
        filters:
          name: <NAME>
      register: amis

    - name: Print latest AMI ID
      ansible.builtin.debug:
        msg: "{{ amis.images[-1].image_id }}"
```
{% endraw %}

You'll need to fill in `<REGION>`, `<NAME>`, and `<OWNER>` the same way as in the [AWS CLI section](#aws-cli). For
example, to look up the ID of the most recent AMD Amazon Linux 2023 AMI in `us-east-2`, you'd fill in the following
values:

{% raw %}
```yaml
- name: Example Playbook
  hosts: localhost
  gather_facts: no
  tasks:
    - name: 'Get AMI IDs'
      amazon.aws.ec2_ami_info:
        owners: amazon
        region: us-east-2
        filters:
          name: al2023-ami-2023.*-x86_64
      register: amis

    - name: Print latest AMI ID
      ansible.builtin.debug:
        msg: "{{ amis.images[-1].image_id }}"
```
{% endraw %}

And to look up the ID of the most recent Ubuntu 24.04 AMI in `us-east-2`, you'd fill in the following:

{% raw %}
```yaml
- name: Example Playbook
  hosts: localhost
  gather_facts: no
  tasks:
    - name: 'Get AMI IDs'
      amazon.aws.ec2_ami_info:
        owners: 099720109477
        region: us-east-2
        filters:
          name: ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*
      register: amis

    - name: Print latest AMI ID
      ansible.builtin.debug:
        msg: "{{ amis.images[-1].image_id }}"
```
{% endraw %}

If this code was in a Playbook called _example-playbook.yml_, you could run it using the following command, and it will
print the ID of the most recent AMI to `stdout`:

```bash
ansible-playbook -v example-playbook.yml
```

You can also use the AMI ID value in the rest of your Ansible code, such as the following code for launching an EC2
instance with the AMI you just found:

{% raw %}
```yaml
- name: Launch EC2 instance
  amazon.aws.ec2_instance:
    name: "example"
    instance_type: t2.micro
    region: us-east-2
    image_id: "{{ amis.images[-1].image_id }}"
```
{% endraw %}

## SSM Parameter Store Aliases

Under the hood, the preceding recipes all use the [`DescribeImages`
API](https://docs.aws.amazon.com/AWSEC2/latest/APIReference/API_DescribeImages.html) to look up the latest AMI ID. This
is a good, generic way to look up AMI IDs that you can adapt to find the IDs for any AMIs, and to filter the results in 
many different ways. However, there is a trick that few people seem to know about which you can use to simplify things 
when you just want the latest version of the most commonly-used AWS AMIs: _Aliases_ in _System Manager (SSM) Parameter 
Store_.

[SSM Parameter Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html)
is an AWS service that can store configuration data. What most people don't know is that AWS stores the IDs of its most 
recent AMIs as public values in SSM Parameter Store, and most tools can look up these IDs for you automatically, giving
you the latest AMI ID, in any region, without any extra lookup steps! 

To use this functionality, you set the AMI ID to `resolve:ssm:<AMI_NAME>`, where `<AMI_NAME>` is 
`/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64` for Amazon Linux and 
`/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id` for Ubuntu. For example, with the 
AWS CLI, you can launch an EC2 instance with the latest Amazon Linux AMI with the following command:

```bash
aws ec2 run-instances \
  --region us-east-2 \
  --image-id "resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" \
  --instance-type "t2.micro"
```

And you can launch an EC2 instance with the latest Ubuntu AMI with the following:

```bash
aws ec2 run-instances \
  --region us-east-2 \
  --image-id "resolve:ssm:/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id" \
  --instance-type "t2.micro"
```

The same trick works in Ansible, too. For example, the following Ansible Playbook can launch an EC2 instance with the
latest Amazon Linux AMI:

```yaml
- name: Example Playbook
  hosts: localhost
  gather_facts: no
  tasks:
    - name: Launch EC2 instance
      amazon.aws.ec2_instance:
        name: "example"
        instance_type: t2.micro
        region: us-east-2
        image_id: "resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
```

It works in OpenTofu and Terraform, too:

```terraform
provider "aws" {
  region = "us-east-2"
}

resource "aws_instance" "example" {
  ami           = "resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
  instance_type = "t2.micro"
}
```

The only place it doesn't seem to work is with Packer: setting `source_ami` to a `resolve:ssm:/...` value results in 
an `InvalidAMIID.Malformed` error. That said, you can use the [`amazon-parameterstore` data 
source](https://developer.hashicorp.com/packer/integrations/hashicorp/amazon/latest/components/data-source/parameterstore)
to resolve the AMI ID yourself, which requires slightly less code than the `amazon-ami` data source:

```hcl
data "amazon-parameterstore" "image" {
  name   = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
  region = "us-east-2"
}

source "amazon-ebs" "example" {
  ami_name        = "custom-ami"
  ami_description = "Example of a custom AMI built using Packer."
  instance_type   = "t2.micro"
  region          = "us-east-2"
  source_ami      = data.amazon-parameterstore.image.value
  ssh_username    = "ec2-user"
}
```

## Conclusion

You've now seen five recipes for fetching the latest AMI ID for Amazon Linux and Ubuntu. To go further, here are a few 
exercises you can try at home to get your hands dirty:

- The recipes you saw all look up AMIs for use with [AMD CPUs](https://aws.amazon.com/ec2/amd/). Try updating the AMI 
  names to instead look up [Graviton CPUs](https://aws.amazon.com/ec2/graviton/) (you'll need to replace `x86_64` in
  the Amazon Linux name and `amd64` in the Ubuntu AMI name with `arm64`). 
- Learn how [AWS names and versions its Amazon Linux AMIs](https://docs.aws.amazon.com/linux/al2023/ug/naming-and-versioning.html)
  and how [Canonical names and versions its Ubuntu AMIs](https://documentation.ubuntu.com/aws/en/latest/aws-how-to/instances/find-ubuntu-images/).
  See also the [SSM Parameter Store values](https://docs.aws.amazon.com/linux/al2023/ug/ec2.html#launch-via-aws-cli) 
  Amazon maintains. 
- Learn how to create
  [aliases for your AMIs in SSM Parameter Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/parameter-store-ec2-aliases.html)
  so that you can find the latest version of your own AMIs using a simple syntax like `ssm:resolve:/my-ami-name`.
- Learn how to apply additional filters to the AMI search, such as EBS volume type, hypervisor, and virtualization type 
  (to see what's supported, see the [filters parameter of the `DescribeImages` 
  API](https://docs.aws.amazon.com/AWSEC2/latest/APIReference/API_DescribeImages.html)).  
- If you're using a non-commercial region, such as GovCloud or China, see [Canonical's Ubuntu images on AWS 
  docs](https://documentation.ubuntu.com/aws/en/latest/aws-how-to/instances/find-ubuntu-images/) for the alternative
  owner ID you'll need to use.

To learn how to use AMIs, create your own custom AMIs, and use other server templating techniques (e.g., Docker), check 
out _[Fundamentals of DevOps and Software Delivery]({{ site. url }})_!

## Footnotes

[^1]: OpenTofu is an [open source fork of Terraform](https://opentofu.org/blog/opentofu-announces-fork-of-terraform/) that was created after Terraform moved away from an open source license. I prefer to use open source tools whenever possible, so this blog post will use OpenTofu for example code, but the examples should work with Terraform as well.
---
layout: resource
title: "How to manage state and environments with OpenTofu"
description: "Learn about OpenTofu's powerful features for managing state, and how they differ from Terraform, including how to store state, encrypt state, and how to manage state across multiple environments."
image: "/resources/how-to-manage-state-and-environments-with-opentofu/tofu-state-envs.png"
---

By default, [OpenTofu](https://opentofu.org/) and [Terraform ](https://www.terraform.io/) record information about what 
infrastructure they created in a _state file_ on your local file system called _terraform.tfstate_. For personal 
projects, this works just fine, but for professional projects with a team, you need a way to manage state that supports 
collaboration, locking, encryption, and multiple environments. A few years ago, I wrote a [guide to managing state with 
Terraform](https://blog.gruntwork.io/how-to-manage-terraform-state-28f5697e68fa) and [managing multiple environments 
with Terraform](https://blog.gruntwork.io/how-to-manage-multiple-environments-with-terraform-32c7bc5d692). Since then,
OpenTofu has added several important features that provide new ways to solve these problems. This blog post is a 
tutorial on how to manage state and environments with OpenTofu in a way that is more secure and more convenient than 
what you can do with Terraform. Here's an outline of what I'll cover:

* [A short primer on state](#a-short-primer-on-state)
* [How to store state](#how-to-store-state)
* [How to protect state](#how-to-protect-state)
* [How to manage multiple environments](#how-to-manage-multiple-environments)

Let's get started with a quick primer on state.

## A short primer on state

Why does OpenTofu need to store state in the first place? To answer this question, consider the following OpenTofu
configuration:

```terraform
provider "aws" {
  region = "us-east-2"
}

resource "aws_instance" "server" {
  ami           = "ami-0900fe555666598a2"
  instance_type = "t2.micro"
}
```

If you run `tofu apply` on this configuration, OpenTofu will deploy a single server (an EC2 instance) in AWS. If you 
then run `tofu destroy`, it will undeploy that same server. But wait, you could have dozens of servers in your AWS 
account—some deployed via OpenTofu, some deployed via scripts, some deployed via the console, and so on—so how does 
OpenTofu know _which_ server to undeploy? 

This is where the state file comes in. When you run `tofu apply` that first time, OpenTofu will record information 
about what infrastructure it created in a _state file_. By default, this will be a _terraform.tfstate_ file in the same 
folder as your OpenTofu configuration. This file contains a custom JSON format that records a mapping from the 
resources in your configuration files to the representation of those resources in the real world. For example, here's
a small snippet (truncated for readability) of the _terraform.tfstate_ file you might get from running `tofu apply` on 
the OpenTofu configuration above that deployed an EC2 instance in AWS:

```json
{
  "version": 4,
  "terraform_version": "1.9.0",
  "serial": 2,
  "lineage": "2aaa08eb-6f29-48ba-071a-6a41d0ac1eb9",
  "resources": [
    {
      "mode": "managed",
      "type": "aws_instance",
      "name": "server",
      "provider": "provider[\"registry.opentofu.org/hashicorp/aws\"]",
      "instances": [
        {
          "schema_version": 1,
          "attributes": {
            "ami": "ami-0900fe555666598a2",
            "availability_zone": "us-east-2a",
            "id": "i-0c97b0e1637c204a8",
            "instance_state": "running",
            "instance_type": "t2.micro"
          }
        }
      ]
    }
  ]
}
```

Using this JSON format, OpenTofu knows that a resource with type `aws_instance` and name `server` corresponds to an 
EC2 Instance in your AWS account with ID `i-0c97b0e1637c204a8`. Every time you run OpenTofu, it can fetch the latest 
status of this EC2 Instance from AWS and compare that to what's in your OpenTofu configuration to determine what 
changes need to be applied. 

If you're using OpenTofu for a personal project, storing state in a single _terraform.tfstate_ file that lives locally 
on your computer works just fine. But if you want to use OpenTofu professionally, with a team, this way of handling 
state causes several problems:

* **Shared storage for state files.** Each of your team members needs access to the same state files. That means you 
  need to store those files in a shared location, and to ensure that OpenTofu knows to pull the latest state from 
  this location before every `apply`/`destroy` and to push the latest state to this location after every 
  `apply`/`destroy`. Moreover, as soon as data is shared, you run into a new problem: concurrency. If two 
  team members are running OpenTofu at the same time, you can run into race conditions as multiple OpenTofu processes 
  make concurrent updates to the state files, leading to conflicts, data loss, and state file corruption. Therefore, 
  you need to store state in a shared location that is integrated with OpenTofu and supports distributed locking.

* **Protecting state files.** OpenTofu state files may contain secrets. For example, if you use the 
  [`aws_db_instance`](https://search.opentofu.org/provider/hashicorp/aws/latest/docs/resources/db_instance)
  resource to deploy a database using Amazon RDS, the state file will store the root user password for that database.
  Therefore, you need to ensure that state files are encrypted, in transit and at rest (you'll learn more about 
  encryption in Chapter 8 of _[Fundamentals of DevOps and Software Delivery]({{ site.url }})_). 

* **Managing state files across multiple environments.** Most companies run infrastructure across several environments 
  (e.g., dev, stage, and prod) that are isolated from each other (e.g., so someone making a change in stage has no way 
  of accidentally affecting prod). That means you need a way to isolate state files for different environments as well 
  (e.g., so someone running `tofu apply` in stage has no way of accidentally affecting prod). 

The following three sections show how to solve each of these three problems with OpenTofu, starting with shared storage 
for state files.

## How to store state

The most common technique for allowing multiple team members to access a common set of files is to put them in version 
control (e.g., Git). Although you should definitely store your OpenTofu configurations in version control, you should
_not_ store your OpenTofu state in version control, as version control does not provide the type of integration (i.e.,
automatic push/pull before/after running `apply` or `destroy`), distributed locking, and protection you need for state 
files.

Instead of using version control, the way to store state in both Terraform and OpenTofu is to use a 
_[backend](https://opentofu.org/docs/language/settings/backends/configuration/)_, which is a plugin that control how
OpenTofu loads and stores state. If you don't specify a backend, the default is the [local 
backend](https://opentofu.org/docs/language/settings/backends/local/), which stores the state file on your local disk. 
OpenTofu supports a number of other backends that can store state in a variety of data stores, including [Amazon 
S3](https://opentofu.org/docs/language/settings/backends/s3/), [Azure Blob 
Storage](https://opentofu.org/docs/language/settings/backends/azurerm/), and [Google Cloud 
Storage](https://opentofu.org/docs/language/settings/backends/gcs/). 

Let's go through an example of using Amazon S3 as a backend. It's a good choice for a backend as it's a fully managed 
service that supports [high levels of durability and 
availability](https://docs.aws.amazon.com/AmazonS3/latest/userguide/DataDurability.html), encryption, locking (via 
[DynamoDB](https://aws.amazon.com/dynamodb/), Amazon's distributed key-value store), and versioning, and it's 
inexpensive (most OpenTofu usage fits into the [AWS free tier](https://aws.amazon.com/free/)). 

To use S3 as a backend, you must first create an S3 bucket and DynamoDB table. One way to do this is to use an OpenTofu 
module from the [book's sample code repo](https://github.com/brikis98/devops-book) called 
[`state-bucket`](https://github.com/brikis98/devops-book/tree/main/ch5/tofu/modules/state-bucket), which can create an 
S3 bucket (including enabling versioning, turning on default server-side encryption, and blocking all public access
to the bucket) and a DynamoDB table. To use the `state-bucket` module, create a new folder called _tofu-state_ to use 
as a root module:

```console
$ mkdir -p tofu-state
$ cd tofu-state
```

Within the _tofu-state_ folder, create a _main.tf_ file with the contents shown below:

```terraform
provider "aws" {
  region = "us-east-2"
}

module "state" {
  source = "github.com/brikis98/devops-book//ch5/tofu/modules/state-bucket"

  # TODO: fill in your own bucket name!
  name = "fundamentals-of-devops-tofu-state"
}
```

This code sets just one parameter, `name`, which will be used as the name of the S3 bucket and DynamoDB table. Note
that S3 bucket names must be _globally_ unique among all AWS customers. Therefore, you _must_ change the `name`
parameter from `"fundamentals-of-devops-tofu-state"` (which I already created) to your own name. Make sure to remember
this name and take note of what AWS region you're using, as you'll need both pieces of information again a little
later.

To create the S3 bucket and DynamoDB table, [authenticate to AWS
](/resources/2025/01/25/authenticate-to-aws-with-iam-identity-center/), and run `tofu init` and `tofu apply`:

```console
$ tofu init
$ tofu apply
```

Once `apply` is done, you can start using the S3 bucket and DynamoDB table for state storage. To do that, you need to
update your OpenTofu modules with a `backend` configuration. A common convention is to add a _backend.tf_ file to your
modules as shown below:

```terraform
terraform {
  backend "s3" {
    # TODO: fill in your own bucket name here!
    bucket         = "fundamentals-of-devops-tofu-state"  # <1>
    key            = "<PATH_TO_MODULE>/terraform.tfstate" # <2>
    region         = "us-east-2"                          # <3>
    encrypt        = true                                 # <4>
    # TODO: fill in your own DynamoDB table name here!
    dynamodb_table = "fundamentals-of-devops-tofu-state"  # <5>
  }
}
```

Here's what this code does:

1. Configure the S3 bucket to use as a backend. Make sure to fill in your own S3 bucket's name here.
2. The filepath within the S3 bucket where the OpenTofu state file should be written. You can use a single S3 bucket
   and DynamoDB table to store the state file for many different root modules, so long as you ensure that each root
   module gets a unique `key` (filepath) for its state file. I recommend setting `<PATH_TO_MODULE>` to the file path
   of the module within your repo. For example, if you put the OpenTofu configuration to deploy an EC2 instance 
   from the start of this blog post in a repo called `live` at the path _live/stage/ec2-instance_, then when adding a
   `backend` block to that module, you should set the `key` to _live/stage/ec2-instance/terraform.tfstate_, as then the
   module and its state live at the same paths within the repo and S3 bucket, respectively.
3. The AWS region where you created your S3 bucket.
4. Setting `encrypt` to `true` ensures that your OpenTofu state will be encrypted on disk when stored in S3. You
   already enabled default encryption in the S3 bucket itself, so this is here as a second layer to ensure that the
   data is always encrypted.
5. The DynamoDB table to use for locking. Make sure to fill in your own DynamoDB table's name here (if you used the
   `state-bucket` module, this will be the same name as the S3 bucket).

Now, when you run `tofu init` on this module, it will start using S3 as a backend. Note that if you already had a 
state file for the module that used a different backend—e.g., a local _terraform.tfstate_ file from the local 
backend—then when you run `tofu init`, you'll see a message that looks like this:

```console
$ tofu init

Initializing the backend...
Do you want to copy existing state to the new backend?
  Pre-existing state was found while migrating the previous "local" backend
  to the newly configured "s3" backend. No existing state was found in the
  newly configured "s3" backend. Do you want to copy this state to the new
  "s3" backend? Enter "yes" to copy and "no" to start with an empty state.

  Enter a value:
```

OpenTofu will automatically detect that you already have a state file in some other backend and prompt you to copy it 
to the new S3 backend. If you type *`yes`* and hit ENTER, you should see the following:

```console
Successfully configured the backend "s3"! OpenTofu will automatically
use this backend unless the backend configuration changes.
```

You've now seen how to solve the first problem: shared storage for state files. With the `backend` block in your 
configuration, OpenTofu will automatically pull the latest state from this S3 bucket before running `apply`
or `destroy` and automatically push the latest state to the S3 bucket after running `apply` or `destroy`, and it'll use 
DynamoDB for locking. Let's now move on to the second problem: protecting state files. 

## How to protect state

Protecting your state file is mostly about ensuring that it is encrypted at all times, both in transit, and at rest. 
This problem is partially solved by some of the built-in backends. For example, the S3 backend you set up in the 
previous section offers _server-side encryption_. That is, when the S3 servers write your state file to disk, 
they encrypt it using AES, and when they send it over the wire to your computer, they encrypt it using TLS.  

So you're all set, right? Well, not quite. First, not all backends support server-side encryption. Second, even for
backends that do support it, it's only a partial solution: 

* **Weak access controls**. Since a single backend (e.g., a single S3 bucket) could contain state files for dozens
  of different modules, it's all too easy to accidentally grant someone access to state files (and therefore, secrets)
  they shouldn't have access to. Some backends support fine-grained access controls (e.g., you can use IAM to control 
  access to individual paths within an S3 bucket), but most real-world usage is coarse-grained, either granting access
  to the entire backend (e.g., the entire S3 bucket), or not at all. 

* **Unencrypted state on the client**. Once the state file is on the client computer (e.g., your computer, you team 
  members' computers, the CI server computers), there are cases where the state file gets written to disk without any 
  encryption. For example, if you hit `CTRL+C` in the middle of an `apply`, or there's a network issue preventing 
  saving the state file to the backend, OpenTofu will save the state in a local file called _errored.tfstate_ that is 
  unencrypted.

* **Single layer of defense**. Even when server-side encryption is working perfectly, it's still just one layer of 
  defense. A single error anywhere (such as the many cases we've seen of data breaches due to misconfigured S3 buckets: 
  e.g., [Accenture](https://www.securityweek.com/accenture-exposed-data-unprotected-cloud-storage-bucket/),
  [Netflix and TD Bank](https://threatpost.com/leaky-amazon-s3-buckets-expose-data-of-netflix-td-bank/146084/), 
  [Sennheiser](https://www.itpro.com/cloud/amazon-s3/361864/sennheiser-exposed-data-28000-customers-aws-s3-bucket)), 
  and you may end up leaking state files and secrets. And given that server-side encryption is usually completely 
  transparent (e.g., with S3, you just have to trust that AWS is encrypting the files on disk, as you have no way to 
  actually verify that), it's easy to forget to turn it on, as the user experience is exactly the same whether it's on 
  or not. As you'll learn in Chapter 7 of _[Fundamentals of DevOps and Software Delivery]({{ site.url }})_, the way to
  protect against this is to use a _defense in depth strategy_, where you set up multiple layers of protection 
  to ensure you're never one mistake away from disaster.

This is where _client-side encryption_, where you encrypt the state client-side, before it leaves your computer, 
comes into the picture. Currently, this is something that is _only_ supported in OpenTofu. To enable client-side 
encryption, you need to specify a _key provider_, which tells OpenTofu where it can find the key to use for encryption 
and decryption. You can either provide the encryption key yourself via the 
[PBKDF2 provider](https://opentofu.org/docs/language/state/encryption/#pbkdf2), or you can use a cloud-managed key
via the [AWS KMS](https://opentofu.org/docs/language/state/encryption/#aws-kms) and [GCP 
KMS](https://opentofu.org/docs/language/state/encryption/#gcp-kms) providers. 

Let's go through an example of using AWS KMS as a key provider. It's a good choice for a key provider as it's a fully 
managed service that provides [high levels of durability and
availability](https://docs.aws.amazon.com/kms/latest/developerguide/data-protection.html), and stores keys securely 
using hardware security modules (HSMs) that ensure the key material can never leave the HSM security boundary.

To use KMS as a key provider, you must first create a KMS key. One way to do this is to use an OpenTofu module from the 
[book's sample code repo](https://github.com/brikis98/devops-book) called 
[`kms-key`](https://github.com/brikis98/devops-book/tree/main/ch5/tofu/modules/kms-key), which can create a key in 
KMS that can be used for symmetric encryption, a basic access policy, and an alias for the key (so you can refer to it 
by a human-friendly name rather than a long, randomly-generated ID). 

**NOTE: AWS KMS is NOT free to use**. As per the [KMS pricing page](https://aws.amazon.com/kms/pricing/), each
key that you create in AWS KMS costs $1/month (prorated hourly). There is also a charge for key usage, though the AWS
free tier includes 20,000 requests/month at no cost. 

To use the `kms-key` module, add the following code to _main.tf_ in your _tofu-state_ module:

```terraform
module "key" {
  source = "github.com/brikis98/devops-book//ch5/tofu/modules/kms-key"

  name = "tofu-state-key"
}
```

The preceding code will create a KMS key with the alias `alias/tofu-state-key` and it'll grant the user running
`apply` admin (management) and usage (encrypt/decrypt) permissions for that key. If you want to grant other users
admin or usage permissions, use the `administrator_iam_arns` and `user_iam_arns` input variables, respectively. 

Run `tofu init` and `tofu apply` one more time to create the KMS key:

```console
$ tofu init
$ tofu apply
```

Once `apply` is done, you can update your `backend` configuration as follows to enable client-side encryption using
this key:

```terraform
terraform {
  encryption {
    # <1>
    key_provider "aws_kms" "tofu_state_key" {
      kms_key_id = "alias/tofu-state-key"
      region     = "us-east-2"
      key_spec   = "AES_256"
    }

    # <2>
    method "aes_gcm" "tofu_state_key" {
      keys = key_provider.aws_kms.tofu_state_key
    }

    # <3>
    method "unencrypted" "migrate" {}

    # <4>
    state {
      method = method.aes_gcm.tofu_state_key
      fallback {
        method = method.unencrypted.migrate
      }
    }    
  }
  
  backend "s3" {
    # ... params omitted ...
  }
}
```

This code adds an `encryption` block (above the `backend` block you added in the previous section) that does the 
following:

1. Specify the KMS key you just created as a key provider.
2. Specify AES GCM as the encryption method, using the KMS key as the encryption key.
3. Specify "unencrypted" as an encryption method. This is only necessary if you already have a state file without
   client-side encryption (e.g., the state file from the previous section). Once you've run `init` to migrate this
   state file to use client-side encryption, you can remove this method from your code.
4. Tell OpenTofu to use AES GCM as the method for encrypting state client-side. Note the use of the `fallback` block
   to allow OpenTofu to use the unencrypted method for reading (but not writing) state if it fails to decrypt it with
   GCM. Again, this is only necessary if you already have a state file without client-side encryption; after you run
   `init`, you can remove this `fallback` block.

Run `tofu init` to enable client-side encryption. If this completes successfully, your state will now be encrypted.
You can even try to open the _terraform.tfstate_ file in your S3 bucket, and it'll look something like this now 
(truncated for readability):

```json
{
  "serial": 2,
  "lineage": "d840b608-8402-0dc7-f5fe-57af20b2799d",
  "meta": {
    "key_provider.aws_kms.tofu_state_key": "eyJjaXBo (...)"
  },
  "encrypted_data": "RpBRdOSp1jWXbqQfby9w (...)",
  "encryption_version": "v0"
}
```

As you can see, all the data is now encrypted. Client-side encryption provides a more complete solution to protecting
your state files: you tend to do a better job with access controls, you avoid ever having unencrypted state on the 
client, and you now have multiple layers of defense (by using both client-side and server-side encryption). There's now 
one final problem left: how to manage state files across multiple environments. This is the topic of the next section.

## How to manage multiple environments

Most companies run infrastructure across multiple environments, such as dev, stage, and prod. The question is, how do 
you organize your OpenTofu code to support multiple environments? In particular, how do you organize your code to
best support the following set of requirements:

* **Minimize code duplication.** If you wanted to deploy some OpenTofu code in three environments, how do you avoid
  having to copy/paste that code three times?

* **See and navigate environments.** From merely looking at your OpenTofu code, can you easily tell what environments
  exist, and what is deployed in each one?

* **Different settings in each environment.** How can you configure the code differently in each environment? For 
  example, how do you configure dev and stage to run smaller or fewer servers than prod?

* **Different backends for each environment.** How do you ensure that the backends you're using to store state in each 
  environment are isolated from each other? If all the state for all environments is in a single backend, then while 
  changing dev or stage, you might accidentally mess up the state for prod! For example, in AWS, you typically use
  separate AWS accounts for each environment, which means that you'll also want to have separate S3 buckets, one in 
  each AWS account, to use as backends for each environment.

* **Different versions in each environment.** OpenTofu allows you to package code into reusable modules and to version
  those modules ([learn more 
  here](https://blog.gruntwork.io/how-to-create-reusable-infrastructure-with-terraform-modules-25526d65f73d)). How do 
  you deploy different versions of a module in different environments? For example, is there a way to test v2.0.0 of
  a module in dev while prod continues to run v1.0.0?

* **Share data between modules.** If your code is spread across multiple modules—e.g., one module to manage networking,
  one module to manage data stores, one module to manage app servers—how do you share data between them? E.g., What if
  the data store module needs data from the networking module?

* **Work with multiple modules concurrently.** If your code is spread across multiple modules, do you have a way to 
  work with multiple modules at the same time? E.g., If you had networking, data store, and app server modules, to 
  spin up a new environment, do you have to run `apply` three separate times, in just the right order, or is there a
  way to automate that process?

* **No extra tooling to learn or use.** Do you need to learn, configure, and maintain new tools to use this strategy?

With Terraform code, the three main options for managing multiple environments were workspaces, branches, and 
Terragrunt; I compared all three according to the criteria above (plus a few others) in [this blog post 
series](https://blog.gruntwork.io/how-to-manage-multiple-environments-with-terraform-32c7bc5d692). You can read that
series for the full details, but the following table shows a summary of how these three options compared (more
black squares = better):

{:.monofont}
|                                         | Workspaces | Branches | Terragrunt 
|-----------------------------------------|------------|----------|------------
| Minimize code duplication               | ■■■■■      | □□□□□    | ■■■■□      
| See and navigate environments           | □□□□□      | ■■■□□    | ■■■■■      
| Different settings in each environment  | ■■■■■      | ■■■■□    | ■■■■■      
| Different backends for each environment | □□□□□      | ■■■■□    | ■■■■■      
| Different versions in each environment  | □□□□□      | ■■□□□    | ■■■■■      
| Share data between modules	            | ■■□□□      | ■■□□□    | ■■■■■      
| Work with multiple modules concurrently	| □□□□□      | □□□□□    | ■■■■■      
| No extra tooling to learn or use	     	| ■■■■■      | ■■■■■    | □□□□□      

Each of the options has some strengths and weaknesses. With OpenTofu, which supports early variable evaluation as of
[version 1.8](https://opentofu.org/blog/opentofu-1-8-0/), we now have a new approach to consider for managing multiple 
environments: _defining environments in variable definition files_.

Let's go through an example so you can see how it works. Go back to the EC2 module you've been using throughout this
blog post, and add a _variables.tf_ file with the following code:

```terraform
variable "environment" {
  description = "The environment (e.g., dev, stage, prod) to deploy into"
  type        = string
  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "The environment must be one of: dev, stage, prod."
  }  
}

variable "instance_type" {
  description = "The type of EC2 instance to run"
  type        = string
}
```

This code defines two input variables:

* `environment`: The name of the environment we're in. Must be one of: dev, stage, prod.
* `instance_type`: The type of EC2 instance to deploy.

Update _backend.tf_ to use the new `environment` input variable in the `backend` block:

```terraform
backend "s3" {
  bucket = "fundamentals-of-devops-tofu-state-${var.environment}" 
  
  # ... (other params omitted) ...
}
```

The change is that the `bucket` value now includes `${var.environment}`, which means that you'll end up using a 
different S3 bucket to store state in each environment, which keeps your state completely isolated (note that you'll
need to create the S3 bucket, DynamoDB table, and KMS key for each environment). This may seem like a simple and 
obvious approach, but using variables in the `backend` configuration is not allowed in Terraform (it requires all 
`backend` configurations to be hard-coded), whereas OpenTofu allows this as of version 1.8.0 thanks to support for 
early variable evaluation. 

Next, go into _main.tf_, and update the code to set the instance type based on the `instance_type` input variable:

```terraform
resource "aws_instance" "server" {
  ami           = "ami-0900fe555666598a2"
  instance_type = var.instance_type
}
```

Now defining an environment is as simple as adding a _[variable definition 
file](https://opentofu.org/docs/language/values/variables/#variable-definitions-tfvars-files)_. For example, to define
the dev environment, create a _dev.tfvars_ file with the following contents:

```hcl
environment   = "dev"
instance_type = "t2.micro"
```

And to define a prod environment, create a _prod.tfvars_ file as follows:

```hcl
environment   = "prod"
instance_type = "m7i.large"
```

Now, when you run OpenTofu commands, you pass in the variable definition file for the environment you want to use via
the `-var-file` flag. For example, to make updates to the dev environment, you would run the following:

```console
$ tofu init -var-file=dev.tfvars
$ tofu apply -var-file=dev.tfvars
```

And to make updates to the prod environment, you would run the following:

```console
$ tofu init -var-file=prod.tfvars
$ tofu apply -var-file=prod.tfvars
```

OpenTofu even supports using variables in module `source` URLs (whereas Terraform only allows hard-coded values), which
allows you to use different versions in different environments. For example, instead of writing an `aws_resource`
configuration by hand, you could deploy an EC2 instance by updating _main.tf_ to use the `ec2-instance` module from
the book's sample code repo as follows:

```terraform
module "instance" {
  source = "github.com/brikis98/devops-book//ch2/tofu/modules/ec2-instance?ref=${var.instance_module_version}"

  name          = "example"
  instance_type = var.instance_type
  ami_id        = "ami-0900fe555666598a2"
}
```

Note that the `source` URL includes a `ref` parameter. This can be any valid Git reference, such as a tag. The
preceding code sets the `ref` parameter to an input variable named `instance_module_version`. Add this input variable
to _variables.tf_ as follows:

```terraform
variable "instance_module_version" {
  description = "The version of the ec2-instance module to use"
  type        = string
}
```

Now you can use different versions of this module in different environments. For example, you could have version 1.0.0
deployed in prod by updating _prod.tfvars_ as follows:

```hcl
instance_module_version = "1.0.0"
```

In the meantime, you could test out version 2.0.0 in dev by updating _dev.tfvars_ as follows:

```hcl
instance_module_version = "2.0.0"
```

With OpenTofu early variable evaluation and variable definition files, you minimize code duplication, it's easy to see
and navigate environments, and you can have different settings, backends, and versions in each environment. Updating 
the comparison table from the [How to manage multiple environments with 
Terraform](https://blog.gruntwork.io/how-to-manage-multiple-environments-with-terraform-32c7bc5d692) blog post,
here's how the OpenTofu variable definition files approach stacks up against workspaces, branches, and Terragrunt (more
black squares = better):

{:.monofont}
|                                         | Workspaces | Branches | Terragrunt | OpenTofu |
|-----------------------------------------|------------|----------|------------|----------|
| Minimize code duplication               | ■■■■■      | □□□□□    | ■■■■□      | ■■■■■    |
| See and navigate environments           | □□□□□      | ■■■□□    | ■■■■■      | ■■■■■    |
| Different settings in each environment  | ■■■■■      | ■■■■□    | ■■■■■      | ■■■■■    |
| Different backends for each environment | □□□□□      | ■■■■□    | ■■■■■      | ■■■■■    |
| Different versions in each environment  | □□□□□      | ■■□□□    | ■■■■■      | ■■■■■    |
| Share data between modules	            | ■■□□□      | ■■□□□    | ■■■■■      | ■■□□□    |
| Work with multiple modules concurrently	| □□□□□      | □□□□□    | ■■■■■      | □□□□□    |
| No extra tooling to learn or use	     	| ■■■■■      | ■■■■■    | □□□□□      | ■■■■■    |

OpenTofu is the strongest option across the board. The only place it comes up a bit short is in sharing data between
modules and working with multiple modules concurrently, which is where [Terragrunt](https://terragrunt.gruntwork.io/)
shines (especially [Terragrunt Stacks](https://terragrunt.gruntwork.io/docs/features/stacks/)), and of course, you can
use Terragrunt and OpenTofu together!  

## Conclusion

You now know the basics of storing state, protecting state, and managing environments with OpenTofu. To go further, 
here are a few exercises you can try at home to get your hands dirty:

* Minimize duplication in your `backend` config by creating [partial configuration 
  files](https://opentofu.org/docs/language/settings/backends/configuration/#partial-configuration) that you can reuse
  across all your modules (instead of copy/pasting the same `backend` block into each module).
* For a comprehensive guide to Terraform and OpenTofu, check out my other book, _[Terraform: Up & 
  Running](https://www.terraformupandrunning.com/)_.

To learn how to integrate OpenTofu and multiple environments into your software delivery process,
check out _[Fundamentals of DevOps and Software Delivery]({{ site.url }})_!



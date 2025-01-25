---
layout: resource
title: "How to authenticate to AWS with IAM Identity Center"
description: "Learn the modern and secure way to authenticate to AWS, both on the web and the command line, using IAM Identity Center."
image: "/resources/authenticate-to-aws-with-iam-identity-center/aws-iam-identity-center.png"
---

For many years, the main way to authenticate to AWS was to use _[Identity and Access Management 
(IAM)](https://aws.amazon.com/iam/)_, but in the last few years, AWS has been pushing users towards the newer _[IAM 
Identity Center](https://aws.amazon.com/iam/identity-center/)_ (formerly known as AWS SSO). This blog post is a short 
guide to this more modern and secure way to authenticate to AWS, both on the web and the command line. Here's an 
outline of what this post will cover:

- [Prerequisite: create an AWS account](#prerequisite-create-an-aws-account)
- [Enable IAM Identity Center](#enable-iam-identity-center)
- [Create permission sets](#create-permission-sets)
- [Create groups](#create-groups)
- [Create or sync users](#create-or-sync-users)
- [Authenticate to AWS on the web](#authenticate-to-aws-on-the-web)
- [Authenticate to AWS on the command line](#authenticate-to-aws-on-the-command-line)

Let's get started by taking care of a prerequisite: creating an AWS account.

## Prerequisite: create an AWS account

This is a guide to authenticating to AWS, so of course you need an AWS account! If you don't already have one, do
the following:

1. **Sign up**. Head over to https://aws.amazon.com and follow the on-screen instructions to sign up. You'll have to 
   provide a credit card for payment, but AWS offers a [generous free tier](https://aws.amazon.com/free), which 
   includes the IAM Identity Center, so following this guide shouldn't cost you anything.
2. **Protect the root user credentials**. When you first register for AWS, you initially sign in as the _root user_. 
   It's critical to protect the root user account, so make sure to store the root user credentials in a secure password 
   manager (e.g., [1Password](https://1password.com/), [BitWarden](https://bitwarden.com/)). You'll learn more 
   about secrets management in Chapter 8 of _[Fundamentals of DevOps and Software Delivery]({{ site.url }})_). 
3. **Enable MFA for the root user**. As an additional layer of protection, make sure to enable [_multi-factor
   authentication (MFA)_ for the root user](https://docs.aws.amazon.com/IAM/latest/UserGuide/enable-mfa-for-root.html).

The root user, by design, has permissions to do absolutely anything in your AWS account, including bypassing most 
security restrictions you put in place, so from a security perspective, it's not a good idea to use the root user on a 
day-to-day basis. In fact, the _only_ thing you should use the root user for is to create other user accounts in the 
IAM Identity Center with more-limited permissions, and then switch to one of those accounts immediately, as described 
in the following steps.

## Enable IAM Identity Center

By default, when you create a new AWS account, IAM Identity Center is not enabled. To enable it, head over to the 
[IAM Identity Service Console](https://console.aws.amazon.com/singlesignon), and if you see an Enable IAM Identity 
Center button, as shown in the image below, click it! 

![Enable IAM Identity Center](/assets/img/resources/authenticate-to-aws-with-iam-identity-center/identity-center-enable.png)

On the next screen, select Enable with AWS Organizations, click Continue, and wait a minute or two for IAM Identity 
Center to be available. Once the IAM Identity Center dashboard loads, on the right side, you should see several
pieces of information, as shown in the following image:

![Take note of the AWS region and AWS access portal URL from the IAM Identity Center dashboard](/assets/img/resources/authenticate-to-aws-with-iam-identity-center/identity-center-dashboard.png)

Take note of the following two pieces of information:

1. **AWS region**: Jot down which AWS region you're using for AWS Identity Center. It'll be something like "United
   "Europe (Ireland) | eu-west-1" or "States (Ohio) | us-east-2". You can learn more about AWS regions 
   [here](https://aws.amazon.com/about-aws/global-infrastructure/regions_az/).
2. **Access portal URL**: Jot down your unique AWS access portal URL. It'll look something like
   `https://d-c123456789.awsapps.com/start/`. 

Write both of these down, as you'll need them later to login.

## Create permission sets

By default, new IAM Identity Center users have no permissions whatsoever and cannot do anything in an AWS account. To 
give a user the ability to do something, you need to associate one or more permission sets with that user. A 
_permission set_ grants permissions by combining one or more _IAM Policies_, which are JSON documents that define what 
you are or aren't allowed to do. You can create your own IAM Policies or use some of the predefined IAM Policies built 
into your AWS account, which are known as _Managed IAM Policies_.

To create a permission set, head over to the [IAM Identity Center Console](https://console.aws.amazon.com/singlesignon), 
select "Permission sets" in the left nav, and click the "Create permission set" button, as shown in the following 
image:

![Permissions sets in the IAM Identity Center](/assets/img/resources/authenticate-to-aws-with-iam-identity-center/identity-center-permission-sets.png)

On the next page, you need to pick a permission set type:

![Pick a permission set type](/assets/img/resources/authenticate-to-aws-with-iam-identity-center/identity-center-permission-set-type.png)

You can either use one of the predefined permission sets (which wrap various AWS managed policies) or create a custom 
permission set. For the purposes of this tutorial, choose "Predefined permission set," and you should see the list of 
available options below:

![Pick a predefined permission set](/assets/img/resources/authenticate-to-aws-with-iam-identity-center/identity-center-predefined-permission-sets.png)

For the purposes of this tutorial, select `AdministratorAccess`, as at least a few of your users will likely need
admin permissions (full access to all AWS services and resources), and click the Next button. On the next page, 
give the permission set a name (I usually stick with the default, which is the name of the policy), set the session
duration to 12 hours (so you aren't logged out more than once per day), and click Next:

![Configure the permission set details](/assets/img/resources/authenticate-to-aws-with-iam-identity-center/identity-center-permission-set-details.png)

Review all the settings on the next page, and if everything looks good, click the Create button.

## Create groups

Although you can assign permissions sets directly to users, it's usually more manageable to assign permissions to 
_groups_ of users. To create a group, head over to the [IAM Identity Center 
Console](https://console.aws.amazon.com/singlesignon), select Groups in the left nav, and click the "Create group" 
button: 

![Groups in the IAM Identity Center](/assets/img/resources/authenticate-to-aws-with-iam-identity-center/identity-center-groups.png)

On the next page, you need to configure the group details, such as the group name and description. For the purposes of
this tutorial, give the group the name `admins`, as you'll be assigning this group the `AdministratorAccess` permission
set you created earlier:

![Configure the group details](/assets/img/resources/authenticate-to-aws-with-iam-identity-center/identity-center-group-details.png)

For now, skip adding any users to the group, and click the "Create group" button. This will take you back to the groups 
page, where you should see your newly-created `admins` group:

![The newly-created admins group](/assets/img/resources/authenticate-to-aws-with-iam-identity-center/identity-center-newly-created-group.png)

Click on your newly-created `admins` group, select the "AWS accounts" tab, and click the "Assign accounts" button: 

![Assign accounts to your newly-created admins group](/assets/img/resources/authenticate-to-aws-with-iam-identity-center/identity-center-group-accounts.png)

On the next page, grant admin access to one or more AWS accounts by selecting those AWS accounts (e.g., such as the
one you may have created in the pre-requisites section), and then selecting the `AdministratorAccess` permission set:

![Grant admin access to your AWS account](/assets/img/resources/authenticate-to-aws-with-iam-identity-center/identity-center-group-assign-accounts.png)

Click the Assign button, and wait a minute or so for that process to complete.

## Create or sync users

Now that IAM Identity Center is configured, you can finally use it to create more limited user accounts. IAM Identity 
Center supports two types of _identity sources_ for users: 

1. **Existing (external) identity provider**. One option is to sync users from an existing identity provider, such 
   as Active Directory, Google Workspace, or Okta.
2. **IAM Identity Center Directory**. Another option is to use IAM Identity Center itself as your identity provider,
   creating users directly in its built-in directory.

For most companies, using an existing identity provider is the best option, as that way, you get _Single Sign-On (SSO)_,
where you can authenticate to AWS using the same login you use for everything else at work, so there are no extra user
accounts or credentials to manage, and when someone leaves the company and is removed from your identity provider
(e.g., removed from Active Directory), they automatically lose access to AWS, too. To set up an existing identity
provider as an identity source, follow the [corresponding tutorial for your identity 
provider](https://docs.aws.amazon.com/singlesignon/latest/userguide/tutorials.html) to set up user syncing, and then
use the groups page to add users to the appropriate groups. 

Alternatively, if you're just using this AWS account for personal learning and testing, you can create a custom user
in the directory built into IAM Identity Center itself. For the purposes of this tutorial, let's try that out. Head
over to the [IAM Identity Center Console](https://console.aws.amazon.com/singlesignon) one more time, select Users
in the left nav, and click the Add User button: 

![IAM Identity Center users](/assets/img/resources/authenticate-to-aws-with-iam-identity-center/identity-center-users.png)

On the next page, enter a username, email address, first name, and last name, leave all other settings at their 
default, and click the Next button:

![Create an IAM Identity Center user](/assets/img/resources/authenticate-to-aws-with-iam-identity-center/identity-center-user-details.png)

On the next page, add the user to the appropriate groups, such as the `admins` group, and click Next: 

![Add the user to the admins group](/assets/img/resources/authenticate-to-aws-with-iam-identity-center/identity-center-user-assign-groups.png)

Review the settings on the next page, and if everything looks good, click the "Add user" button. After a few seconds, 
you should get an invitation email to sign-in via your access portal: 

![Invite email](/assets/img/resources/authenticate-to-aws-with-iam-identity-center/identity-center-portal-invite-email.png)

Click the "Accept invitation" button in the email, and follow the on-screen instructions to set a password for your 
user (make sure to save the password in a secure password manager, such as 1Password or BitWarden), login, and 
configure an MFA device. When you're done with that process, you should be logged into the access portal: 

![Access portal](/assets/img/resources/authenticate-to-aws-with-iam-identity-center/identity-center-access-portal.png)

From now on, you can use your IAM Identity Center user (rather than the root user) and this portal to log in to your
AWS accounts. The following two sections describe how to do that.

## Authenticate to AWS on the web

To access your AWS accounts on the web, first, login to your access portal: you should have the URL saved from when
you configured IAM Identity Center; alternatively, you can find that URL at the bottom of the invite email from when
you created your IAM Identity Center user. Once you're logged in, the access portal should show you the list of AWS
accounts yo have access to. Click the arrow next to one of the accounts, and you should see a link with the name of 
the permission set you have access to, such as `AdministratorAccess`:

![Seeing the permission set you have access to in an account](/assets/img/resources/authenticate-to-aws-with-iam-identity-center/identity-center-portal-auth-to-account.png)

Click on the permission set, and AWS will open up a new tab and log you into that AWS account, with those corresponding
permissions. That's all there is too it!

## Authenticate to AWS on the command line

There are [multiple ways to authenticate to AWS from the command 
line](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-authentication.html). For me, the option that strikes
the best balance between convenience (as it lets me use my browser for authentication) and security (as it only uses
temporary credentials) is to use the [AWS Command Line Interface (CLI)](https://aws.amazon.com/cli/) along with IAM
Identity Center. To use this method, [Install the AWS 
CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) (make sure to install version 2.15
or newer), and the first time you use it, run the `aws configure sso` command:

```console
$ aws configure sso
SSO session name (Recommended): personal
SSO start URL [None]: https://d-c123456789.awsapps.com/start/
SSO region [None]: eu-west-1
SSO registration scopes [sso:account:access]:
```

The AWS CLI will first try to configure a _session_, which roughly corresponds to a single access portal (a single AWS 
Organization). The CLI will prompt you for the following information:

* **SSO session name**. This typically corresponds to the AWS organization where you have AWS Identity Center and an 
  access portal configured. For example, if this is your personal AWS account, you might name it "personal." If this
  is an AWS organization you use at work, and you only have one such organization, you might call name it after your
  company. If your company has multiple AWS organizations, you might name it after those organization names. 
* **SSO start URL**. This is the URL of the access portal you use to log in to your AWS accounts. This is one of the
  pieces of information you saved when configuring IAM Identity Center; it's also in the invitation email you got when
  creating an IAM Identity Center user. It looks something like `https://d-c123456789.awsapps.com/start/`.
* **SSO region name**. This is the AWS region in which you set up AWS IAM Identity Center (e.g., eu-west-1).
* **SSO registration scopes**. You can hit Enter to leave this value at its default (`sso:account:access`).

Once you've filled in all this information, the AWS CLI will open your browser window, which allows you to log in to 
your access portal as usual. Follow the on-screen prompts to authorize the AWS CLI, clicking "Confirm and continue" (if
the code matches what you see in your terminal) and then "Allow access." 

![Authorizing the AWS CLI](/assets/img/resources/authenticate-to-aws-with-iam-identity-center/aws-cli-authorize.png)

Once you've approved the request, you can close the browser window, and back in the terminal, the AWS CLI will then
try to configure a _profile_, which corresponds to being logged into a single AWS account (one of the ones within the
AWS organization that's part of the session) with a specific permission set. If you have access to multiple AWS accounts
or permissions sets, the AWS CLI will show you a drop-down where you can pick which account to authenticate to, and
then another drop-down where you can pick which permission set to use:

![Authorizing the AWS CLI](/assets/img/resources/authenticate-to-aws-with-iam-identity-center/aws-cli-pick-account.png)

If you only have access to a single AWS account and permission set, the AWS CLI will pick that one automatically. The
CLI will then prompt you for information to set up your profile:

```console
CLI default client Region [None]:
CLI default output format [None]:
CLI profile name [AdministratorAccess-111111111111]: personal-mgmt-admin
```

Here is the information the CLI prompts you for:

* **CLI default client Region**. Hit Enter to leave this value at its default (None).
* **CLI default output format**. Hit Enter to leave this value at its default (None).
* **CLI profile name**. This is the name to use for the profile. Since this corresponds to a single permission set in
  a single account in a single AWS organization, you may want to use a name format such as 
  `<ORG>-<ACCOUNT>-<PERMISSIONS>`, where `ORG` is the name of the organization, `ACCOUNT` is the name of the account,
  and `PERMISSIONS` represents the permissions you'll have in that account. For example, you might name the profile
  `personal-mgmt-admin` to indicate that this profile gives you admin permissions in the management account of your 
  personal AWS organization.

Once you enter all this information, your session and profile will be created, and you'll be logged into that profile.
You can now use this profile with the AWS CLI and any other CLI tools that need to authenticate to AWS by passing in
the profile name via the `--profile` flag. For example, you can check your authentication with the AWS CLI as follows:

```console
$ aws sts get-caller-identity --profile=personal-mgmt-admin
```

Alternatively, as not all tools support the `--profile` flag, you can set the `AWS_PROFILE` environment variable:

```console
$ export AWS_PROFILE=personal-mgmt-admin
```

Now the AWS CLI will automatically use that profile without additional flags:


```console
$ aws sts get-caller-identity
```

Moreover, any CLI tool that authenticates to AWS, such as [OpenTofu](https://opentofu.org/), will automatically use that 
profile, too:

```console
$ tofu apply
```

If your session expires, you can log in again using the `aws sso login` command:

```console
$ aws sso login --profile=personal-mgmt-admin
```

And if you need to add other profiles in the future (to access other accounts or permissions sets), you can run the
`aws configure sso` command again, or add profiles by hand to your AWS CLI configuration file, which lives in 
`~/.aws/config` on Linux or macOS, or at `C:\Users\USERNAME\.aws\config` on Windows.

## Conclusion

You now know the basics of setting up IAM Identity Center and using it to authenticate to your AWS accounts, both
in the web browser and on the command line. To go further, here are a few exercises you can try at home to get your 
hands dirty:

* Create [custom permission sets](https://docs.aws.amazon.com/singlesignon/latest/userguide/permissionsetcustom.html)
  so you can grant users least-privilege access to your accounts.
* Set up SSO with your existing identity provider, such as 
  [Active Directory](https://docs.aws.amazon.com/singlesignon/latest/userguide/gs-ad.html), 
  [Google Workspace](https://docs.aws.amazon.com/singlesignon/latest/userguide/gs-gwp.html),
  [Okta](https://docs.aws.amazon.com/singlesignon/latest/userguide/gs-okta.html),
  [JumpCloud](https://docs.aws.amazon.com/singlesignon/latest/userguide/jumpcloud-idp.html),
  [OneLogin](https://docs.aws.amazon.com/singlesignon/latest/userguide/onelogin-idp.html), or
  [Ping](https://docs.aws.amazon.com/singlesignon/latest/userguide/pingidentity.html).
* Secure IAM Identity Center by setting up 
  [logging](https://docs.aws.amazon.com/singlesignon/latest/userguide/security-logging-and-monitoring.html) and
  [compliance validation](https://docs.aws.amazon.com/singlesignon/latest/userguide/sso-compliance.html).

To learn how to integrate authentication and SSO into your software delivery process,
check out _[Fundamentals of DevOps and Software Delivery]({{ site.url }})_!
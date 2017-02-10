# Ansible Playbook for Serverless Framework

Example [Ansible](https://github.com/ansible/ansible) playbook for deploying [Serverless](https://github.com/serverless/serverless) service.

Benefits on using this approach:

* The service can be tested in the build flow
* Stack deployment is faster when the service is already compiled and test are runned
* Same tested package is used in all the stages

For small scale serverless projects there is also a lite version that builds and deploys Serverless service [serverless-deployment-ansible-lite](https://github.com/SC5/serverless-deployment-ansible-lite).

**Contents**

[Project Structure](#project-structure)

[Setup Local Environment](#setup-local-environment)

[Setup Jenkins](#setup-jenkins)

[Deployment Flow](#deployment-flow)

[Build](#build)

[Deployment](#deployment)


## Project Structure

* `group_vars` default variables
* `inventories` inventory files and variables for environments (development, production, etc.)
* `roles`
  * `infra` role for infrastructure, vpc, database etc.
  * `service` role for Serverless service
* `scripts` scripts that helps deployment

## Setup Local Environment

If you are deploying from your local environment, [Docker](https://docs.docker.com/engine/installation/) is required for deploying the playbook or alternatively Ansible and all the dependencies defined in Dockerfile installed in you environment.

## Setup Jenkins

When using jenkins for deployment, easiest way is to setup Jenkins into EC2 instance running in your AWS account. Here is quick and dirty instructions how to do that [Jenkins setup instructions](https://github.com/laardee/jenkins-installation)

In addition to suggested plugins, install following plugins also:

* Pipeline: AWS Steps
* Version Number Plug-In

## Deployment flow

![deployment flow](https://raw.githubusercontent.com/SC5/serverless-deployment-ansible/flow.png)

1. Create artifact from the Serverless service that contains parameterized CloudFormation Jinja2 template and functions package
2. Upload artifact to S3 (or Artifactory or other file system).
3. Download artifact with Ansible
4. Extract and create environment specific CloudFormation templates
5. Deploy stack to AWS

## Build

Create S3 bucket for artifacts using AWS Console or aws-cli.

```Bash
aws s3api create-bucket --bucket my-artifacts-bucket --region us-east-1
```

### Local environment

[serverless-deployment-example-service](https://github.com/SC5/serverless-deployment-example-service) has ready made setup for [serverless-ansible-build-plugin](https://github.com/laardee/serverless-ansible-build-plugin) that helps the artifact creation process.

In the serverless-deployment-example-service, scripts directory there is `create-artifact.sh` that builds service and creates artifact with recommended filename. 

Executing `create-artifact.sh` with param `-p` creates tar package, `-s` parameter is mandatory and needs to match service name.

Following snippet will create package named e.g. `example-service-1.20170206.1-799dcd4.tar.gz`. Where

* `example-service` is service name (set with `-s`)
* `1` is version for service (set with `-v`, optional, defaults to 1)
* `20170206` is build date
* `1` is number of the build in build date (set with `-b`, optional, defaults to 1)
* `799dcd4` is short hash from git

```Bash
./scripts/create-artifact.sh -p -s example-service
```

The `1.20170206.1-799dcd4` part is the `service_version` what is used later in Ansible vars.

Then copy the artifact to you artifact S3 bucket.

### Jenkins

Following pipeline script will

1. checkouts the service from repository
2. creates version tag
3. builds service
4. uploads artifact to S3 bucket

```Groovy
MAJOR_VERSION = "1"
ARTIFACTS_BUCKET = "my-artifacts-bucket"
SERVICE = "example-service"
node {
    stage('Checkout service repo') {
        dir('project') {
            git 'https://github.com/SC5/serverless-deployment-example-service.git'
        }
    }
    
    stage('Set version') {
        dir('project') {
            gitCommitShort = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
            version = VersionNumber(projectStartDate: '2016-10-01', skipFailedBuilds: true, versionNumberString: '${BUILD_DATE_FORMATTED, "yyyyMMdd"}.${BUILDS_TODAY, X}-${gitCommitShort}', versionPrefix: "${MAJOR_VERSION}.")
            currentVersion = "${version}" + "${gitCommitShort}"
            
        }
    }
    
    stage('Build') {
        dir('project') {
            withEnv(["VERSION=${currentVersion}"]) {
                sh "./scripts/create-artifact.sh -s ${SERVICE}"
            }
        }
    }
    
    stage("Copy Artifact to S3") {
        dir('artifacts') {
            withEnv(["VERSION=${currentVersion}"]) {
                sh "truncate latest --size 0 && echo ${currentVersion} > latest"
                sh "tar -zcf ${SERVICE}-${VERSION}.tar.gz -C ../project/.ansible ${SERVICE}.zip ${SERVICE}.json.j2"
                withAWS {
                    s3Upload(file:"${SERVICE}-${VERSION}.tar.gz", bucket:"${ARTIFACTS_BUCKET}", path:"${SERVICE}/${SERVICE}-${VERSION}.tar.gz")
                    s3Upload(file:"latest", bucket:"${ARTIFACTS_BUCKET}", path:"${SERVICE}/latest")
                }
            }
        }
    }
}
```

## Deployment

Define artifacts S3 bucket to `artifacts_bucket` variable in `group_vars/aws/vars.yml`, so that Ansible knows where to download artifacts.

### Local environment

First define the service name to `roles/service/tasks/main.yml`

```Yaml
- set_fact:
    service_name: example-service
```

When deploying from local environment AWS secrets needs to be passed to deployment container, for that e.g. `.deploy.sh` script in the project root with contents of

```Bash
#!/usr/bin/env bash

export AWS_ACCESS_KEY=my-access-key
export AWS_SECRET_KEY=my-secret-key

./scripts/deploy-local.sh

```

might ease up the deployment flow.

1. Build Dockerfile with `./scripts/build-docker.sh`
2. Run `./.deploy.sh`

To deploy certain version of the Serverless service, use environmental variable `SERVICE_VERSION`. If version is not defined it fallbacks to latest version.

### Jenkins

When using Jenkins on AWS EC2, the role of the instance needs to have permissions to deploy CloudFormation stacks, create S3 buckets, IAM Roles, Lambda and other services that are used in Serverless service.

Following pipeline script will

1. checkout this repository
2. build docker image for deployment
3. deploy stacks to AWS

```Groovy
node {
    stage('Checkout repository') {
        git 'https://github.com/SC5/serverless-deployment-ansible.git'
    }
    stage('Build Docker image') {
       sh "./scripts/build-docker.sh"
    }
    stage('Deploy') {
        sh './scripts/deploy-development.sh'
    }
}
```

The deploy script `./scripts/deploy-development.sh` in deployment repository executes Ansible in docker container.

```Bash
#!/usr/bin/env bash

docker run -v $(pwd):/src -w /src serverless-deployment /bin/bash -c "\
export SERVICE_VERSION=$SERVICE_VERSION && \
ansible-playbook -vvvv --inventory-file inventories/development/inventory site.yml"

[[ $? -eq 0 ]] || { echo "Deployment failed!" ; exit 1; }
```

To deploy certain version of the Serverless service, use environmental variable `SERVICE_VERSION`, that can be defined in Jenkins parameterized job. If version is not defined it fallbacks to latest version.

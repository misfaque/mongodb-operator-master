# mongodb-operator (cluster admin actions)

## Demo

Please view the below recording for a demonstration of the steps documented in this README.

[Watch the QuickTime (.mov) recording (8 mins)](https://drive.google.com/a/broadcom.com/file/d/1CzAgnXLWJMjyG2XQwOKdd_sV6Tymna7o/view?usp=sharing)

## Overview

This README provides instructions for a cluster aministrator to download any relevant images used by the operator (e.g. from Docker Hub), rename/retag and push them to artifactory. Once the images have been pushed, install the [Percona](https://github.com/percona/percona-server-mongodb-operator) Server MongoDB Cluster Operator Custom Resource Definitions (CRDs) to a GKE Kubernetes cluster.

Once the CRDs are installed and the images are available in Artifactory, the `push` entrypoint is used to make the images available in a `mongod-operator` Google Container Registry in the same Google Project that the GKE Kubernetes cluster is running in. The `push` entrypoint creates a `mongodb-operator` namespace and creates a serviceaccount in that `mongodb-operator` namespace named `mongodb-operator` which is subsequently used to deploy the operator and related yaml operations (e.g. backup, restore) to other namespaces where product teams want to use the MongoDB Operator functionality.

Add a clusterrole and a clusterrolebinding to a serviceaccount named `mongodb-operator` that will allow that serviceaccount to be used to deploy and manage the operator in the product teams namespaces.

Once the images are pushed,the CRDs applied and the clusterrole/clusterrolebinding created by a cluster administrator, a helm chart is available to install the (optional) PMM Server monitoring capability and a helm chart is available to install, upgrade, backup and restore a Percona Server MongoDB cluster instance(s). This could be usd by either a SaaS Ops managed service team or by any product team to perform their own self-service. Both of these charts can be triggered via the SaaS Ops CD Pipeline and example branches in this repo have been provided with detailed READMEs.

Also, please read the [Percona documentation](https://www.percona.com/doc/kubernetes-operator-for-psmongodb/index.html) to gain an understanding of the features of the Operator.

## Prerequisites

In the [deploy-info.yml](./deploy-info.yml), the following team needs to be defined:

```
team:
  name: "mongodb-operator"
  token: "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXXXXXX"
```

The token value for the environment is created and managed by the SaaS Ops team. Raise a SaaS ticket if you need to get the token for a specific environment.

## Getting the Percona Operator images

Percona provide the images used by the MongoDB Operator CRDs on [Docker Hub](https://hub.docker.com/u/percona). Instead of pulling the images directly from Docker Hub, we want to download any new versions of the images used by the operator, tag them appropriately, scan and push them to a defined location in the Artifactory docker registry and deploy them via the CD pipeline. There are two images required by the Percona MongoDB Operator CRDs:

* percona-server-mongodb-operator - see https://hub.docker.com/r/percona/percona-server-mongodb-operator
* pmm-server - https://hub.docker.com/r/percona/pmm-server

| Percona Image Tag on Docker Hub                | Broadcom Tagged and Pushed Version In Artifactory |
| :----------------------------------------------| :-------------------------------------------------|
| percona-server-mongodb-operator:1.3.0          | percona-server-mongodb-operator:1.3.0             |
| percona-server-mongodb-operator:1.3.0-backup   | percona-server-mongodb-operator-backup:1.3.0      |
| percona-server-mongodb-operator:1.3.0-mongd4.0 | percona-server-mongodb-mongd40:1.3.0              |
| percona-server-mongodb-operator:1.3.0-pmm      | percona-server-mongodb-operator-pmm:1.3.0         |
| pmm-server:2.2.2                               | pmm-server:2.2.2                                  |

An example of pulling, tagging an image from docker hub and pushing the retagged image to artifactory is shown below. Firstly, ensure you are logged into docker hub and artifactory registries respectively:

```
docker pull percona/percona-server-mongodb-operator:1.3.0-backup
docker tag percona/percona-server-mongodb-operator1.3.0-backup docker-release-local.artifactory-lvn.broadcom.net/saas-devops/mongodb-operator/percona-server-mongodb-operator-backup:1.3.0
docker push docker-release-local.artifactory-lvn.broadcom.net/saas-devops/mongodb-operator/percona-server-mongodb-operator-backup:1.3.0
```

Download any newer image(s) from [Docker Hub](https://hub.docker.com/u/percona), tag them appropriately and push them to [Artifactory](https://artifactory-lvn.broadcom.net/artifactory/docker-release-local/saas-devops/mongodb-operator).

The core functionality that deploys and manages a Percona MongoDB cluster is provided in the mongodb-operator image, built from the Dockerfile in this master branch. Use the `build.sh` and `push.sh` scripts to push any later versions to artifactory.

## Pushing Images from Artifactory to Google Container Registry

In your own gitops repo, create a new branch - e.g. pipeline_mongod-operator-master - and copy the [Jenkinsfile](./Jenkinsfile), [deploy-info.yml](./deploy-info.yml), [crd.yaml](./crd.yaml) and [push-images.yml](./push-images.yml) to it from this branch. Ensure your copied `Jenkinsfile` is triggering the expected SaaS Ops CD Pipeline code (dev for dockcpdev repos and master for dockcp repos) and edit your copied `deploy-info.yml` to ensure it is deploying to the expected namespace (defined by the `project_name` setting in `deploy-info.yml` which for this use case should be set to `mongodb-operator`) and GKE cluster (defined by the `kubernetes.env.name` setting in `deploy-info.yml`).

As of March 2020, the images that are available to push to a `mongodb-operator` namespace in the Google Container Registry location used by the GKE environment defined in the [deploy-info.yml](./deploy-info.yml) are at the `docker-release-local.artifactory-lvn.broadcom.net/saas-devops/mongodb-operator/` location in Artifactory as follows:

![screenshot1](images/screenshot1.png)

After the Jenkins server has completed the `push` job, the images will be available in the Google Project Container Registry at the following location:

`gcr.io/<gcp-project-id>/<env-name>/mongodb-operator`

where:

* `gcp-project-id` is the Project ID og the Google Project you are deploying to
* `env-name` is the `kubernetes.env.name` value in [deploy-info.yml](./deploy-info.yml) that identifies your GKE cluster

For example, if you look at your Google Project Container Registry in the Google Console, you should see see the following:

![screenshot2](images/screenshot2.png)

## Adding the Cluster Operator Custom Resource Definitions (CRDs)

1. Ensure you can access the Kubernetes cluster as a user with clusteradmin level privileges. See [Configure GKE cluster access for kubectl](https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl).
2. Clone this repository and `cd` into it.
3. Add the Cluster Operator Custom Resource Definitions (CRD)s. This is a one time action:
```
kubectl apply -f crd.yaml
```
4. Validate the Cluster Operator CRDs have been installed
```
kubectl get crd | grep percona
```
You should see the following Custom Resource Definitions in the output:
```
NAME
perconaservermongodbs.psmdb.percona.com 
perconaservermongodbbackups.psmdb.percona.com 
perconaservermongodbrestores.psmdb.percona.com 
```
5. The mongodb-operator image uses a serviceaccount named `mongodb-operator` in the `mongodb-operator` namespace to deploy and manage a Percona MongoDB cluster in any other namespace via the CD pipeline. Thus, we need to provide this serviceaccount the necessary permissions applying the following clusterroles.
```
kubectl create clusterrole psmdb-admin --verb="*" --resource=perconaservermongodbs.psmdb.percona.com,perconaservermongodbs.psmdb.percona.com/status,perconaservermongodbbackups.psmdb.percona.com,perconaservermongodbbackups.psmdb.percona.com/status,perconaservermongodbrestores.psmdb.percona.com,perconaservermongodbrestores.psmdb.percona.com/status
kubectl create clusterrolebinding psmdb-admin --clusterrole psmdb-admin --serviceaccount mongodb-operator:mongodb-operator
```
6. Validate that you see the psmdb-admin clusterrole:
```
kubectl get clusterroles | grep psmdb
```
You should see the following cluster roles in the output:
```
NAME
psmdb-admin
```
7. Validate that the `mongodb-operator` serviceaccount having access to the psmdb-admin clusterrole:
```
kubectl get clusterrolebindings | grep psmdb
NAME           ROLE            USERS    GROUPS    SERVICE ACCOUNTS                                    SUBJECTS
psmdb-admin    /psmdb-admin                       mongodb-operator/mongodb-operator  
```

# How end users access and use the operator

Once the above has been performed by a cluster admin, the following two Helm charts are available to end users to deploy and manage the MongoDB operator in their namespace(s) via the CD pipeline. An end user in this context may be a SaaS OPs delivered managed service team who provision and manage MongoDB clusters as requested from product teams. Alternatively, an end user may be a product team themselves who want a self-service capability and they take ownership of ongoing support and maintenance of the deployed mongodb cluster.

# The pmm-server Helm Chart #

Percona provide a Grafana based UI to view time-based analysis metrics from a MongoDB cluster - see the [docs](https://www.percona.com/doc/percona-monitoring-and-management/index.html). A Helm chart is available to install via the CD Pipeline - see the [README.md](https://github.gwd.broadcom.net/dockcpdev/mongodb-operator/blob/pipeline_pmm-server/README.md). Install this to the same namespace where the `mongodb-operator` helm chart will deploy the MongoDB instance to (see below).

# The mongodb-operator Helm Chart 

Once the Cluster Operator is available in the Openshift cluster and the images pushed to the local registry, a Helm Chart that installs and manages a MongoDB Operator into any namespace via the CD Pipeline is available - see the [README.md](https://github.gwd.broadcom.net/dockcpdev/mongodb-operator/blob/pipeline_mongodb-operator/README.md). 

#!/bin/sh

trap revoke_service_account_tokens EXIT

operator_pod_running() {
    CHECK_OPERATOR_SLEEP=10
    CHECK_OPERATOR_RUNNING=1
    while [ ${CHECK_OPERATOR_RUNNING} -lt 30 ];
    do
        OPERATOR_RUNNING=`kubectl_token --namespace ${KUBERNETES_NAMESPACE} get pods | grep ${OPERATOR_POD}- | grep Running | wc -l`

        if [ "${OPERATOR_RUNNING}" == "1" ]
        then
            echo Found the running operator pod in ${KUBERNETES_NAMESPACE}
            return 0
        else
            echo Waiting for the running operator pod in ${KUBERNETES_NAMESPACE}
        fi

        # Wait before checking if the operator pod is running
        sleep ${CHECK_OPERATOR_SLEEP}
        ((CHECK_OPERATOR_RUNNING++))

        if [ "${CHECK_OPERATOR_RUNNING}" == "30" ]
        then
            echo Could not find the running operator pod in ${KUBERNETES_NAMESPACE}
            return 1
        fi
    done

    return 1
}

revoke_service_account_tokens() {
    kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} get secrets --namespace ${BASE_KUBERNETES_NAMESPACE} | grep ${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT}-token | awk '{print $1}' | xargs -I {} kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} delete secret {} --namespace ${BASE_KUBERNETES_NAMESPACE}
}

echo Processing ${OPERATOR_COMMAND} request at ${RUN_TIME}

# Authenticate to Kubernetes using provided kubeconfig and serviceaccount token
export KUBECONFIG=/kubeconfig/kubeconfig
alias kubectl_token="kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN}"

echo Testing connection to Kubernetes namespace
kubectl_token get namespace ${KUBERNETES_NAMESPACE}
# If kubectl test not successful, exit
if [ $? -ne 0 ];
then
    echo Could not validate that the Kubernetes namespace ${KUBERNETES_NAMESPACE} can be accessed. Exiting
    exit -1
fi

# Run the relevant Operator command
case "${OPERATOR_COMMAND}" in
'deploy-cluster')
    # Apply S3 Backup Credentials
    echo Applying backup-s3.yaml in ${KUBERNETES_NAMESPACE} namespace
    kubectl_token apply -f /operator/backup-s3.yaml
    sleep 10

    # Apply RBAC
    echo Applying rbac.yaml in ${KUBERNETES_NAMESPACE} namespace
    kubectl_token apply -f /operator/role.yaml
    # Note, the percona-server-mongodb-operator must already exist in the namespace
    kubectl_token apply -f /operator/role-binding.yaml
    sleep 10

    # Apply Operator
    echo Applying operator.yaml in ${KUBERNETES_NAMESPACE} namespace
    kubectl_token apply -f /operator/operator.yaml
    sleep 10

    # Apply Users
    echo Applying secrets.yaml in ${KUBERNETES_NAMESPACE} namespace
    kubectl_token apply -f /operator/secrets.yaml
    sleep 10

    # Apply SSL Certificates
    echo Applying ssl-secrets.yaml in ${KUBERNETES_NAMESPACE} namespace
    kubectl_token apply -f /operator/ssl-secrets.yaml
    kubectl_token apply -f /operator/ssl-internal-secrets.yaml
    sleep 10

    # Ensure operator pod is running before proceeding
    if ! operator_pod_running;
    then
	exit 1
    fi

    # Apply Cluster
    echo Applying cr.yaml in ${KUBERNETES_NAMESPACE} namespace
    kubectl_token apply -f /operator/cr.yaml
    sleep 10
;;
'backup-cluster')
    # Ensure operator pod is running before proceeding
    if ! operator_pod_running;
    then
	exit 1
    fi

    # Apply backup
    echo Applying backup.yaml in ${KUBERNETES_NAMESPACE} namespace
    kubectl_token apply -f /operator/backup.yaml
    sleep 10

;;
'restore-cluster')
    # Ensure operator pod is running before proceeding
    if ! operator_pod_running;
    then
	exit 1
    fi

    # Apply restore
    echo Applying restore.yaml in ${KUBERNETES_NAMESPACE} namespace
    kubectl_token apply -f /operator/restore.yaml
    sleep 10
;;
'delete-cluster')
    # Ensure operator pod is running before proceeding
    if ! operator_pod_running;
    then
	exit 1
    fi

    # Apply delete
    echo Deleting cr.yaml in ${KUBERNETES_NAMESPACE} namespace
    kubectl_token delete -f /operator/cr.yaml
    sleep 10
;;
'list-backups')
    # Ensure operator pod is running before proceeding
    if ! operator_pod_running;
    then
	exit 1
    fi

    # List clusters
    echo Listing mongodb clusters in ${KUBERNETES_NAMESPACE} namespace
    kubectl_token get psmdb --namespace ${KUBERNETES_NAMESPACE}

    # List backups
    echo Listing backups in ${KUBERNETES_NAMESPACE} namespace
    kubectl_token get psmdb-backup --namespace ${KUBERNETES_NAMESPACE}
;;
'delete-backup')
    # Ensure operator pod is running before proceeding
    if ! operator_pod_running;
    then
	exit 1
    fi

    # Delete backup
    echo Deleting backup ${BACKUP_NAME} in ${KUBERNETES_NAMESPACE} namespace
    kubectl_token delete psmdb-backup ${BACKUP_NAME} --namespace ${KUBERNETES_NAMESPACE}
;;
'update-cluster')
    # Ensure operator pod is running before proceeding
    if ! operator_pod_running;
    then
	exit 1
    fi

    # Patch the operator deployment with the desired Percona version
    echo Running the following command: kubectl patch deployment percona-server-mongodb-operator --namespace ${KUBERNETES_NAMESPACE} \
   -p '{"spec":{"template":{"spec":{"containers":[{"name":"percona-server-mongodb-operator","image":"'${OPERATOR_IMAGES}'/percona-server-mongodb-operator:'${PERCONA_OPERATOR_VERSION}'"}]}}}}'

    kubectl_token patch deployment percona-server-mongodb-operator --namespace ${KUBERNETES_NAMESPACE} \
   -p '{"spec":{"template":{"spec":{"containers":[{"name":"percona-server-mongodb-operator","image":"'${OPERATOR_IMAGES}'/percona-server-mongodb-operator:'${PERCONA_OPERATOR_VERSION}'"}]}}}}'

    # Patch the cluster to the desired Percona version. The update strategy of RollingUpdate should ensure pods are restarted
    echo Running the following command: kubectl patch pxc ${CLUSTER_NAME} --type=merge --namespace ${KUBERNETES_NAMESPACE} -p '{
   "metadata": {"annotations":{ "kubectl.kubernetes.io/last-applied-configuration": "{\"apiVersion\":\"pxc.percona.com/'${PERCONA_API_VERSION}'\"}" }},
   "spec": "replsets": "'${OPERATOR_IMAGES}'/percona-server-mongodb-operator-mongd40:'${PERCONA_OPERATOR_VERSION}'",
       "image": "'${OPERATOR_IMAGES}'/percona-server-mongodb-operator-mongd40:'${PERCONA_OPERATOR_VERSION}'",
       "backup": { "image": "'${OPERATOR_IMAGES}'/percona-xtradb-cluster-operator-backup:'${PERCONA_OPERATOR_VERSION}'" },
       "pmm": { "image": "'${OPERATOR_IMAGES}'/percona-xtradb-cluster-operator-pmm:'${PERCONA_OPERATOR_VERSION}'" }
   }}'

    kubectl_token patch pxc ${CLUSTER_NAME} --type=merge --namespace ${KUBERNETES_NAMESPACE} -p '{
   "metadata": {"annotations":{ "kubectl.kubernetes.io/last-applied-configuration": "{\"apiVersion\":\"pxc.percona.com/'${PERCONA_API_VERSION}'\"}" }},
   "spec": "replsets": "'${OPERATOR_IMAGES}'/percona-server-mongodb-operator-mongd40:'${PERCONA_OPERATOR_VERSION}'",
       "image": "'${OPERATOR_IMAGES}'/percona-server-mongodb-operator-mongd40:'${PERCONA_OPERATOR_VERSION}'",
       "backup": { "image": "'${OPERATOR_IMAGES}'/percona-server-mongodb-operator-backup:'${PERCONA_OPERATOR_VERSION}'" },
       "pmm":  { "image": "'${OPERATOR_IMAGES}'/percona-server-mongodb-operator-pmm:'${PERCONA_OPERATOR_VERSION}'" }
   }}'

;;
*)
    echo "Sorry, we can't process ${OPERATOR_COMMAND} request"
;;
esac

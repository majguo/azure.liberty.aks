#!/bin/bash

#      Copyright (c) Microsoft Corporation.
# 
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
# 
#           http://www.apache.org/licenses/LICENSE-2.0
# 
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.

wait_deployment_complete() {
    deploymentName=$1
    namespaceName=$2
    logFile=$3

    kubectl get deployment ${deploymentName} -n ${namespaceName}
    while [ $? -ne 0 ]
    do
        echo "Wait until the deployment ${deploymentName} created..." >> $logFile
        sleep 5
        kubectl get deployment ${deploymentName} -n ${namespaceName}
    done
    read -r -a replicas <<< `kubectl get deployment ${deploymentName} -n ${namespaceName} -o=jsonpath='{.spec.replicas}{" "}{.status.readyReplicas}{" "}{.status.availableReplicas}{" "}{.status.updatedReplicas}{"\n"}'`
    while [[ ${#replicas[@]} -ne 4 || ${replicas[0]} != ${replicas[1]} || ${replicas[1]} != ${replicas[2]} || ${replicas[2]} != ${replicas[3]} ]]
    do
        # Delete pods in ImagePullBackOff status
        podIds=`kubectl get pod -n ${namespaceName} | grep ImagePullBackOff | awk '{print $1}'`
        read -r -a podIds <<< `echo $podIds`
        for podId in "${podIds[@]}"
        do
            echo "Delete pod ${podId} in ImagePullBackOff status" >> $logFile
            kubectl delete pod ${podId} -n ${namespaceName}
        done

        sleep 5
        echo "Wait until the deployment ${deploymentName} completes..." >> $logFile
        read -r -a replicas <<< `kubectl get deployment ${deploymentName} -n ${namespaceName} -o=jsonpath='{.spec.replicas}{" "}{.status.readyReplicas}{" "}{.status.availableReplicas}{" "}{.status.updatedReplicas}{"\n"}'`
    done
    echo "Deployment ${deploymentName} completed." >> $logFile
}

clusterRGName=$1
clusterName=$2
acrName=$3
export Project_Name=${4}
logFile=deployment.log

# Install utilities
apk update
apk add gettext
apk add docker-cli

# Install `kubectl` and connect to the AKS cluster
az aks install-cli
az aks get-credentials -g $clusterRGName -n $clusterName --overwrite-existing >> $logFile

# Install Open Liberty Operator V0.7.1
OPERATOR_VERSION=0.7.1
OPERATOR_NAMESPACE=default
WATCH_NAMESPACE='""'
kubectl apply -f https://raw.githubusercontent.com/OpenLiberty/open-liberty-operator/master/deploy/releases/${OPERATOR_VERSION}/openliberty-app-crd.yaml
curl -L https://raw.githubusercontent.com/OpenLiberty/open-liberty-operator/master/deploy/releases/${OPERATOR_VERSION}/openliberty-app-cluster-rbac.yaml \
    | sed -e "s/OPEN_LIBERTY_OPERATOR_NAMESPACE/${OPERATOR_NAMESPACE}/" \
    | kubectl apply -f - >> $logFile
curl -L https://raw.githubusercontent.com/OpenLiberty/open-liberty-operator/master/deploy/releases/${OPERATOR_VERSION}/openliberty-app-operator.yaml \
    | sed -e "s/OPEN_LIBERTY_WATCH_NAMESPACE/${WATCH_NAMESPACE}/" \
    | kubectl apply -n ${OPERATOR_NAMESPACE} -f - >> $logFile
wait_deployment_complete open-liberty-operator $OPERATOR_NAMESPACE ${logFile}

# Create project namespace
kubectl create namespace ${Project_Name} >> $logFile

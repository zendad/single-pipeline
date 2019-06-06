#!/bin/bash

WORKSPACE=/home/dereck2

MODULESREPO=git@github.com:zendad/single-pipeline.git
HELMCHARTREPO=git@github.com:zendad/modules-chart.git

#clone directory
CLONEDIR=$WORKSPACE/module-pipeline

#app work directory
APPWORKDIR=$CLONEDIR/moduleapps

#docker directory
DOCKERDIR=$APPWORKDIR/docker

#Deployment status
DEPLOYMENTSTATUS=$CLONEDIR/deploymentstatus.txt

#docker registry
GCP_PROJECT_ID=modules

#clone modules repo
echo "cloning modules repo"
git clone $MODULESREPO $CLONEDIR

echo "cloning docker & helm modules repo"
git clone $HELMCHARTREPO $APPWORKDIR

#using sonaqube to run code quality checks
echo "install modules needed for sonarqube"
pip3.6 install nose coverage nosexcover pylint

echo "check if there are modules to deploy"
cd $CLONEDIR
git log --name-status -1 | tail -n +7 |  cut -f1 -d'/' | awk '{print $2}' | grep module | grep -v base > $CLONEDIR/modules.txt
if [ -s  $CLONEDIR/modules.txt ]
then
    echo "New changes deployed to modules,preparing deployment"
    cp -pr module_base main.py setup.py requirements.txt $DOCKERDIR
    for module in $(git log --name-status -1 | tail -n +7 |  cut -f1 -d'/' | awk '{print $2}' | grep module | grep -v 'base\|app')
    do
      cd  $CLONEDIR
      MODULE_NUMBER=$(echo $module | tr -dc '0-9')
      IMAGE_NAME=$(echo $module | cut -c1-6)-$MODULE_NUMBER
      TAG=$(git rev-parse --short HEAD)
      IMAGE=gcr.io/$GCP_PROJECT_ID/$IMAGE_NAME
      
      echo "List of changes to $module" >> $DEPLOYMENTSTATUS
      git log --name-status -1 | grep $module >> $DEPLOYMENTSTATUS
      
      #run code quality checks on module
      echo "running code quality checks on $module"
      nosetests --with-coverage --cover-package=$module --cover-branches --cover-xml
      sonar-runner
      
      echo "Build Docker image for module $module"
      #prepare module for docker build
      cp -pr $module $DOCKERDIR
      
      #build,tag and push docker image to registry
      cd $DOCKERDIR
      docker build -t $IMAGE_NAME:$TAG .
      docker tag $IMAGE_NAME:$TAG $IMAGE:$TAG
      gcloud auth configure-docker
      gcloud docker -- push $IMAGE:$TAG
      
      
      echo "Deploying module $module to kubernetes"
      #prepare helm package add module number,tag and registry details
      cd  $CLONEDIR
     
      cp -pr $APPWORKDIR/charts $APPWORKDIR/$module
      sed -i "s#repository:#repository: $IMAGE#g" $APPWORKDIR/$module/values.yaml
      sed -i "s/tag:/tag: $TAG/g" $APPWORKDIR/$module/values.yaml
      sed -i "s/moduleNumber:/moduleNumber: $MODULE_NUMBER/g" $APPWORKDIR/$module/values.yaml
      sed -i "s/name:/name: $IMAGE_NAME/g" $APPWORKDIR/$module/values.yaml
      
      #update chart version
      sed -i "s/name:/name: $module/g" $APPWORKDIR/$module/Chart.yaml
      sed -i "s/version:/version: $(git rev-list --count HEAD).0.0/g" $APPWORKDIR/$module/Chart.yaml
      echo "verify helm charts before deployment"
      cd $APPWORKDIR/$module
      helm lint .
      #Verify  status and email adminuser
      if [ $? -eq 0 ]; 
        then
            echo "helm chart is valid, installing $module" >> $DEPLOYMENTSTATUS
            helm upgrade -i $IMAGE_NAME . >> $DEPLOYMENTSTATUS
            echo "send email to admin on deployment status"
            mail -s "$module Deployed" $adminuser < $DEPLOYMENTSTATUS
      else
            echo "$module could not be deployed" >> $DEPLOYMENTSTATUS
            mail -s "$module deployment failed" $adminuser < $DEPLOYMENTSTATUS
      fi
      echo "$module deployment is done, cleaning up"
      rm -rf $DOCKERDIR/$module
      rm -rf $DEPLOYMENTSTATUS
    done
else
    echo "no modules to deploy exiting"
    exit 1
fi

#Deployments done cleaning up
docker rmi $(docker images -a -q) -f
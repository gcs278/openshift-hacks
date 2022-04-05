oc get pods &> /dev/null
if [ $? -ne 0 ]; then
  echo "ERROR: Something went wrong with getting image"
  exit 1
fi
image=$(oc get -n openshift-ingress deployment router-default  -o json | jq -r .spec.template.spec.containers[0].image)
if [[ $? -ne 0 ]]; then
  echo "ERROR: Something went wrong with getting image"
  exit 1
fi
podman pull --authfile ~/.secrets/pull-secret.txt $image
podman create --name=test $image
podman cp openshift-router test:/usr/bin/
new_image="quay.io/gspence/openshift-router"
podman commit test $new_image
podman push $new_image

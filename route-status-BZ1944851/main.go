package main

import (
	"fmt"
	v14 "github.com/openshift/api/operator/v1"
	v16 "github.com/openshift/api/operatoringress/v1"
	operatorcontroller "github.com/openshift/cluster-ingress-operator/pkg/operator/controller"
	v15 "k8s.io/api/apps/v1"
	v1 "k8s.io/api/core/v1"
	v13 "k8s.io/api/networking/v1"
	rbacv1 "k8s.io/api/rbac/v1"
	v12 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/manager/signals"
	"time"

	"context"

	routev1 "github.com/openshift/api/route/v1"
	operatorclient "github.com/openshift/cluster-ingress-operator/pkg/operator/client"
	operatorconfig "github.com/openshift/cluster-ingress-operator/pkg/operator/config"
	"k8s.io/client-go/rest"
	"sigs.k8s.io/controller-runtime/pkg/cache"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/config"
	"sigs.k8s.io/controller-runtime/pkg/manager"
)

func main() {
	kubeConfig, err := config.GetConfig()
	if err != nil {
		fmt.Println("couldn't get kubeconfig")
		return
	}
	operatorConfig := operatorconfig.Config{
		OperatorReleaseVersion: "4.10.5",
		Namespace:              "openshift-ingress-operator",
		IngressControllerImage: "quay.io/gspence/ingress-operator:router-status3",
		CanaryImage:            "quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:fab573b688254438cb67525cef636f480d9f2cc712d57079b85221272ee4c939",
	}

	scheme := operatorclient.GetScheme()
	// Set up an operator manager for the operator namespace.
	mgr, err := manager.New(kubeConfig, manager.Options{
		Namespace: operatorConfig.Namespace,
		Scheme:    scheme,
		NewCache: cache.MultiNamespacedCacheBuilder([]string{
			operatorConfig.Namespace,
			operatorcontroller.GlobalUserSpecifiedConfigNamespace,
			operatorcontroller.DefaultOperandNamespace,
			operatorcontroller.DefaultCanaryNamespace,
			operatorcontroller.GlobalMachineSpecifiedConfigNamespace,
			//"",
			operatorcontroller.SourceConfigMapNamespace,
		}),
		// Use a non-caching client everywhere. The default split client does not
		// promise to invalidate the cache during writes (nor does it promise
		// sequential create/get coherence), and we have code which (probably
		// incorrectly) assumes a get immediately following a create/update will
		// return the updated resource. All client consumers will need audited to
		// ensure they are tolerant of stale data (or we need a cache or client that
		// makes stronger coherence guarantees).
		NewClient: func(_ cache.Cache, config *rest.Config, options client.Options, uncachedObjects ...client.Object) (client.Client, error) {
			return client.New(config, options)
		},
	})
	// Set up the channels for the watcher, operator, and metrics using
	// the context provided from the controller runtime.
	signal, cancel := context.WithCancel(signals.SetupSignalHandler())
	defer cancel()

	errChan := make(chan error)
	go func() {
		errChan <- mgr.Start(signal)
	}()
	time.Sleep(5 * time.Second)
	mgr.GetCache().WaitForCacheSync(signal)
	client := mgr.GetCache()
	//mgr.Start(context.TODO())

	println("Routes:")
	routeObjectMetas := []v12.ObjectMeta{}
	routeList := &routev1.RouteList{}
	if err := client.List(context.TODO(), routeList); err != nil {
		println("ERROR LISTING ROUTES")
		fmt.Printf("%w", err)
		return
	}
	for _, i := range routeList.Items {
		routeObjectMetas = append(routeObjectMetas, i.ObjectMeta)
		println(i.Name)
	}
	findDuplicates(routeObjectMetas)
	println("---------------------")

	println("Pods:")
	podList := &v1.PodList{}
	podObjectMetas := []v12.ObjectMeta{}
	if err := client.List(context.TODO(), podList); err != nil {
		println("ERROR LISTING PODS")
		fmt.Printf("%w", err)
		return
	}
	for _, i := range podList.Items {
		podObjectMetas = append(podObjectMetas, i.ObjectMeta)
		//println(i.Name)
	}
	findDuplicates(podObjectMetas)
	println("---------------------")

	println("Services:")
	serviceList := &v1.ServiceList{}
	serviceObjectMetas := []v12.ObjectMeta{}
	if err := client.List(context.TODO(), serviceList); err != nil {
		println("ERROR LISTING Services")
		fmt.Printf("%w", err)
		return
	}
	for _, i := range serviceList.Items {
		serviceObjectMetas = append(serviceObjectMetas, i.ObjectMeta)
		//println(i.Name)
	}
	findDuplicates(serviceObjectMetas)
	println("---------------------")

	println("Nodes:")
	nodeObjectMetas := []v12.ObjectMeta{}
	nodeList := &v1.NodeList{}
	if err := client.List(context.TODO(), nodeList); err != nil {
		println("ERROR LISTING ROUTES")
		fmt.Printf("%w", err)
		return
	}
	for _, i := range nodeList.Items {
		nodeObjectMetas = append(nodeObjectMetas, i.ObjectMeta)
		println(i.Name)
	}
	findDuplicates(nodeObjectMetas)
	println("---------------------")

	println("Ingress Class:")
	ingressClassList := &v13.IngressClassList{}
	if err := client.List(context.TODO(), ingressClassList); err != nil {
		println("ERROR LISTING Ingress Class")
		fmt.Printf("%w", err)
		return
	}
	for _, i := range ingressClassList.Items {
		//nodeObjectMetas = append(nodeObjectMetas, i.ObjectMeta)
		println(i.Name)
	}
	//findDuplicates(nodeObjectMetas)
	println("---------------------")

	println("Config Maps:")
	configMapList := &v1.ConfigMapList{}
	configMapObjectMetas := []v12.ObjectMeta{}
	if err := client.List(context.TODO(), configMapList); err != nil {
		println("ERROR LISTING configmap")
		fmt.Printf("%w", err)
		return
	}
	for _, i := range configMapList.Items {
		configMapObjectMetas = append(configMapObjectMetas, i.ObjectMeta)
		println(i.Name)
	}
	findDuplicates(configMapObjectMetas)
	println("---------------------")

	println("Ingress Controllers:")
	ingressControllerList := &v14.IngressControllerList{}
	icObjectMetas := []v12.ObjectMeta{}
	client.List(context.TODO(), ingressControllerList)
	for _, i := range ingressControllerList.Items {
		icObjectMetas = append(icObjectMetas, i.ObjectMeta)
		println(i.Name)
	}
	findDuplicates(icObjectMetas)
	println("---------------------")

	println("Deployments")
	deploymentList := &v15.DeploymentList{}
	deploymentObjectMetas := []v12.ObjectMeta{}
	client.List(context.TODO(), deploymentList)
	for _, i := range deploymentList.Items {
		deploymentObjectMetas = append(deploymentObjectMetas, i.ObjectMeta)
		println(i.Name)
	}
	findDuplicates(deploymentObjectMetas)
	println("---------------------")

	println("Role list")
	roleList := &rbacv1.RoleList{}
	roleObjectMetas := []v12.ObjectMeta{}
	client.List(context.TODO(), roleList)
	for _, i := range roleList.Items {
		roleObjectMetas = append(roleObjectMetas, i.ObjectMeta)
		println(i.Name)
	}
	findDuplicates(roleObjectMetas)
	println("---------------------")

	println("Role Binding list")
	roleBindingList := &rbacv1.RoleBindingList{}
	roleBindingObjectMetas := []v12.ObjectMeta{}
	client.List(context.TODO(), roleBindingList)
	for _, i := range roleBindingList.Items {
		roleBindingObjectMetas = append(roleBindingObjectMetas, i.ObjectMeta)
		println(i.Name)
	}
	findDuplicates(roleBindingObjectMetas)
	println("---------------------")

	println("DNS list")
	list := &v14.DNSList{}
	objectMetas := []v12.ObjectMeta{}
	client.List(context.TODO(), list)
	for _, i := range list.Items {
		objectMetas = append(objectMetas, i.ObjectMeta)
		println(i.Name)
	}
	findDuplicates(objectMetas)
	println("---------------------")

	println("DNS Record list")
	list2 := &v16.DNSRecordList{}
	objectMetas = []v12.ObjectMeta{}
	client.List(context.TODO(), list2)
	for _, i := range list2.Items {
		objectMetas = append(objectMetas, i.ObjectMeta)
		println(i.Name)
	}
	findDuplicates(objectMetas)
	println("---------------------")

	println("Secrets list")
	list3 := &v1.SecretList{}
	objectMetas = []v12.ObjectMeta{}
	client.List(context.TODO(), list3)
	for _, i := range list3.Items {
		objectMetas = append(objectMetas, i.ObjectMeta)
		println(i.Name)
	}
	findDuplicates(objectMetas)
	println("---------------------")

}

//func printAllObjects(objectList interface{}, name string) {
//	println("%s:", name)
//	objectMetas := []v12.ObjectMeta{}
//
//	for _, i := range objectList.Items {
//		objectMetas = append(objectMetas, i.ObjectMeta)
//		println(i.Name)
//	}
//	findDuplicates(objectMetas)
//	println("---------------------")
//}

func findDuplicates(meta []v12.ObjectMeta) {
	fmt.Printf("Items: %d\n", len(meta))
	allKeys := make(map[types.UID]bool)
	list := []types.UID{}
	for _, item := range meta {
		if _, value := allKeys[item.UID]; !value {
			allKeys[item.UID] = true
			list = append(list, item.UID)
		} else {
			fmt.Printf("DUPLICATE: %s:%s\n", item.Name, item.UID)
		}
	}
	return
}

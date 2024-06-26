# A Demo of SHA-1 Upgradeable=False IngressController in 4.15

<!-- @hook show_editor EDITOR -->
<!-- @start_livecast -->
---
<!-- @SHOW -->

## A Demo of SHA-1 Upgradeable=False IngressController in 4.15

Let's demo what happens when you have an IngressController with a
SHA-1 Default Certificate in 4.15.18+ clusters.

First, we will need to generate a SHA-1 certificate:

```bash
#@notypeout
openssl req -x509 -sha1 -newkey rsa:1024 -days 3650 -keyout certs/sha1CA.key -out certs/sha1CA.crt -addext "keyUsage=cRLSign, digitalSignature, keyCertSign" -addext "extendedKeyUsage=serverAuth,clientAuth" -nodes -subj '/C=US/ST=SC/L=Default City/O=Default Company Ltd/OU=Test CA/CN=www.exampleCA.com/emailAddress=example@example.com'
#@notypeout
openssl req -newkey rsa:1024 -nodes -keyout certs/sha1.key -out certs/sha1.csr -subj '/CN=www.example.com/ST=SC/C=US/emailAddress=example@example.com/O=Example/OU=Example'
#@notypeout
openssl x509 -req -days 3650 -sha1 -in certs/sha1.csr -CA certs/sha1CA.crt -CAcreateserial -CAkey certs/sha1CA.key -extensions ext -extfile <(echo $'[ext]\nbasicConstraints = CA:           FALSE\nsubjectKeyIdentifier = none\nauthorityKeyIdentifier = none\nextendedKeyUsage=serverAuth,clientAuth\nkeyUsage=nonRepudiation, digitalSignature, keyEncipherment') -out certs/sha1.crt
```

And just to be sure, let's prove it's a SHA-1 Cert:

```bash
openssl x509 -noout -text -in 'certs/sha1.crt' | grep -i sha1
```

Next, create an IngressController with this SHA-1 Default Cert:

```bash
oc delete secret -n openshift-ingress sha1-cert
oc create secret -n openshift-ingress tls sha1-cert --key=certs/sha1.key --cert=certs/sha1.crt

export TEST_DOMAIN="demo.$(oc get dnses cluster -o jsonpath={.spec.baseDomain})"
envsubst < ingresscontroller-sha1.yaml.tmpl > ingresscontroller-sha1.yaml

bat --paging never ingresscontroller-sha1.yaml

oc apply -f ingresscontroller-sha1.yaml
```

Let's examine the IngressController's status conditions:

```bash
oc get ingresscontroller -n openshift-ingress-operator -o yaml | bat --paging never --language yaml
```

Next, let's see what CVO is reporting as the upgradeable status:

```bash
oc adm upgrade
```

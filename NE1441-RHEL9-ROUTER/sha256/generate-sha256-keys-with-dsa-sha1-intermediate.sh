#!/bin/bash

# Generate DSA Parameters
openssl dsaparam -out dsaparam.pem 2048

# Generate DSA Private Key for CA
openssl gendsa -out exampleca.key dsaparam.pem

# Generate Self-Signed CA Certificate
openssl req -x509 -sha1 -days 3650 -key exampleca.key -out exampleca.crt \
-addext "keyUsage=cRLSign, digitalSignature, keyCertSign" \
-addext "extendedKeyUsage=serverAuth, clientAuth" \
-nodes -subj '/C=US/ST=SC/L=Default City/O=Default Company Ltd/OU=Test CA/CN=www.exampleca.com/emailAddress=example@example.com'

# Generate DSA Private Key for Intermediate CA
openssl gendsa -out example-inter.key dsaparam.pem

# Generate CSR for Intermediate CA
openssl req -new -key example-inter.key -out example-inter.csr \
-subj '/CN=www.exampleinter.com/ST=SC/C=US/emailAddress=example@example.com/O=Example/OU=Example'

openssl req -x509 -sha1 -days 3650 -in example-inter.csr -CA exampleca.crt -CAkey exampleca.key -out example-inter.crt -addext "keyUsage=cRLSign, digitalSignature, keyCertSign" -addext      "extendedKeyUsage=serverAuth, clientAuth" -nodes

openssl gendsa -out example.key dsaparam.pem
openssl req -new -key example.key -out example.csr -subj '/CN=www.example.com/ST=SC/C=US/emailAddress=example@example.com/O=Example/OU=Example'

openssl x509 -req -days 3650 -sha1 -in example.csr -CA example-inter.crt -CAkey example-inter.key -CAcreateserial -extensions ext -extfile <(echo $'[ext]\nbasicConstraints = CA:FALSE\nsubjectKeyIdentifier = hash\nauthorityKeyIdentifier = keyid,issuer\nextendedKeyUsage=serverAuth,clientAuth\nkeyUsage=nonRepudiation, digitalSignature, keyEncipherment') -out example.crt

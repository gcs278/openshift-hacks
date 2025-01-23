#!/bin/bash

openssl dsaparam -out dsaparam.pem 2048
openssl gendsa -out exampleca.key dsaparam.pem
openssl req -new -x509 -key exampleca.key -out exampleca.crt -days 365 -sha1 -subj '/C=US/ST=SC/L=Default City/O=Default Company Ltd/OU=Test CA/CN=www.exampleca.com/emailAddress=example@example.com'
openssl gendsa -out example.key dsaparam.pem
openssl req -new -key example.key -out example.csr -subj '/C=US/ST=SC/L=Default City/O=Default Company Ltd/OU=Test CA/CN=www.example.com/emailAddress=example@example.com'
openssl x509 -req -in example.csr -CA exampleca.crt -CAkey exampleca.key -CAcreateserial -out example.crt -days 365 -sha1
cat example.crt example.key > dsa_combo.pem

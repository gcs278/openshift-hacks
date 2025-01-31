#!/bin/bash

openssl req -x509 -newkey rsa:2048 -keyout example-selfsigned.key -out example-selfsigned.pem -md5 -days 3650 -nodes -subj "/C=US/ST=SC/L=Test/O=CompanyName/OU=CompanySectionName/CN=www.example.com"

#!/usr/bin/env python

from __future__ import print_function
from socket import *
import time

bind = '' #listen on any
port = 25050

serverSocket = socket(AF_INET, SOCK_DGRAM)
serverSocket.bind((bind, port))

print("Started udp server on port", port)

while True:
    message, address = serverSocket.recvfrom(2048)
    #time.sleep(1)
    #print(".", end='', flush=True)
    serverSocket.sendto(message, address)

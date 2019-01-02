#!/usr/bin/python3

import requests

from threading import Thread

url = "http://cary-k8s:80/spring-ws-service"

def make_request(n):
	""" Make requests in sequence n times"""
	for x in range(n):
		r = requests.get(url, verify=False)
		print(r.text)

nthreads = 500
threads = []

for i in range(nthreads):
	t = Thread(target=make_request, args=(500,))
	threads.append(t)

# start the threads
[ t.start() for t in threads ]
# wait for the threads to finish
[ t.join() for t in threads ]
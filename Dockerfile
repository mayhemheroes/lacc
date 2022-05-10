# Build Stage
FROM --platform=linux/amd64 ubuntu:20.04 as builder
RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install  -y vim less man wget tar git gzip unzip make cmake software-properties-common curl


RUN git clone https://github.com/larmel/lacc.git
WORKDIR /lacc
RUN ./configure
RUN make



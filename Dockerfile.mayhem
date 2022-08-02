# Build Stage
FROM --platform=linux/amd64 ubuntu:20.04 as builder
RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y make gcc

ADD . /lacc
WORKDIR /lacc
RUN ./configure
RUN make

RUN mkdir -p /deps
RUN ldd /lacc/bin/lacc | tr -s '[:blank:]' '\n' | grep '^/' | xargs -I % sh -c 'cp % /deps;'

FROM ubuntu:20.04 as package

COPY --from=builder /deps /deps
COPY --from=builder /lacc/bin/lacc /lacc/bin/lacc
ENV LD_LIBRARY_PATH=/deps



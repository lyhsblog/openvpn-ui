#!/bin/bash
# VERSION 1.3 by d3vilh@github.com aka Mr. Philipp. Thanks bugsyb@github.com for all the efforts ;)
set -e  # Exit immediately if a command exits with a non-zero status. Set -x option for debugging

# Optional proxy for docker build (copy .proxy.env.example to .proxy.env and edit)
if [ -f .proxy.env ]; then
  # shellcheck disable=SC1091
  source .proxy.env
fi

HTTP_PROXY="${HTTP_PROXY:-${http_proxy:-}}"
HTTPS_PROXY="${HTTPS_PROXY:-${https_proxy:-${HTTP_PROXY}}}"
NO_PROXY="${NO_PROXY:-${no_proxy:-localhost,127.0.0.1}}"

PROXY_BUILD_ARGS=()
PROXY_RUN_ENVS=()
if [ -n "$HTTP_PROXY" ]; then
  PROXY_BUILD_ARGS+=(
    --build-arg "HTTP_PROXY=$HTTP_PROXY"
    --build-arg "HTTPS_PROXY=$HTTPS_PROXY"
    --build-arg "NO_PROXY=$NO_PROXY"
    --build-arg "http_proxy=$HTTP_PROXY"
    --build-arg "https_proxy=$HTTPS_PROXY"
    --build-arg "no_proxy=$NO_PROXY"
  )
  PROXY_RUN_ENVS+=(
    -e "HTTP_PROXY=$HTTP_PROXY"
    -e "HTTPS_PROXY=$HTTPS_PROXY"
    -e "NO_PROXY=$NO_PROXY"
    -e "http_proxy=$HTTP_PROXY"
    -e "https_proxy=$HTTPS_PROXY"
    -e "no_proxy=$NO_PROXY"
  )
  printf "\033[1;33mUsing build proxy:\033[0m %s\n" "$HTTP_PROXY"
fi

# Define the machine architecture
# PLATFORM="linux/amd64" # arm64v8 = "linux/arm64/v8", arm32v5 - "linux/arm/v5", arm32v7 - "linux/arm/v7", amd64 - "linux/amd64"
ARCH=$(uname -m)
case $ARCH in
  armv6*)
    PLATFORM="linux/arm/v5"
    #UIIMAGE="FROM arm32v5/debian:stable-slim"
    UIIMAGE="FROM arm32v6/alpine" #moving to unstable because it has easy-rsa v3.1.6 which supports cert renewal
    BEEIMAGE="FROM arm32v5/golang:1.21-bookworm"
    ;;
  armv7*)
    PLATFORM="linux/arm/v7"
    #UIIMAGE="FROM arm32v7/debian:stable-slim"
    UIIMAGE="FROM arm32v7/alpine" #moving to unstable because it has easy-rsa v3.1.6 which supports cert renewal
    BEEIMAGE="FROM arm32v7/golang:1.23.4-bookworm"
    ;;
  aarch64*)
    PLATFORM="linux/arm64/v8"
    #UIIMAGE="FROM arm64v8/debian:stable-slim"
    UIIMAGE="FROM arm64v8/alpine" #moving to unstable because it has easy-rsa v3.1.6 which supports cert renewal
    BEEIMAGE="FROM golang:1.23.4-bookworm"
    ;;
  arm64*)
    PLATFORM="linux/arm64/v8"
    #UIIMAGE="FROM arm64v8/debian:stable-slim"
    UIIMAGE="FROM arm64v8/alpine" #moving to unstable because it has easy-rsa v3.1.6 which supports cert renewal
    BEEIMAGE="FROM golang:1.23.4-bookworm"
    ;;
  *)
    PLATFORM="linux/amd64"
    #UIIMAGE="FROM debian:stable-slim"
    UIIMAGE="FROM alpine" #moving to unstable because it has easy-rsa v3.1.6 which supports cert renewal
    BEEIMAGE="FROM golang:1.23.4-bookworm"
    ;;
esac

# Benchmarking the start time get
start_time=$(date +%s)

printf "\033[1;34mBuilding for\033[0m $ARCH ($PLATFORM) with: \n  \033[1;34mUI Image:\033[0m $UIIMAGE \n  \033[1;34mBeeGo Image:\033[0m $BEEIMAGE \n"
# Update Dockerfile based on platform
sed -i "s#FROM DEFINE-YOUR-ARCH#$UIIMAGE#g" Dockerfile
# Update Dockerfile-beego based on platform
sed -i "s#FROM DEFINE-YOUR-ARCH#$BEEIMAGE#g" Dockerfile-beego
printf "Dockerfiles updated \n\033[1;34mBuilding Golang and Bee enviroment.\033[0m\n"

# Build golang & bee environment
docker build --progress=plain --platform=$PLATFORM -f Dockerfile-beego "${PROXY_BUILD_ARGS[@]}" -t local/beego-v8 -t local/beego-v8:latest .
printf "\033[1;34mBuilding OpenVPN-UI and qrencode binaries.\033[0m\n"

# Run a beego-v8 container to build qrencode and execute bee pack
printf "OpenVPN-UI and qrencode were built \n\033[1;34mBuilding OpenVPN-UI image.\033[0m\n"

time docker run \
    -v "$PWD/../":/go/src/github.com/d3vilh/openvpn-ui \
    -e GO111MODULE='auto' \
    -e CGO_ENABLED=1 \
    "${PROXY_RUN_ENVS[@]}" \
    --rm \
    -w /usr/src/myapp \
    local/beego-v8 \
sh -c "cd /go/src/github.com/d3vilh/openvpn-ui/ && \
    git config --global --add safe.directory /go/src/github.com/d3vilh/openvpn-ui && \
    go env -w GOFLAGS=\"-buildvcs=false\" && \
    bee version && \
    CGO_ENABLED=1 CC=musl-gcc bee pack -exr='^vendor|^ace.tar.bz2|^data.db|^build|^README.md|^docs' && \
    cd /app/qrencode && \
    go build -o qrencode main.go && \
    chmod +x /app/qrencode/qrencode && \
    cp -p /app/qrencode/qrencode /go/src/github.com/d3vilh/openvpn-ui/"
printf "OpenVPN-UI and qrencode were built \n\033[1;34mBuilding OpenVPN-UI image.\033[0m\n"

# Build OpenVPN-UI image
QRFILE="qrencode"
UIFILE="openvpn-ui.tar.gz"
cp -f ../$QRFILE ./
cp -f ../$UIFILE ./

# Build openvpn-ui image
docker build "${PROXY_BUILD_ARGS[@]}" -t local/openvpn-ui .
rm -f $UIFILE; rm -f $(basename $UIFILE); #rm -f $QRFILE;
printf "\033[1;34mAll done.\033[0m\n"

# Benchmarking the end time record
end_time=$(date +%s)
# Calculate the execution time in seconds
execution_time=$((end_time - start_time))
# Calculate the execution time in minutes and seconds
minutes=$((execution_time / 60))
seconds=$((execution_time % 60))

# Print the execution time in mm:ss format
printf "\033[1;34mExecution time: %02d:%02d\033[0m (%d sec)\n" $minutes $seconds $execution_time
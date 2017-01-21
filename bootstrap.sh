#!/usr/bin/env bash

set -e # stop script on error

# Install git
sudo apt-get update
sudo apt-get install -y git

# install go.
wget https://storage.googleapis.com/golang/go1.7.4.linux-amd64.tar.gz
tar -C /usr/local -xzvf go1.7.4.linux-amd64.tar.gz
kdir -p $HOME/go/src $HOME/go/bin $HOME/go/pkg
echo "export GOPATH=$HOME/go" >> $HOME/.bashrc
echo "export PATH=$PATH:$GOPATH/bin:/usr/local/go/bin" >> $HOME/.bashrc

# Get hugo
go get github.com/spf13/hugo

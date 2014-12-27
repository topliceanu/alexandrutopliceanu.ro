#!/usr/bin/env bash

# install ruby
sudo apt-get install -y python-software-properties
sudo apt-add-repository ppa:brightbox/ruby-ng
sudo apt-get update
sudo apt-get install -y ruby rubygems ruby-switch

# install nodejs.
sudo add-apt-repository ppa:chris-lea/node.js
sudo apt-get update
sudo apt-get install nodejs

# install jekyll.
gem install jekyll

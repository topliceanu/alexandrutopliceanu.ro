#!/usr/bin/env bash

sudo apt-get update
sudo apt-get install -y git-core curl zlib1g-dev build-essential libssl-dev libreadline-dev libyaml-dev libsqlite3-dev sqlite3 libxml2-dev libxslt1-dev libcurl4-openssl-dev python-software-properties

# install ruby.
sudo apt-get install -y libgdbm-dev libncurses5-dev automake libtool bison libffi-dev
curl -L https://get.rvm.io | bash -s stable
source ~/.rvm/scripts/rvm
echo "source ~/.rvm/scripts/rvm" >> ~/.bashrc
rvm install 2.1.5
rvm use 2.1.5 --default
ruby -v

# rubygems should not to install the docs locally.
echo "gem: --no-ri --no-rdoc" > ~/.gemrc

# install nodejs.
sudo add-apt-repository ppa:chris-lea/node.js
sudo apt-get update
sudo apt-get install nodejs

# install jekyll.
gem install jekyll

# aws-carb: amazon web services - cloudinit and route53 bootstrap

## Install

via rubygems:

```
gem install aws-carb
```

using bundler:

```
bundler install
```

## Configuration

At minimum, Carb needs to know your aws-ec2 credentials. The simplest way to allow this is to edit ~/.carb/config/config.yaml. See config/config.yaml.example for an example config.


## Example usage

carb can be used to create ec2 instances

```
aws create
```


## Temporary Quickstart Docs..

Leaving this stuff here until proper docs have been written:

```
# works on ruby > 1.9 
gem install aws-carb

# install config and template directories
mkdir -p ~/.carb/{config,templates}

sudo updatedb

cp `locate gems/aws-carb-0.0.3/configs/config.yaml.example`  ~/.carb/config/config.yaml
cp `locate gems/aws-carb-0.0.3/template/basic.cloud-config.erb` ~/.carb/templates/

# edit config.yaml - remember to specify an ssh key because without one your ec2 instance will be inaccessible! (copy your ssh key from id_rsa.pub as a string - not a file path)
vim ~/.carb/config/config.yaml

# examples:

# create a basic instance like this (or put 'image_id' into 'ec2' section of config.yaml):
carb create --image-id <ami id>

# create an instance but bootstrap it with the user-data cloudinit template and also get some route53 goodness going on because hostname is set
# run with verbose to see more interesting info
carb -v create --user-data-template ~/.carb/templates/basic.cloud-config.erb --common-variables "{ 'hostname' => 'asdasdasasdasdsa' }"

# list all the ec2 options:
carb help create 

# 
--block-device-mappings="{ :device_name => "/dev/sdc", :ebs => { :volume_size => "100G" } }"




```



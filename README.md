# amazon web services - cloudinit and route53 bootstrap

```
      
       ::::::::      :::     :::::::::  :::::::::  
      :+:    :+:   :+: :+:   :+:    :+: :+:    :+: 
      +:+         +:+   +:+  +:+    +:+ +:+    +:+ 
      +#+        +#++:++#++: +#++:++#:  +#++:++#+  
      +#+        +#+     +#+ +#+    +#+ +#+    +#+ 
      #+#    #+# #+#     #+# #+#    #+# #+#    #+# 
       ########  ###     ### ###    ### #########  
      
          - cloudinit and route53 bootstrap -

```

## Install




### rubygems

```
gem build aws-carb.gemspec
gem install --local aws-carb-*.gem
```

### Dependencies

If you've compiled your own ruby (rvm/rbenv, etc) then you will need to make sure ruby has support for various libraries.

For debian based systems, do the following before compiling ruby:
```
sudo apt-get isntall libreadline-dev zlib1g-dev libssl-dev
```

## Configuration

At minimum, Carb needs to know your aws-ec2 credentials. The simplest way to allow this is to edit ~/.carb/config/config.yaml. See config/config.yaml.example for an example config.

See aws-config project for credentials

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
mkdir -p ~/.carb/{config,template}

sudo updatedb

cp `locate gems/aws-carb-0.0.3/examples/config/config.yaml.example`  ~/.carb/config/config.yaml
cp `locate gems/aws-carb-0.0.3/examples/template/basic.cloud-config.erb` ~/.carb/template/

# edit config.yaml - remember to specify an ssh key because without one your ec2 instance will be inaccessible! (copy your ssh key from id_rsa.pub as a string - not a file path)
vim ~/.carb/config/config.yaml

# examples:

# create a basic instance like this (or put 'image_id' into 'ec2' section of config.yaml):
carb create --image-id <ami id>

# create an instance but bootstrap it with the user-data cloudinit template and also get some route53 goodness going on because hostname is set
# run with verbose to see more interesting info
# Note: parameters specified on the command line override variables set in the config file
carb -v create --user-data-template ~/.carb/template/basic.cloud-config.erb --common-variables "{ 'hostname' => 'asdasdasasdasdsa' }"

# list all the ec2 options:
carb help create

```

## Understanding block-device-mappings

### Description

When specifying block-device mappings, each mapping must be a valid hash and must be contained in an array.

Once the machine has booted the block device(s) will be available through their virtual block device, e.g:

```
# /dev/xv<disk><partition>
/dev/sdc1 = /dev/xvc1
/dev/sdf0 = /dev/xvf0
...
```

http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/block-device-mapping-concepts.html

### Examples

A typical block device mapping:

```
[{ 'device_name' => '/dev/sdf1', 'ebs' => { 'volume_size' => 500 } }]
```

Multiple block device mappings:
```
[
  { 'device_name' => '/dev/sdf1', 'ebs' => { 'volume_size' => 500 } },
  { 'device_name' => '/dev/sdf2', 'ebs' => { 'volume_size' => 500 } }
]
```

Typical command line usage:
```
carb -c ~/.carb/config/config.yaml -v create --user-data-template ~/.carb/template/basic.cloud-config.erb --block-device-mappings "[{ 'device_name' => '/dev/sdf1', 'ebs' => { 'volume_size' => 500 } }]"
```

Example customer command line usage:
```

ithaka sams

carb -c ~/.carb/config/ithaka-lucid-xa.yaml -v create --user-data-template ~/.carb/template/cloud-config.erb  --instance-type c3.xlarge --common-variables "{ 'hostname' => 'cspithsam08x1' }" --block-device-mappings "[{ 'device_name' => '/dev/sda1', 'ebs' => { 'volume_size' => 32, 'volume_type' => 'gp2' } }]"

arb -c ~/.carb/config/ithaka-lucid-yb.yaml -v create --user-data-template ~/.carb/template/cloud-config.erb  --instance-type c3.xlarge --common-variables "{ 'hostname' => 'cspithsam08y2' }" --block-device-mappings "[{ 'device_name' => '/dev/sda1', 'ebs' => { 'volume_size' => 32, 'volume_type' => 'gp2' } }]"

ithaka star

carb -c ~/.carb/config/ithaka-star-xa.yaml -v create --user-data-template ~/.carb/template/cloud-config.erb  --instance-type c1.medium --common-variables "{ 'hostname' => 'cspithstar08x2' }" --block-device-mappings "[{ 'device_name' => '/dev/sda1', 'ebs' => { 'volume_size' => 12, 'volume_type' => 'gp2' } }]"

carb -c ~/.carb/config/ithaka-star-yb.yaml -v create --user-data-template ~/.carb/template/cloud-config.erb  --instance-type c1.medium --common-variables "{ 'hostname' => 'cspithstar08y2' }" --block-device-mappings "[{ 'device_name' => '/dev/sda1', 'ebs' => { 'volume_size' => 12, 'volume_type' => 'gp2' } }]"

ithaka dataqa

carb -c ~/.carb/config/ithaka-star-dataqa-x.yaml -v create --user-data-template ~/.carb/template/cloud-config.erb  --instance-type c1.medium  --common-variables "{ 'hostname' => 'cspithqastar08x2' }"

single node sams in our aws account

carb -c ~/.carb/config/sem-x.yaml -v create --user-data-template ~/.carb/template/cloud-config.erb  --instance-type t2.medium --common-variables "{ 'hostname' => 'cspcolsam30x1' }" --block-device-mappings "[{ 'device_name' => '/dev/sda1', 'ebs' => { 'volume_size' => 32, 'volume_type' => 'gp2' } }]"



```



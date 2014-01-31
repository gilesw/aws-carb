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




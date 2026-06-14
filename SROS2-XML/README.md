# SROS2 Configurations

## SROS2 Set-Up
```
$ ros2 security create_keystore demo_keystore
$ ros2 security create_enclave demo_keystore /talker_listener/talker
$ ros2 security create_enclave demo_keystore /talker_listener/listener
$ export ROS_SECURITY_KEYSTORE=/home/aw/sros2/demo_keystore
$ export ROS_SECURITY_ENABLE=true
$ export ROS_SECURITY_STRATEGY=Enforce
```

You will then need to configure permissions settings in `autoware_launch.xml` to enable access control. See the `.xml` files
for implementations.


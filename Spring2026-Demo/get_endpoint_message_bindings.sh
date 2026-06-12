# When trying to call Tier4 or Autoware-specific custom service endpoints in ROS, you may get the error: "The passed service type is invalid"
# This may happen because the Autoware Docker image doesn't come with the message package's Python bindings. You're most likely using 'ros2 service call',
# which is a Python CLI that doesn't include the needed bindings.

# You can verify that this is the case by doing:
# - $ echo $AMENT_PREFIX_PATH
# 	- If it returns only /opt/ros/humble, that means there is no Autoware overlay sourced
# - $ ros2 package list | grep tier4
# 	- If it returns nothing, that means that no Autoware packages are visible to Python tools
# - $ ros2 service type /api/autoware/set/emergency
# 	- This should still work, confirming that it is a serialization issue

# The solution to this is to build message packages from source with the commands below

cd /tmp
git clone https://github.com/autowarefoundation/autoware_msgs.git --depth=1
git clone https://github.com/tier4/tier4_autoware_msgs.git --depth=1 --branch v0.58.0
git clone https://github.com/autowarefoundation/autoware_adapi_msgs.git --depth=1 --branch 1.9.1
mkdir -p /tmp/msgs_ws/src
cp -r /tmp/autoware_msgs/. /tmp/msgs_ws/src/
cp -r /tmp/tier4_autoware_msgs/. /tmp/msgs_ws/src/
cp -r /tmp/autoware_adapi_msgs/. /tmp/msgs_ws/src/
cd /tmp/msgs_ws
colcon build --packages-up-to tier4_external_api_msgs autoware_adapi_v1_msgs
source /opt/ros/humble/setup.bash
source /tmp/msgs_ws/install/setup.bash



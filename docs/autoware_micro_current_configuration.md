# autoware_micro_launch Current Configuration

This document summarizes the current `autoware_micro_launch` configuration after the Planning Simulator simplification work.

Related diagram: `docs/autoware_micro_current_configuration.drawio`

## Purpose

`autoware_micro_launch` is a Palta micro focused launch package that keeps the Autoware execution path readable inside one package. The launch files under `launch/modules/` define the major functional boundaries, and the files under `launch/universe_module/` contain the copied, simplified Autoware Universe launch hierarchy needed to trace each module locally.

There are two primary entry points.

- `src/launcher/autoware_micro_launch/launch/autoware.launch.xml`
  - Full Palta micro launch entry point.
  - Starts vehicle, map, sensing, localization, minimal LiDAR perception, planning, control, system, and RViz by default.
  - `launch_api` defaults to `false` so the graph remains easier to read.
- `src/launcher/autoware_micro_launch/launch/planning_simulator.launch.xml`
  - Planning Simulator launch entry point.
  - Starts Autoware planning/control/system/API with simulator-side dummy vehicle, localization, and perception inputs.
  - Disables real sensing and real localization.
  - Keeps `launch_api=true` because RViz initial pose, route, and engage operations depend on AD API behavior.

## Overall Data Flow

In the full launch, the main flow is:

```text
Vehicle + Sensing
  -> Map / Localization / Perception
  -> Planning
  -> Control
  -> Vehicle command output
```

In Planning Simulator, the real vehicle and real localization/sensing inputs are replaced by simulator-side nodes:

```text
Simulator dummy vehicle / localization / perception
  -> Map / optional minimal perception
  -> Planning
  -> Control
  -> simple_planning_simulator
```

The simulator needs one explicit engage bridge:

```text
/autoware/engage -> /vehicle/engage
```

This bridge is implemented by `simulator_engage_relay` in `planning_simulator.launch.xml`. Without it, Autoware can enter AUTO, but `simple_planning_simulator` does not receive the engage command that starts vehicle motion.

## Current Planning Shape

Planning is intentionally reduced for learning. The current default focuses on:

```text
route
  -> behavior path
  -> simple trajectory conversion
  -> motion velocity planning
  -> scenario selection
  -> velocity smoothing
  -> planning trajectory relay
  -> control
```

The important defaults are:

```bash
motion_path_smoother_type:=none
motion_path_planner_type:=none
launch_planning_validator:=false
launch_planning_evaluator:=false
launch_parking_module:=false
launch_obstacle_stop_module:=true
```

With `motion_path_planner_type:=none`, `path_optimizer` is not launched. The path from behavior planning is converted to a trajectory by `autoware_planning_topic_converter::PathToTrajectory`.

With `launch_planning_validator:=false`, Planning Validator is not launched. Since validator normally publishes `/planning/trajectory`, a relay keeps the Control input alive:

```text
/planning/scenario_planning/velocity_smoother/trajectory
  -> /planning/trajectory
```

`autoware.launch.xml` also relays:

```text
/planning/trajectory
  -> /planning/scenario_planning/trajectory
```

This preserves the topic expected by downstream Autoware modules and visualization.

## Planning Modules Kept

The following modules remain in the default Planning path because they are useful for understanding route-to-control behavior:

- `autoware_mission_planner_universe`
- `autoware_scenario_selector`
- `autoware_external_velocity_limit_selector`
- `autoware_velocity_smoother`
- `autoware_hazard_lights_selector`
- `autoware_behavior_path_planner`
- `autoware_behavior_velocity_planner`
- `autoware_planning_topic_converter`
- `autoware_motion_velocity_planner`

The default plugin set is also reduced:

- Behavior path:
  - `autoware_behavior_path_static_obstacle_avoidance_module`
  - `autoware_behavior_path_start_planner_module`
- Motion velocity:
  - `autoware_motion_velocity_obstacle_stop_module`

## Planning Modules Skipped By Default

The following are disabled by default to keep the simulator path small:

- Path smoothing and curvature optimization:
  - `motion_path_smoother_type:=none`
  - `motion_path_planner_type:=none`
- Planning validation and evaluation:
  - `launch_planning_validator:=false`
  - `launch_planning_evaluator:=false`
- Parking / freespace planning:
  - `launch_parking_module:=false`
- Manual lane change handler:
  - `launch_manual_lane_change_handler:=false`
- Behavior velocity map-rule modules:
  - crosswalk, walkway, traffic light, intersection, stop line, detection area, virtual traffic light, no stopping area, blind spot
- Motion velocity special modules:
  - obstacle slow down, obstacle cruise, dynamic obstacle stop, out of lane, obstacle velocity limiter, run out, boundary departure prevention, road user stop
- Control safety/evaluator modules:
  - lane departure checker, control validator, AEB, collision detector, control evaluator

Most of these can still be re-enabled by passing launch arguments, but the default path is optimized for reading and basic Planning Simulator motion.

## Control Path

Control keeps the minimum modules needed to receive `/planning/trajectory`, manage operation mode, and output vehicle commands:

```text
/planning/trajectory
  -> trajectory follower
  -> shift decider
  -> vehicle command gate / control command gate
  -> operation mode transition manager
  -> control_command_mux
  -> vehicle command output
```

`control_command_mux` remains enabled by default so Autoware control commands and external/teleop command paths can be multiplexed consistently.

## System And Diagnostics

System still launches the operation/safety shell:

- operation mode and command mode handling
- diagnostic graph aggregator
- component state monitoring
- MRM comfortable/emergency stop operators
- hazard status conversion
- rosbag node monitoring

Heavy host monitors are disabled by default:

```bash
launch_system_monitor:=false
```

The diagnostic graph uses the micro-specific configuration:

```text
src/launcher/autoware_micro_launch/config/system/diagnostics/autoware-micro.yaml
```

The Planning diagnostic condition was simplified so AUTO does not depend on Planning Validator diagnostics. The current Planning diagnostic graph checks route state and topic rates for route/trajectory, but does not require `/autoware/planning/trajectory_validation`.

## Build Scope

`src/launcher/autoware_micro_launch/build_target.txt` lists the packages needed for the current default configuration. After simplification, the Planning section keeps the minimal route-to-control path and only the plugin packages needed by the enabled defaults.

The build command remains:

```bash
./src/launcher/autoware_micro_launch/build.sh
```

The script reads `build_target.txt`, uses `--packages-up-to`, sets Release build mode, and uses a workspace-local `CCACHE_DIR`.

## How To Read The Launch Hierarchy

Start from one of the entry points:

```text
launch/autoware.launch.xml
launch/planning_simulator.launch.xml
```

Then follow functional includes:

```text
launch/modules/map.launch.xml
launch/modules/localization.launch.xml
launch/modules/perception.launch.xml
launch/modules/planning.launch.xml
launch/modules/control.launch.xml
launch/modules/system.launch.xml
launch/modules/simulator.launch.xml
```

For Planning details, continue through:

```text
launch/universe_module/planning/planning.launch.xml
launch/universe_module/planning/scenario_planning/scenario_planning.launch.xml
launch/universe_module/planning/scenario_planning/lane_driving.launch.xml
launch/universe_module/planning/scenario_planning/lane_driving/behavior_planning/behavior_planning.launch.xml
launch/universe_module/planning/scenario_planning/lane_driving/motion_planning/motion_planning.launch.xml
```

This path shows the current simplified flow from mission planning to behavior path planning, simple path-to-trajectory conversion, motion velocity planning, velocity smoothing, and the final trajectory relay.

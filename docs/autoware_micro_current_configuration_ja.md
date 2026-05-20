# autoware_micro_launch 現状構成

この文書は、Planning Simulator 向けの簡略化を反映した現在の `autoware_micro_launch` 構成をまとめたものです。

関連図: `docs/autoware_micro_current_configuration.drawio`

## 目的

`autoware_micro_launch` は、Palta micro 向けの Autoware 起動構成を読みやすくまとめるための launch package です。`launch/modules/` には vehicle、map、planning、control などの大きな機能単位の入口を置き、`launch/universe_module/` には Autoware Universe 側の中間 launch を必要な範囲で移植しています。

これにより、Autoware の起動経路を `autoware_micro_launch` の中だけで追いやすくしています。

主な entry point は 2 つです。

- `src/launcher/autoware_micro_launch/launch/autoware.launch.xml`
  - Palta micro の通常起動入口です。
  - 既定では vehicle、map、sensing、localization、minimal LiDAR perception、planning、control、system、RViz を起動します。
  - 起動グラフを読みやすくするため、`launch_api` は既定で `false` です。
- `src/launcher/autoware_micro_launch/launch/planning_simulator.launch.xml`
  - Planning Simulator 用の起動入口です。
  - 実センサと実 localization の代わりに、simulator 側の dummy vehicle、dummy localization、dummy perception を使います。
  - Planning、Control、System、API は起動します。
  - RViz からの initial pose、route、engage 操作に AD API が必要なため、`launch_api=true` を既定にしています。

## 全体のデータフロー

通常起動では、おおまかな流れは次のようになります。

```text
Vehicle + Sensing
  -> Map / Localization / Perception
  -> Planning
  -> Control
  -> Vehicle command output
```

Planning Simulator では、実車両・実 localization・実 sensing の入力を simulator 側の node で置き換えます。

```text
Simulator dummy vehicle / localization / perception
  -> Map / optional minimal perception
  -> Planning
  -> Control
  -> simple_planning_simulator
```

Planning Simulator では、engage の topic を明示的につなぐ必要があります。

```text
/autoware/engage -> /vehicle/engage
```

この bridge は `planning_simulator.launch.xml` の `simulator_engage_relay` で実装しています。これがないと、Autoware 側は AUTO に入っても、`simple_planning_simulator` が走行開始の engage を受け取れず、車両が動きません。

## 現在の Planning 構成

Planning は学習用に意図的に小さくしています。現在の既定構成では、以下の流れに注目できます。

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

重要な既定値は次の通りです。

```bash
motion_path_smoother_type:=none
motion_path_planner_type:=none
launch_planning_validator:=false
launch_planning_evaluator:=false
launch_parking_module:=false
launch_obstacle_stop_module:=true
```

`motion_path_planner_type:=none` により、`path_optimizer` は起動しません。Behavior Planning が出した path は、`autoware_planning_topic_converter::PathToTrajectory` によって trajectory に変換されます。

また、`launch_planning_validator:=false` により、Planning Validator は起動しません。通常は validator が `/planning/trajectory` を出力しますが、validator を消すと Control への入力が途切れるため、relay で補っています。

```text
/planning/scenario_planning/velocity_smoother/trajectory
  -> /planning/trajectory
```

さらに `autoware.launch.xml` では、次の relay も起動しています。

```text
/planning/trajectory
  -> /planning/scenario_planning/trajectory
```

これにより、後段 module や可視化が期待する topic を維持しています。

## 既定で残している Planning module

現在の Planning path では、route から control へつながる基本的な流れを理解するため、以下を残しています。

- `autoware_mission_planner_universe`
- `autoware_scenario_selector`
- `autoware_external_velocity_limit_selector`
- `autoware_velocity_smoother`
- `autoware_hazard_lights_selector`
- `autoware_behavior_path_planner`
- `autoware_behavior_velocity_planner`
- `autoware_planning_topic_converter`
- `autoware_motion_velocity_planner`

plugin も最小寄りにしています。

- Behavior path:
  - `autoware_behavior_path_static_obstacle_avoidance_module`
  - `autoware_behavior_path_start_planner_module`
- Motion velocity:
  - `autoware_motion_velocity_obstacle_stop_module`

## 既定で skip している Planning module

Planning Simulator の経路を小さく保つため、以下は既定で無効にしています。

- Path smoothing / curvature optimization:
  - `motion_path_smoother_type:=none`
  - `motion_path_planner_type:=none`
- Planning validation / evaluation:
  - `launch_planning_validator:=false`
  - `launch_planning_evaluator:=false`
- Parking / freespace planning:
  - `launch_parking_module:=false`
- Manual lane change handler:
  - `launch_manual_lane_change_handler:=false`
- Behavior velocity の地図ルール系 module:
  - crosswalk、walkway、traffic light、intersection、stop line、detection area、virtual traffic light、no stopping area、blind spot
- Motion velocity の特殊 module:
  - obstacle slow down、obstacle cruise、dynamic obstacle stop、out of lane、obstacle velocity limiter、run out、boundary departure prevention、road user stop
- Control の safety / evaluator 系 module:
  - lane departure checker、control validator、AEB、collision detector、control evaluator

これらの多くは launch argument を渡せば再度有効化できます。ただし現在の既定構成は、Planning Simulator で基本的な走行を確認しつつ、launch と topic の流れを読みやすくすることを優先しています。

## Control の流れ

Control は、`/planning/trajectory` を受け取り、operation mode を管理し、車両 command を出力するために必要な最小構成を残しています。

```text
/planning/trajectory
  -> trajectory follower
  -> shift decider
  -> vehicle command gate / control command gate
  -> operation mode transition manager
  -> control_command_mux
  -> vehicle command output
```

`control_command_mux` は既定で有効です。Autoware の control command と external / teleop 系 command を一貫して扱えるようにするためです。

## System と Diagnostics

System では、operation / safety に関わる外枠は残しています。

- operation mode / command mode handling
- diagnostic graph aggregator
- component state monitoring
- MRM comfortable / emergency stop operators
- hazard status conversion
- rosbag node monitoring

一方、重い host monitor は既定で無効です。

```bash
launch_system_monitor:=false
```

diagnostic graph には micro 用の設定を使っています。

```text
src/launcher/autoware_micro_launch/config/system/diagnostics/autoware-micro.yaml
```

Planning の診断条件は、Planning Validator に依存しないように簡略化しています。現在の Planning diagnostic graph は route state と route / trajectory の topic rate を確認しますが、`/autoware/planning/trajectory_validation` は要求しません。

これにより、Planning Validator を起動していない構成でも AUTO 遷移条件を満たせるようにしています。

## Build 対象

`src/launcher/autoware_micro_launch/build_target.txt` には、現在の既定構成に必要な package を列挙しています。

Planning 簡略化後は、route から control までの最小経路と、既定で有効な plugin package のみを中心に残しています。

build コマンドは次の通りです。

```bash
./src/launcher/autoware_micro_launch/build.sh
```

`build.sh` は `build_target.txt` を読み込み、`--packages-up-to` で依存 package も含めて build します。Release build を指定し、`CCACHE_DIR` は workspace 内に向けています。

## Launch 階層の読み方

まず、次のどちらかの entry point から読み始めます。

```text
launch/autoware.launch.xml
launch/planning_simulator.launch.xml
```

次に、機能単位の launch を追います。

```text
launch/modules/map.launch.xml
launch/modules/localization.launch.xml
launch/modules/perception.launch.xml
launch/modules/planning.launch.xml
launch/modules/control.launch.xml
launch/modules/system.launch.xml
launch/modules/simulator.launch.xml
```

Planning の詳細は、次の順番で追うと理解しやすいです。

```text
launch/universe_module/planning/planning.launch.xml
launch/universe_module/planning/scenario_planning/scenario_planning.launch.xml
launch/universe_module/planning/scenario_planning/lane_driving.launch.xml
launch/universe_module/planning/scenario_planning/lane_driving/behavior_planning/behavior_planning.launch.xml
launch/universe_module/planning/scenario_planning/lane_driving/motion_planning/motion_planning.launch.xml
```

この経路を追うことで、mission planning から behavior path planning、simple path-to-trajectory conversion、motion velocity planning、velocity smoothing、最後の trajectory relay までの流れを確認できます。

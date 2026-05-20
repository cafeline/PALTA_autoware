# Autoware Learning Simplification Notes

## 目的

このドキュメントは、`docs/architecture.md` で分析した Palta 向け Autoware 構成について、初学者が Autoware の全体像を学ぶときに、どの機能を一時的に skip できそうかを整理したものです。

前提として、Vehicle、Map、Sensing は簡略化しにくいものとして扱います。これらは Autoware の入力と実機接続の土台であり、ここを削ると topic graph の意味が大きく変わります。学習用に簡略化するなら、主に System、Validator、Evaluator、Planning の細かなシーンモジュール、Control の監視系から段階的に見ます。

ここでの「skip」は、実運用・実機走行で安全に無効化できるという意味ではありません。初学者が構成を読む、launch の依存関係を追う、最小限の情報流を理解する目的で、学習段階では後回しにできる候補という意味です。

## 判断基準

skip 候補は次の基準で分類します。

- **維持推奨**: これを外すと Autoware の主要な情報流が壊れる、または vehicle/map/sensing/localization/planning/control の接続理解が難しくなる。
- **学習初期は後回し可**: 主要な入力・出力の理解には必須ではない。安全監視、診断、評価、可視化、細かな挙動調整に近い。
- **条件付きで skip 可**: 目的によっては外せるが、シナリオや topic の前提が変わる。外す場合は何を学ばないことにするかを明確にする。
- **注意して維持**: 一見複雑だが、自動運転の基本ループに近い。完全に外すより「中身をブラックボックスとして扱う」方がよい。

## 全体方針

初心者向けには、最初からすべての Autoware module を理解しようとしない方がよいです。まず次の太い流れだけを残して理解します。

```text
Sensing
  -> Localization
  -> Perception
  -> Planning
  -> Control
  -> Vehicle
```

この流れを追ううえで、Vehicle、Map、Sensing は保持します。Perception はすでに `lidar_obstacle_detection_minimal` が指定されており、かなり簡略化されています。さらに簡略化する余地が大きいのは、System、Planning validator、Control checker、Planning の細かな behavior module です。

## 維持したいもの

### Vehicle

Vehicle は簡略化しない方がよいです。

理由は、最終的な `/control/command/*` がどのように実機側へ渡るかを理解するために必要だからです。`palta_launch/launch/vehicle_interface.launch.xml` は LSDB、CAN、DIO、左右モータ interface を束ねており、Palta 固有の構成理解の中心です。

学習時は内部実装まで深追いせず、次の対応だけを押さえるのがよいです。

- Control の出力: `/control/command/control_cmd`, `/control/command/gear_cmd`
- Vehicle 側の変換: `lsdb_interface`
- 左右駆動系への出力: `/s1/left/command`, `/s1/right/command`
- 車両状態の入力: `/vehicle/status/*`

### Map

Map も簡略化しない方がよいです。

Localization は点群地図に依存し、Planning は Lanelet2 の vector map に依存します。Map を外すと NDT、route、behavior planning、lane departure checker などの理解が難しくなります。

学習時は、Map の中身を詳細に理解するより、次の役割分担だけを把握すれば十分です。

- `/map/pointcloud_map`: NDT localization 用
- `/map/vector_map`: route、lane、traffic rule、planning 用
- `/map/vector_map_marker`: RViz 表示用
- `/map/get_differential_pointcloud_map`: NDT が使う点群地図サービス

### Sensing

Sensing も簡略化しない方がよいです。

今回の構成では Palta の 2 台 LiDAR、IMU、車速変換が Localization と Perception の入力になります。ここを削ると、以降の module の入力 topic が成立しません。

ただし、学習時に詳細を読む優先度は分けられます。最初は次だけ押さえれば十分です。

- 2 台の Hesai LiDAR から `/sensing/lidar/concatenated/pointcloud` を作る。
- IMU は `/sensing/imu/imu_data` を出す。
- 車速は `/sensing/vehicle_velocity_converter/twist_with_covariance` に変換され、gyro odometer に使われる。

## System の skip 候補

System は最も skip 候補が多い領域です。System は安全監視、診断、MRM、operation mode、rosbag node 監視などを含み、実運用では重要ですが、Autoware の基本的な認識・計画・制御の流れを理解するだけなら最初は重く見えます。

### 学習初期は後回しにしやすいもの

- `launch_system_monitor:=false`
  - CPU/GPU/HDD/memory/network/NTP/process/voltage などの system monitor を止める候補です。
  - Autoware の主処理 topic flow には直接関与しないため、初学者の構成把握では後回しにしやすいです。

- `launch_dummy_diag_publisher:=false`
  - 既定でも `false` です。
  - 学習用には有効化しない方が読みやすいです。

- `require_rosbag_for_auto:=false`
  - すでに指定済みです。
  - rosbag recorder の存在確認を AUTO 遷移条件に入れないため、学習時の余計な前提を減らせます。

### launch 引数だけでは簡単に切れないもの

`tier4_system_launch/launch/system.launch.xml` には、次のような診断・監視系が含まれます。

- duplicated node checker
- processing time checker
- pipeline latency monitor
- rosbag node monitor
- service log checker
- component state monitor
- diagnostic graph aggregator
- hazard status converter
- MRM handler/operator

これらは `launch_system_monitor` のような単一引数では全部を止められません。学習用に完全に簡略化したい場合は、`launch_system:=false` で System 全体を止める選択肢があります。

ただし、`launch_system:=false` は注意が必要です。Control の operation mode、state、emergency、MRM との接続理解が変わる可能性があります。初心者が「Perception から Control までのデータの太い流れ」を読むだけなら有効ですが、「AUTO に入る条件」や「安全状態の管理」を学ぶ段階では戻すべきです。

## Perception の skip 候補

今回の Perception はすでに `perception_module_preset:=lidar_obstacle_detection_minimal` です。そのため、初学者向けにはかなり良い簡略構成です。

### すでに skip されているもの

最小プリセットにより、次の複雑な構成は基本的に起動されません。

- camera/lidar/radar fusion
- LiDAR DNN detector
- camera 2D detector
- radar fusion
- traffic light recognition
- irregular object detector
- object validator/filter の複雑な分岐

### 維持したいもの

最小プリセット内の次の処理は維持した方がよいです。

- ground segmentation
- LiDAR rule detector / clustering
- occupancy grid map
- multi object tracker
- map based prediction

この 5 つは、点群から planning が使う障害物情報へ変換する流れを理解するうえで重要です。さらに削ると、Planning が何を入力にしているかが見えにくくなります。

### 条件付きで後回しにできるもの

- `tracking.launch.xml`
  - 「検出物体が Planning に入る」だけを見たい段階では、tracking の詳細は後回しにできます。
  - ただし launch 上は prediction が tracking output を入力にしているため、単純に外すと `/perception/object_recognition/objects` までの流れが崩れます。skip するなら launch 変更や topic relay が必要になります。

- `prediction.launch.xml`
  - 予測の詳細は後回しにできます。
  - ただし最終 object topic `/perception/object_recognition/objects` を出す役割があるため、実際に止めるなら detection/tracking output を Planning 入力へ差し替える必要があります。

結論として、Perception は現在の minimal preset 以上に無理に削らず、「中身の理解を後回しにする」方が安全です。

## Localization の skip 候補

Localization は基本的に維持した方がよいです。NDT、gyro odometer、EKF は自車位置と速度を作る中心です。

### 維持したいもの

- NDT scan matcher
- NDT 用点群前処理
- gyro odometer
- EKF localizer
- stop filter
- twist2accel

これらを外すと `/localization/kinematic_state` や `/localization/acceleration` が出なくなり、Planning/Control の入力が壊れます。

### 後回しにできるもの

- localization error monitor
  - 位置推定の異常監視なので、学習初期は詳細理解を後回しにできます。
  - ただし launch 単位で簡単に off にする引数は見当たらないため、実際に skip するには launch 編集が必要です。

- pose instability detector
  - EKF 後の監視系として扱えます。
  - ただし `pose_twist_fusion_filter.launch.xml` 内に含まれるため、個別に切るには launch 側の編集が必要です。

Localization は「削る」よりも、「NDT pose + gyro twist -> EKF -> kinematic_state」という 1 行の理解に圧縮して読むのがよいです。

## Planning の skip 候補

Planning は最も module 数が多く、初心者には複雑に見えやすい領域です。Map/Sensing/Vehicle は維持しつつ、Planning では細かな scene module と validator を減らすのが読みやすさに効きます。

### 維持したい太い流れ

次の流れは維持した方がよいです。

```text
mission_planning/route
  -> behavior_planning/path
  -> motion_planning/trajectory
  -> velocity_smoother
  -> planning_validator
  -> /planning/trajectory
```

Planning 全体を理解するには、mission planning、scenario planning、lane driving、behavior planning、motion planning の関係を押さえることが重要です。

### 学習初期に off 候補となる Planning module

`default_preset.yaml` で引数化されているため、以下は学習用に off 候補です。

- `launch_parking_module:=false`
  - 初学者が lane driving だけを学ぶなら parking は後回しでよいです。
  - parking を止めると freespace planner と costmap generator の理解負荷を減らせます。

- `launch_remaining_distance_time_calculator:=false`
  - 到達残距離・残時間の補助情報です。
  - 主な planning trajectory の生成には直接関与しないため、後回しにできます。

- `launch_lane_change_right_module:=false`
- `launch_lane_change_left_module:=false`
- `launch_avoidance_by_lane_change_module:=false`
- `launch_side_shift_module:=false`
- `launch_bidirectional_traffic_module:=false`
  - 初期学習では「単一路線を進む」構成に寄せると読みやすいです。
  - lane change や side shift は behavior path planner の理解を難しくします。

- `launch_blind_spot_module:=false`
- `launch_detection_area_module:=false`
- `launch_virtual_traffic_light_module:=false`
- `launch_no_stopping_area_module:=false`
  - 特定の地図要素や交通ルールに関係するため、最初は後回しにしやすいです。

### 維持した方がよい Planning module

初期学習でも、次は残す方が理解しやすいです。

- `launch_static_obstacle_avoidance:=true`
  - Perception の障害物が Planning にどう効くかを学べます。

- `launch_start_planner_module:=true`
  - 発進時の挙動に関係します。

- `launch_crosswalk_module:=true`
- `launch_walkway_module:=true`
- `launch_traffic_light_module:=true`
- `launch_intersection_module:=true`
- `launch_stop_line_module:=true`
  - Lanelet2 map の意味を学ぶには代表的な behavior velocity module として残す価値があります。
  - ただし今回の minimal Perception では traffic light recognition が起動されないため、信号認識まで学ぶ段階で別途 topic 供給を確認します。

- motion velocity planner の obstacle 系
  - `launch_obstacle_stop_module`
  - `launch_obstacle_slow_down_module`
  - `launch_obstacle_cruise_module`
  - `launch_dynamic_obstacle_stop_module`
  - Perception と Planning の接続を理解するために有用です。

### Validator の skip 候補

Planning validator は最終 trajectory の健全性確認です。実運用では重要ですが、初学者が「trajectory がどう作られるか」を追う段階では複雑さの原因になります。

off 候補は次のとおりです。

- `launch_latency_checker:=false`
- `launch_intersection_collision_checker:=false`
- `launch_rear_collision_checker:=false`

一方で、`launch_trajectory_checker` は最終 trajectory の基本的な妥当性に近いため、最初から完全に外すより、残しておくか、後で比較するのがよいです。

注意点として、`planning.launch.xml` は validator の出力を `/planning/trajectory` として使っています。Planning validator 自体を完全に外す場合、`/planning/scenario_planning/velocity_smoother/trajectory` を `/planning/trajectory` に relay するなど、出力 topic の接続変更が必要になります。単に validator を消すだけでは Control 入力が途切れる可能性があります。

## Control の skip 候補

Control は trajectory follower、vehicle command gate、operation mode transition manager が中心です。この中心部分は維持した方がよいです。

### 維持したいもの

- `trajectory_follower_node`
- `vehicle_cmd_gate`
- `operation_mode_transition_manager`
- `shift_decider`
- `control_command_mux`

これらを追うことで、`/planning/trajectory` が `/control/command/control_cmd` へ変換される流れを理解できます。

### 学習初期に off 候補となるもの

`control/default_preset.yaml` で引数化されているため、次は off 候補です。

- `launch_control_evaluator:=false`
  - 評価用なので、初期学習では後回しにできます。

- `launch_lane_departure_checker:=false`
  - lane departure の安全監視です。
  - Map と trajectory の関係を検証する機能ですが、Control の基本ループ理解では後回しにできます。

- `launch_control_validator:=false`
  - Control output の検証です。
  - 初期学習では trajectory follower の入出力を優先して見ればよいです。

- `launch_autonomous_emergency_braking:=false`
  - AEB は重要な安全機能ですが、初学者が通常制御の流れを理解する段階では複雑です。
  - 実機走行や安全評価では戻すべきです。

- `launch_collision_detector:=false`
  - 衝突監視です。
  - AEB と同様、学習初期では後回しにできます。

### すでに off のもの

以下は既定で off です。

- `launch_obstacle_collision_checker:=false`
- `launch_predicted_path_checker:=false`

初期学習ではこのままでよいです。

### 外部指令系について

- `launch_external_cmd_selector`
- `launch_external_cmd_converter`

これらは外部制御指令との接続に関係します。teleop や外部入力を扱わない学習段階では後回しにできます。ただし `control_command_mux` や LSDB interface との接続方針に関係するため、実際に off する場合は `/control/command/*` の流れを確認する必要があります。

## API/RViz の扱い

API は Autoware の操作や状態取得の入口です。初学者が launch 構成だけを読むなら、最初は詳細を後回しにできます。

- `launch_api:=false`
  - API/ADAPI の理解を後回しにする場合の候補です。
  - ただし initial pose、engage、operation mode などを API 経由で扱う場合は必要になります。

RViz は可視化に有用なので、初学者には残す方がよいです。

- `rviz:=true`
  - topic と TF と map/object/trajectory の関係を目で確認できるため、学習向きです。

## 学習用の段階的な簡略案

### Step 1: まずは現在の構成をそのまま読む

最初は `docs/architecture.md` の全体構成に沿って、次の topic だけ追います。

- `/sensing/lidar/concatenated/pointcloud`
- `/localization/kinematic_state`
- `/perception/object_recognition/objects`
- `/perception/obstacle_segmentation/pointcloud`
- `/planning/trajectory`
- `/control/command/control_cmd`
- `/vehicle/status/*`

この段階では module を削らず、複雑な monitoring/validator は「周辺機能」として扱います。

### Step 2: System 監視を後回しにする

学習用には次を検討できます。

```bash
launch_system_monitor:=false
require_rosbag_for_auto:=false
```

さらに単純化したい場合は `launch_system:=false` も候補ですが、operation mode や safety 系の理解が変わるため、topic flow を読む目的に限定します。

### Step 3: Planning のシーン数を減らす

lane driving の主経路を理解したい場合は、以下のような方向で module を減らすと読みやすいです。

```bash
launch_parking_module:=false
launch_remaining_distance_time_calculator:=false
launch_lane_change_right_module:=false
launch_lane_change_left_module:=false
launch_avoidance_by_lane_change_module:=false
launch_side_shift_module:=false
launch_bidirectional_traffic_module:=false
```

これにより、parking、lane change、side shift などの枝を減らし、route から lane driving trajectory までの太い流れに集中できます。

### Step 4: Control/Planning の validator を後回しにする

Control の基本ループに集中するなら、次を検討できます。

```bash
launch_control_evaluator:=false
launch_lane_departure_checker:=false
launch_control_validator:=false
launch_autonomous_emergency_braking:=false
launch_collision_detector:=false
```

Planning 側では、まず checker の詳細理解を後回しにし、実際に off する場合は `/planning/trajectory` の接続が維持されるか確認します。

```bash
launch_latency_checker:=false
launch_intersection_collision_checker:=false
launch_rear_collision_checker:=false
```

## 初学者向けの推奨最小理解セット

最初に読むべき launch は次の順序がよいです。

1. `autoware.launch.xml`
2. `tier4_sensing_component.launch.xml`
3. `palta_sensor_kit_launch/launch/sensing.launch.xml`
4. `tier4_map_component.launch.xml`
5. `tier4_localization_component.launch.xml`
6. `tier4_perception_component.launch.xml`
7. `tier4_planning_component.launch.xml`
8. `tier4_control_component.launch.xml`
9. `tier4_vehicle_launch/launch/vehicle.launch.xml`
10. `palta_launch/launch/vehicle_interface.launch.xml`

最初から各 module の内部 launch を全部読むより、component launch がどの大分類を呼んでいるかを把握してから、必要に応じて中に入る方が理解しやすいです。

## まとめ

Vehicle、Map、Sensing は簡略化しない方がよいです。Localization と Perception も、現在の構成では基本ループに近いため、実際に削るより「内部詳細を後回しにする」方が向いています。

実際に skip 候補が多いのは System、Planning のシーンモジュール、Planning validator、Control checker/evaluator です。初学者向けには、安全監視・診断・評価・特殊シーンをまず周辺機能として扱い、`Sensing -> Localization -> Perception -> Planning -> Control -> Vehicle` の太い流れを先に理解するのが最も読みやすいです。

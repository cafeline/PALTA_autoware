# Autoware Launch Architecture Analysis

## 分析条件

本ドキュメントは、以下のコマンドで起動される構成を静的に分析したものです。ビルド、`ros2 launch` の実行、実機接続確認は行っていません。

```bash
ros2 launch autoware_launch autoware.launch.xml \
  map_path:=PROJECT_ROOT/map/room206_map_data \
  vehicle_model:=palta \
  sensor_model:=palta_sensor_kit \
  pointcloud_map_file:=pointcloud \
  use_lidar_host_time_stamp:=true \
  gnss_enabled:=false \
  rviz_initial_pose_auto_fix_target:=vector_map \
  require_rosbag_for_auto:=false \
  perception_module_preset:=lidar_obstacle_detection_minimal
```

起点は `src/launcher/autoware_launch/autoware_launch/launch/autoware.launch.xml` です。明示指定されていない `launch_*` 引数は既定値の `true` のため、vehicle/system/map/sensing/localization/perception/planning/control/API/RViz はすべて起動対象です。`use_sim_time` は `false`、`planning_module_preset` と `control_module_preset` は `default`、`controller` は空文字のため Control は既定の MPC lateral + PID longitudinal 構成になります。

重要な指定値は次のとおりです。

- `map_path`: `PROJECT_ROOT/map/room206_map_data`
- `pointcloud_map_file`: `pointcloud`
- `lanelet2_map_file`: 既定の `lanelet2_map.osm`
- `vehicle_model`: `palta`
- `sensor_model`: `palta_sensor_kit`
- `use_lidar_host_time_stamp`: `true`
- `gnss_enabled`: `false`
- `require_rosbag_for_auto`: `false`
- `perception_module_preset`: `lidar_obstacle_detection_minimal`
- `rviz_initial_pose_auto_fix_target`: `vector_map`

## 全体構成

処理の主な流れは次のようになります。

1. `autoware.launch.xml` がグローバルパラメータと `pointcloud_container` を作成する。
2. `palta` 車両モデルの URDF と LSDB 車両インターフェースを起動する。
3. `palta_sensor_kit` の 2 台の Hesai LiDAR、Tamagawa IMU、車速変換を `/sensing` 配下で起動する。
4. Map は点群地図、Lanelet2 ベクタ地図、地図投影情報、地図 TF を `/map` 配下で提供する。
5. Localization は LiDAR 点群を前処理し、NDT pose と gyro odom twist を EKF で統合して `/localization/kinematic_state` を出す。
6. Perception は最小 LiDAR 障害物検出プリセットで、地面分離、クラスタリング、追跡、地図ベース予測、占有格子地図を作る。
7. Planning は mission planning、lane driving、parking、velocity smoothing、planning validator を実行し `/planning/trajectory` を出す。
8. Control は Planning trajectory と Localization 状態から制御指令を生成し、gate/mux を経由して `/control/command/*` に出す。
9. Vehicle 側の LSDB interface が `/control/command/*` を左右駆動系のコマンドへ変換する。

## Map

Map は `tier4_map_component.launch.xml` から `tier4_map_launch/launch/map.launch.xml` を呼び出します。

この起動条件で解決される主な地図ファイルは次のとおりです。

- 点群地図: `PROJECT_ROOT/map/room206_map_data/pointcloud`
- 点群メタデータ: `PROJECT_ROOT/map/room206_map_data/pointcloud_map_metadata.yaml`
- Lanelet2 地図: `PROJECT_ROOT/map/room206_map_data/lanelet2_map.osm`
- 投影情報: `PROJECT_ROOT/map/room206_map_data/map_projector_info.yaml`

`map.launch.xml` は `/map` namespace に `map_container` を作り、以下の composable node を起動します。

- `PointCloudMapLoaderNode`: 点群地図を読み込み、`/map/pointcloud_map` と `/map/pointcloud_map_metadata` を提供する。NDT は `/map/get_differential_pointcloud_map` サービスを使う。
- `Lanelet2MapLoaderNode`: Lanelet2 map を読み込み、`/map/vector_map` を提供する。
- `Lanelet2MapVisualizationNode`: RViz 表示向けに `/map/vector_map_marker` を出す。
- `VectorMapTFGeneratorNode`: ベクタ地図から map 系 TF を生成する。
- `map_hash_generator`: 点群地図と Lanelet2 地図のハッシュを生成する。
- `map_projection_loader`: `map_projector_info.yaml` と Lanelet2 map から地図投影情報を読み込む。

Planning は `/map/vector_map` を route/behavior/velocity planning に使い、Localization の NDT は点群地図サービスを使います。Perception の予測も `use_vector_map=true` のため `/map/vector_map` に依存します。

## Localization

Localization は `tier4_localization_component.launch.xml` から `tier4_localization_launch/launch/localization.launch.xml` を呼び出します。既定の `pose_source=ndt`、`twist_source=gyro_odom` が使われ、指定により `gnss_enabled=false` です。

起動される主な処理は次のとおりです。

- `pose_twist_estimator.launch.xml`
  - `ndt_scan_matcher.launch.xml` を起動し、`/localization/util/downsample/pointcloud` と `/map/get_differential_pointcloud_map` を使って `/localization/pose_estimator/pose_with_covariance` を推定する。
  - `gyro_odometer.launch.xml` を起動し、`/sensing/vehicle_velocity_converter/twist_with_covariance` から `/localization/twist_estimator/twist_with_covariance` を生成する。
  - `pose_initializer` を起動する。`gnss_enabled=false` のため automatic pose initializer は起動せず、初期位置は手動指定が基本になる。
  - NDT 用点群前処理として `util.launch.xml` を起動する。
- `util.launch.xml`
  - `CropBoxFilterComponent`、`VoxelGridDownsampleFilterComponent`、`RandomDownsampleFilterComponent` を `pointcloud_container` にロードし、`/sensing/lidar/concatenated/pointcloud` を NDT 用にダウンサンプルする。
- `pose_twist_fusion_filter.launch.xml`
  - `ekf_localizer` が NDT pose と gyro odom twist を統合し、`/localization/pose_twist_fusion_filter/kinematic_state` を生成する。
  - `stop_filter` が最終的な `/localization/kinematic_state` を出す。
  - `twist2accel` が `/localization/acceleration` を出す。
  - `pose_instability_detector` が姿勢推定の不安定性を監視する。
- `localization_error_monitor.launch.xml`
  - `/localization/kinematic_state` を監視する。

この構成では GNSS は初期姿勢推定には使われません。ただし `ndt_scan_matcher.launch.xml` 内には `/sensing/gnss/pose_with_covariance` の regularization 入力が定義されています。指定条件上、`palta_sensor_kit` 側では GNSS launch は含まれていないため、実際にこのトピックが供給されるかは別途確認が必要です。

## Perception

Perception は `perception_module_preset:=lidar_obstacle_detection_minimal` により、通常の `perception.launch.xml` ではなく最小 LiDAR 障害物検出構成を使います。カメラ、レーダー、DNN LiDAR 検出、信号認識のフル構成はこのプリセットでは起動されません。

入力は既定の `/sensing/lidar/concatenated/pointcloud` です。`palta_sensor_kit` は 2 台の Hesai LiDAR を `pointcloud_container` 上で動かし、`PointCloudConcatenateDataSynchronizerComponent` により連結点群を作ります。`use_lidar_host_time_stamp=true` のため、Hesai/Nebula 側の点群 header stamp はホスト時刻を使う設定で渡されます。

起動される主な処理は次のとおりです。

- `perception_lidar_obstacle_detection_minimal.launch.xml`
  - `ground_segmentation.launch.py` を `/perception/obstacle_segmentation` 配下で起動し、入力点群から地面を分離して `/perception/obstacle_segmentation/pointcloud` を生成する。
  - `lidar_rule_detector.launch.xml` を起動し、障害物点群をクラスタリングして `/perception/object_recognition/detection/objects` を生成する。
  - `use_low_height_cropbox` は `tier4_perception_component.launch.xml` の既定で `true`。
- `probabilistic_occupancy_grid_map.launch.xml`
  - `pointcloud_based_occupancy_grid_map` を使い、障害物点群と raw pointcloud から `/perception/occupancy_grid_map/map` を生成する。
  - updater は既定の `binary_bayes_filter`。
- `tracking.launch.xml`
  - `mode=lidar`、`use_radar_tracking_fusion=false`、`use_multi_channel_tracker_merger=false`。
  - `autoware_multi_object_tracker` が `/perception/object_recognition/detection/objects` を追跡し、`/perception/object_recognition/tracking/objects` を出す。
- `prediction.launch.xml`
  - `use_vector_map=true`、`prediction_model_type=map_based`。
  - `/perception/object_recognition/tracking/objects` と `/map/vector_map` を使い、最終的な `/perception/object_recognition/objects` を出す。

Planning と Control への主な出力は次の 3 つです。

- `/perception/object_recognition/objects`
- `/perception/obstacle_segmentation/pointcloud`
- `/perception/occupancy_grid_map/map`

## Planning

Planning は `tier4_planning_component.launch.xml` が `default_preset.yaml` を読み込んだうえで、`tier4_planning_launch/launch/planning.launch.xml` を起動します。入力は `/perception/object_recognition/objects` と `/perception/obstacle_segmentation/pointcloud` です。

`default_preset.yaml` で有効な主なモジュールは次のとおりです。

- Behavior path: static obstacle avoidance、lane change left/right、start planner、side shift、bidirectional traffic。dynamic obstacle avoidance、sampling planner、goal planner、external request lane change は無効。
- Behavior velocity: crosswalk、walkway、traffic light、intersection、blind spot、detection area、virtual traffic light、no stopping area、stop line が有効。roundabout、merge from private、occlusion spot、speed bump、no drivable lane は無効。
- Motion planning: path smoother は `elastic_band`、path planner は `path_optimizer`。
- Motion velocity planner: obstacle stop/slow down/cruise、dynamic obstacle stop、out of lane、obstacle velocity limiter、run out、boundary departure prevention、road user stop が有効。
- Planning validator: latency、trajectory、intersection collision、rear collision checker が有効。
- remaining distance/time calculator は有効。

起動される主な処理は次のとおりです。

- `mission_planning.launch.xml`
  - `mission_planner` と `goal_pose_visualizer` を起動し、route を `/planning/mission_planning/route` として扱う。
- `scenario_planning.launch.xml`
  - `scenario_selector` が lane driving と parking の trajectory を選択する。
  - `external_velocity_limit_selector` と `velocity_smoother` が最終 trajectory を平滑化し、`/planning/scenario_planning/velocity_smoother/trajectory` を生成する。
  - `hazard_lights_selector` を起動する。
  - lane driving と parking を並行して起動する。
- `lane_driving.launch.xml`
  - behavior planning と motion planning を `/planning/scenario_planning/lane_driving` 配下で起動する。
- `behavior_planning.launch.xml`
  - `BehaviorPathPlannerNode` が route、vector map、perception objects、occupancy grid、odometry から `path_with_lane_id` を生成する。
  - `BehaviorVelocityPlannerNode` が traffic signal、dynamic objects、no-ground pointcloud、occupancy grid などを使い、速度制約付き path を生成する。
- `motion_planning.launch.xml`
  - `ElasticBandSmoother` で path を平滑化する。
  - `PathOptimizer` で車両運動に適した trajectory を生成する。
  - `MotionVelocityPlannerNode` が障害物停止、減速、巡航、車線逸脱、boundary departure prevention などの速度計画を適用し、lane driving trajectory を出す。
- `planning_validator.launch.xml`
  - `/planning/scenario_planning/velocity_smoother/trajectory` を検証し、最終的に `/planning/trajectory` を出す。
- `topic_tools relay`
  - `/planning/trajectory` を `/planning/scenario_planning/trajectory` に中継する移行用ノード。

Planning は Map、Localization、Perception の全領域に依存します。特にこの構成では信号認識は最小 Perception プリセットで起動されないため、traffic light 系 behavior velocity module は起動されるものの、信号トピックの供給元は別途必要になる可能性があります。

## Control

Control は `tier4_control_component.launch.xml` が `default_preset.yaml` を読み込んだうえで、`tier4_control_launch/launch/control.launch.xml` を起動します。`controller` は空文字なので `autoware_pure_pursuit` への切り替えは行われず、既定の `trajectory_follower_node`、lateral `mpc`、longitudinal `pid` になります。

主な入力は次のとおりです。

- `/planning/trajectory`
- `/localization/kinematic_state`
- `/localization/acceleration`
- `/vehicle/status/steering_status`
- `/vehicle/status/velocity_status`
- `/perception/object_recognition/objects`
- `/perception/obstacle_segmentation/pointcloud`
- `/map/vector_map`

起動される主な処理は次のとおりです。

- `control_container`
  - `trajectory_follower_node` が `/planning/trajectory`、自己位置、操舵角、加速度から `/control/trajectory_follower/control_cmd` を生成する。
  - `shift_decider` が control command と現在 gear から gear command を生成する。
  - `vehicle_cmd_gate` が自動運転、外部指令、緊急停止、operation mode を調停する。
  - `operation_mode_transition_manager` が autonomous mode に入れるかを判定する。
- `control_check_container`
  - lane departure checker、control validator、AEB、collision detector を起動する。
  - obstacle collision checker と predicted path checker は既定で無効。
- `external_cmd_selector` と `external_cmd_converter`
  - 外部制御指令の選択・変換を行う。
- `control_command_mux.launch.xml`
  - `launch_control_command_mux=true` が `autoware.launch.xml` の既定なので起動される。
  - `vehicle_cmd_gate` の出力は一度 `/control/control_cmd` と `/control/autoware/gear_cmd` に出され、`control_command_mux` が Autoware と teleop 等を調停して `/control/command/*` に再配信する。

この構成で車両インターフェースへ渡る代表的な出力は `/control/command/control_cmd` と `/control/command/gear_cmd` です。

## Vehicle

Vehicle は `tier4_vehicle_launch/launch/vehicle.launch.xml` から起動されます。`vehicle_model=palta`、`sensor_model=palta_sensor_kit` なので、説明系は `palta_description` と `palta_sensor_kit_description`、車両インターフェースは `palta_launch` が使われます。

起動される主な処理は次のとおりです。

- `robot_state_publisher`
  - `tier4_vehicle_launch/urdf/vehicle.xacro` を `vehicle_model:=palta`、`sensor_model:=palta_sensor_kit`、`config_dir:=$(find-pkg-share palta_sensor_kit_description)/config` で展開する。
  - 車両・センサの TF tree を提供する。
- `palta_launch/launch/vehicle_interface.launch.xml`
  - 既定の `mode=can`、`can_device=can0` で LSDB 車両インターフェースを起動する。
  - `ros2_socketcan` の receiver/sender を起動し、`/can0/from_can_bus` と `/can0/to_can_bus` を使う。
  - `dio_ros_driver` を起動する。
  - `/s1/lsdb/left` と `/s1/lsdb/right` に左右の `lsdb_can_interface` を起動する。左は `node_id=2`、右は `node_id=1`。
  - `lsdb_interface` が Autoware 側の制御指令と LSDB 左右モータ指令・状態を接続する。`vehicle_velocity_limit` は `1.67 m/s` です。

`palta_description/config/vehicle_info.param.yaml` の代表値は、wheel radius `0.13 m`、wheel base `0.30 m`、wheel tread `0.33 m`、vehicle height `0.922 m`、max steer angle `1.57 rad` です。これらは Planning/Control/Localization の車両モデルパラメータとして共有されます。

## Sensing

要件の分類では独立項目ではありませんが、Perception と Localization の入力源として重要なためここに整理します。

Sensing は `tier4_sensing_component.launch.xml` から `tier4_sensing_launch/launch/sensing.launch.xml` を呼び出し、`sensor_model=palta_sensor_kit` の場合は `use_lidar_host_time_stamp` を渡して `palta_sensor_kit_launch/launch/sensing.launch.xml` を起動します。

`palta_sensor_kit_launch` の主な構成は次のとおりです。

- `lidar.launch.xml`
  - `/sensing/lidar/lidar1` と `/sensing/lidar/lidar2` を起動する。
  - どちらも `PandarXT32`、`return_mode=Dual`、`rotation_speed=600`、`max_range=120.0`。
  - LiDAR 1 は `frame_id=hesai_lidar_top_link`、既定 IP は sensor `192.168.1.201`、host `192.168.1.100`、data port `2368`。
  - LiDAR 2 は `frame_id=hesai_lidar_front_link`、既定 IP は sensor `192.168.2.201`、host `192.168.2.100`、data port `2369`。
  - `pointcloud_preprocessor.launch.py` が `PointCloudConcatenateDataSynchronizerComponent` を `pointcloud_container` にロードし、`/sensing/lidar/concatenated/pointcloud` を生成する。
- `imu.launch.xml`
  - Tamagawa IMU serial driver を `/sensing/imu/tamagawa` に起動し、`imu_raw` を出す。
  - `autoware_imu_corrector` が `/sensing/imu/imu_data` を生成する。
  - `gyro_bias_estimator` は `/localization/kinematic_state` と `/localization/pose_estimator/pose_with_covariance` も参照する。
- `vehicle_velocity_converter.launch.xml`
  - `/vehicle/status/velocity_status` を `/sensing/vehicle_velocity_converter/twist_with_covariance` に変換する。

## Launch ファイル別要約

| launch ファイル | 役割 |
| --- | --- |
| `autoware_launch/launch/autoware.launch.xml` | 全体の入口。global params、pointcloud container、vehicle/system/map/sensing/localization/perception/planning/control/API/RViz を条件付きで起動する。 |
| `autoware_launch/launch/pointcloud_container.launch.py` | LiDAR/Perception/Localization の composable pointcloud node を載せる共有 container を作る。 |
| `autoware_launch/launch/components/tier4_map_component.launch.xml` | `map_path` 配下の点群地図、Lanelet2 map、投影情報を `tier4_map_launch` に渡す。 |
| `tier4_map_launch/launch/map.launch.xml` | `/map` 配下で点群地図 loader、Lanelet2 loader、visualizer、map TF、map hash、projection loader を起動する。 |
| `autoware_launch/launch/components/tier4_sensing_component.launch.xml` | `sensor_model` に応じて sensing stack を起動し、`palta_sensor_kit` には LiDAR host timestamp 設定を渡す。 |
| `tier4_sensing_launch/launch/sensing.launch.xml` | `/sensing` namespace を作り、センサモデル別の sensing launch を呼ぶ。 |
| `palta_sensor_kit_launch/launch/sensing.launch.xml` | Palta の LiDAR、IMU、車速変換をまとめて起動する。 |
| `palta_sensor_kit_launch/launch/lidar.launch.xml` | 2 台の Hesai PandarXT32 と連結点群生成を起動する。 |
| `palta_sensor_kit_launch/launch/imu.launch.xml` | Tamagawa IMU driver、IMU corrector、gyro bias estimator を起動する。 |
| `palta_sensor_kit_launch/launch/pointcloud_preprocessor.launch.py` | 2 台の LiDAR 点群を同期・連結し、`concatenated/pointcloud` を作る composable node をロードする。 |
| `autoware_launch/launch/components/tier4_localization_component.launch.xml` | Localization のパラメータ群を解決し、pose/twist estimation、fusion、monitor を起動する。 |
| `tier4_localization_launch/launch/localization.launch.xml` | `/localization` 配下で pose_twist_estimator、pose_twist_fusion_filter、localization_error_monitor を起動する。 |
| `tier4_localization_launch/launch/pose_twist_estimator/pose_twist_estimator.launch.xml` | `pose_source=ndt`、`twist_source=gyro_odom` に応じて NDT、gyro odometer、pose initializer、NDT 点群前処理を起動する。 |
| `tier4_localization_launch/launch/pose_twist_estimator/ndt_scan_matcher.launch.xml` | ダウンサンプル点群と点群地図サービスから NDT pose を推定する。 |
| `tier4_localization_launch/launch/pose_twist_estimator/gyro_odometer.launch.xml` | 車速由来 twist を localization twist に変換する。 |
| `tier4_localization_launch/launch/util/util.launch.xml` | NDT 用に crop、voxel downsample、random downsample を行う。 |
| `tier4_localization_launch/launch/pose_twist_fusion_filter/pose_twist_fusion_filter.launch.xml` | EKF、stop filter、twist2accel、pose instability detector を起動する。 |
| `tier4_localization_launch/launch/localization_error_monitor/localization_error_monitor.launch.xml` | localization output の異常を監視する。 |
| `autoware_launch/launch/components/tier4_perception_component.launch.xml` | Perception の起動分岐を行う。指定条件では最小 LiDAR 障害物検出プリセットを選ぶ。 |
| `tier4_perception_launch/launch/perception_lidar_obstacle_detection_minimal.launch.xml` | 地面分離と LiDAR rule detector によるクラスタリングを起動する。 |
| `tier4_perception_launch/launch/occupancy_grid_map/probabilistic_occupancy_grid_map.launch.xml` | 点群ベースの probabilistic occupancy grid map を生成する。 |
| `tier4_perception_launch/launch/object_recognition/tracking/tracking.launch.xml` | LiDAR 検出結果を multi object tracker で追跡する。 |
| `tier4_perception_launch/launch/object_recognition/prediction/prediction.launch.xml` | vector map を使った map based prediction を行い、最終 object topic を出す。 |
| `autoware_launch/launch/components/tier4_planning_component.launch.xml` | Planning preset とパラメータ群を読み込み、planning stack を起動する。 |
| `tier4_planning_launch/launch/planning.launch.xml` | mission planning、scenario planning、planning validator、planning evaluator を起動する。 |
| `tier4_planning_launch/launch/mission_planning/mission_planning.launch.xml` | mission planner と goal pose visualizer を起動する。 |
| `tier4_planning_launch/launch/scenario_planning/scenario_planning.launch.xml` | scenario selector、velocity smoother、hazard lights selector、lane driving、parking を起動する。 |
| `tier4_planning_launch/launch/scenario_planning/lane_driving.launch.xml` | lane driving の behavior planning と motion planning を起動する。 |
| `tier4_planning_launch/launch/scenario_planning/lane_driving/behavior_planning/behavior_planning.launch.xml` | behavior path planner と behavior velocity planner を起動する。 |
| `tier4_planning_launch/launch/scenario_planning/lane_driving/motion_planning/motion_planning.launch.xml` | path smoother、path optimizer、motion velocity planner、必要に応じ surround obstacle checker を起動する。 |
| `autoware_launch/launch/components/tier4_control_component.launch.xml` | Control preset を読み込み、controller 種別、出力 topic、control command mux の有無を決定する。 |
| `tier4_control_launch/launch/control.launch.xml` | trajectory follower、vehicle cmd gate、operation mode transition manager、control checkers、external cmd selector/converter を起動する。 |
| `control_command_mux/launch/control_command_mux.launch.xml` | Autoware と teleop 等の control command を調停し、`/control/command/*` へ出す。 |
| `tier4_vehicle_launch/launch/vehicle.launch.xml` | 車両 URDF の publish と vehicle interface の起動を行う。 |
| `palta_launch/launch/vehicle_interface.launch.xml` | Palta の LSDB CAN/serial interface、socketcan、DIO、左右モータ interface、Autoware interface を起動する。 |
| `lsdb_can_interface/launch/lsdb_can_interface.launch.xml` | LSDB の左右ドライバに対する CAN command/status 変換ノードを起動する。 |
| `ros2_socketcan/launch/socket_can_bridge.launch.xml` | SocketCAN の sender/receiver を起動し、CAN bus と ROS topic を橋渡しする。 |
| `dio_ros_driver/launch/dio_ros_driver.launch.xml` | DIO driver を `/dio` namespace で起動する。 |
| `autoware_launch/launch/components/tier4_system_component.launch.xml` | system monitor、diagnostics、MRM、operation mode 系を起動する。`require_rosbag_for_auto=false` のため rosbag 必須条件は無効。 |
| `autoware_launch/launch/components/tier4_autoware_api_component.launch.xml` | API/ADAPI 系を起動する。RViz 初期姿勢補正には指定された `vector_map` を使う。 |
| `rviz2` node | `autoware.rviz` を開き、Autoware の可視化を行う。 |

## 注意点

- `pointcloud_map_file:=pointcloud` は既定の `pointcloud_map.pcd` ではなく、`map_path/pointcloud` を loader に渡します。この値がファイルかディレクトリかは地図データ側の構成に依存します。
- `gnss_enabled=false` のため、GNSS による automatic pose initializer は起動されません。初期位置は RViz/API 等から与える運用になります。
- 最小 Perception プリセットでは traffic light recognition は起動されません。一方 Planning 側の traffic light module は既定で有効なので、信号トピックを使う運用では供給元を別途確認する必要があります。
- `require_rosbag_for_auto=false` のため、AUTO 遷移時に rosbag node の存在は要求されません。
- 本分析は launch/XML/Python/YAML の静的読解に基づきます。実際の node graph、topic 接続、パラメータ解決、パッケージ解決はビルド・実行時に確認が必要です。

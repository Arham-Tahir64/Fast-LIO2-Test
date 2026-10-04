# Fast-LIO2 ROS 2 workspace

Docker reproduces the working Ubuntu 24.04 / ROS 2 Jazzy setup, including:

- PCL, Eigen, OpenMP (GCC), Python development headers, NumPy, and Matplotlib.
- ROS message generation, PCL integration, TF2, launch tools, RViz2, and SQLite rosbag playback/conversion.
- Livox SDK2 and `livox_ros_driver2`, built from the exact revisions used on the host.
- FAST-LIO2 with the included ikd-Tree sources, `construction_seq2.yaml`, lightweight RViz configuration, and Livox bag preparation script.

The image builds both workspaces and sources ROS, Livox, and FAST-LIO automatically. It does not need the host's ROS installation. Recordings are mounted at runtime rather than copied into the image. These commands use Linux host networking so mapping, playback, and RViz can discover each other.

## Build

From this repository's root:

```bash
sudo docker build -t fastlio2:jazzy .
mkdir -p bags output
```

Build parallelism defaults to two jobs. For a memory-limited machine use `--build-arg BUILD_JOBS=1`. The ROS base and apt packages receive updates; the two Livox source revisions are pinned in the Dockerfile. The image follows the host architecture (ARM64 or AMD64).

## Prepare the construction recording

Skip this step if `bags/construction_seq2_fastlio` already exists. The original recording uses `livox_ros_driver/msg/CustomMsg`; FAST-LIO expects `livox_ros_driver2/msg/CustomMsg`. The helper checks that the message fields match, preserves serialized data and timestamps, and copies only `/livox/lidar` and `/livox/imu`. It requires a source bag with one SQLite `.db3` file and embedded message definitions, and refuses to overwrite an existing destination.

If you need the original dataset (about 10 GB), download it with:

```bash
mkdir -p bags/construction_seq2
curl -fL --retry 3 -C - -o bags/construction_seq2/construction_seq2.db3 \
  https://huggingface.co/datasets/Willyzw/rtk-slam-dataset/resolve/main/ros2/construction_seq2/construction_seq2.db3
curl -fL --retry 3 -o bags/construction_seq2/metadata.yaml \
  https://huggingface.co/datasets/Willyzw/rtk-slam-dataset/resolve/main/ros2/construction_seq2/metadata.yaml
```

Convert inside the image (allow another approximately 2.5 GB of disk space):

```bash
sudo docker run --rm \
  -v "$PWD/bags:/bags" \
  fastlio2:jazzy \
  python3 /opt/fastlio_ws/scripts/prepare_livox_bag.py \
    /bags/construction_seq2 /bags/construction_seq2_fastlio
```

Files created by the container are owned by root. To restore your ownership after conversion:

```bash
sudo chown -R "$(id -u):$(id -g)" bags/construction_seq2_fastlio
```

## Run mapping and playback

Terminal 1 starts mapping with the construction configuration, simulated time, and RViz disabled:

```bash
sudo docker run --rm -it --name fastlio-slam --network host \
  -v "$PWD/output:/output" \
  fastlio2:jazzy
```

Terminal 2 plays the prepared bag at the previously used half speed and publishes `/clock`:

```bash
sudo docker run --rm -it --network host \
  -v "$PWD/bags:/bags:ro" \
  fastlio2:jazzy \
  ros2 bag play /bags/construction_seq2_fastlio --clock --rate 0.5
```

Both containers default to `ROS_DOMAIN_ID=0`. To change it, pass the same `-e ROS_DOMAIN_ID=42` to mapping, playback, and RViz. The construction configuration disables PCD saving; `/output` is available for files you explicitly enable or create.

## View in RViz

On a Linux desktop with an X11 display (including XWayland), open a third terminal:

```bash
xhost +si:localuser:root
sudo docker run --rm -it --network host \
  -e DISPLAY="$DISPLAY" -e QT_X11_NO_MITSHM=1 \
  -e LIBGL_ALWAYS_SOFTWARE=1 \
  -v /tmp/.X11-unix:/tmp/.X11-unix:ro \
  fastlio2:jazzy \
  rviz2 -d /opt/fastlio_ws/install/fast_lio/share/fast_lio/rviz/fastlio_light.rviz \
    --ros-args -p use_sim_time:=true
xhost -si:localuser:root
```

`xhost` comes from the host's `x11-xserver-utils` package. Software rendering avoids a host GPU driver dependency. On a machine without a desktop, use headless mapping and view its topics from another ROS 2 Jazzy machine on the same domain/network.

## Other configurations and live LiDAR

Override the default command for your sensor. Live data uses wall time:

```bash
sudo docker run --rm -it --network host \
  -v "$PWD/output:/output" \
  fastlio2:jazzy \
  ros2 launch fast_lio mapping.launch.py \
    config_file:=mid360.yaml use_sim_time:=false rviz:=false
```

For live Livox hardware, run the included driver in another container using your own network/sensor configuration. The default image command starts mapping; bag replay supplies the recorded sensor topics. To inspect the installed driver launch files or open a shell:

```bash
sudo docker run --rm -it --network host fastlio2:jazzy bash
ls /opt/livox_ws/install/livox_ros_driver2/share/livox_ros_driver2/launch_ROS2
```

Upstream build references: [Livox SDK2](https://github.com/Livox-SDK/Livox-SDK2) and [Livox ROS driver2](https://github.com/Livox-SDK/livox_ros_driver2). The image performs Python message-import and launch-argument checks during its build.

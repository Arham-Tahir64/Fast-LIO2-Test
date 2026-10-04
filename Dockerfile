FROM ros:jazzy-ros-base

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Match the Livox revisions used by the working host installation.
ARG LIVOX_SDK2_COMMIT=c0796f04c143143899c87a773d9f6b7136453c0b
ARG LIVOX_DRIVER2_COMMIT=21445540f0d100dc86a7e6df312dd70bbdb4afdf
ARG BUILD_JOBS=2

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake git ca-certificates curl pkg-config \
    libapr1-dev libeigen3-dev libpcl-dev libgl1-mesa-dri \
    python3-dev python3-numpy python3-matplotlib python3-colcon-common-extensions \
    ros-jazzy-ament-cmake-auto ros-jazzy-rosidl-default-generators \
    ros-jazzy-rosidl-default-runtime ros-jazzy-common-interfaces \
    ros-jazzy-rclcpp-components ros-jazzy-pcl-ros ros-jazzy-pcl-conversions \
    ros-jazzy-tf2 ros-jazzy-launch-ros ros-jazzy-rviz2 \
    ros-jazzy-rosbag2 ros-jazzy-rosbag2-py \
    ros-jazzy-rosbag2-storage-default-plugins \
    && rm -rf /var/lib/apt/lists/*

RUN git init /opt/Livox-SDK2 \
    && git -C /opt/Livox-SDK2 remote add origin https://github.com/Livox-SDK/Livox-SDK2.git \
    && git -C /opt/Livox-SDK2 fetch --depth 1 origin "${LIVOX_SDK2_COMMIT}" \
    && git -C /opt/Livox-SDK2 checkout --detach FETCH_HEAD \
    && cmake -S /opt/Livox-SDK2 -B /opt/Livox-SDK2/build -DCMAKE_BUILD_TYPE=Release \
    && cmake --build /opt/Livox-SDK2/build --parallel "${BUILD_JOBS}" \
    && cmake --install /opt/Livox-SDK2/build \
    && ldconfig \
    && rm -rf /opt/Livox-SDK2

# Prepare the same ROS2 package selection as upstream build.sh jazzy,
# then use colcon directly to cap parallelism and disable upstream lint tests.
RUN git init /opt/livox_ws/src/livox_ros_driver2 \
    && git -C /opt/livox_ws/src/livox_ros_driver2 remote add origin https://github.com/Livox-SDK/livox_ros_driver2.git \
    && git -C /opt/livox_ws/src/livox_ros_driver2 fetch --depth 1 origin "${LIVOX_DRIVER2_COMMIT}" \
    && git -C /opt/livox_ws/src/livox_ros_driver2 checkout --detach FETCH_HEAD \
    && cp /opt/livox_ws/src/livox_ros_driver2/package_ROS2.xml /opt/livox_ws/src/livox_ros_driver2/package.xml \
    && source /opt/ros/jazzy/setup.bash \
    && cd /opt/livox_ws \
    && CMAKE_BUILD_PARALLEL_LEVEL="${BUILD_JOBS}" colcon build --executor sequential \
        --cmake-args -DROS_EDITION=ROS2 -DDISTRO_ROS=jazzy \
        -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
    && rm -rf build log src

WORKDIR /opt/fastlio_ws
COPY src/ ./src/
COPY scripts/ ./scripts/

RUN source /opt/ros/jazzy/setup.bash \
    && source /opt/livox_ws/install/setup.bash \
    && CMAKE_BUILD_PARALLEL_LEVEL="${BUILD_JOBS}" colcon build --executor sequential \
        --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
    && rm -rf build log \
    && mkdir -p /bags /output

COPY docker/entrypoint.sh /usr/local/bin/fastlio-entrypoint
RUN chmod +x /usr/local/bin/fastlio-entrypoint \
    && /usr/local/bin/fastlio-entrypoint python3 -c \
        'import rosbag2_py; from livox_ros_driver2.msg import CustomMsg; from ament_index_python.packages import get_package_share_directory; print(get_package_share_directory("fast_lio"))' \
    && /usr/local/bin/fastlio-entrypoint ros2 launch fast_lio mapping.launch.py --show-args

ENV ROS_DOMAIN_ID=0
WORKDIR /output
ENTRYPOINT ["/usr/local/bin/fastlio-entrypoint"]
CMD ["ros2", "launch", "fast_lio", "mapping.launch.py", "config_file:=construction_seq2.yaml", "use_sim_time:=true", "rviz:=false"]

#!/usr/bin/env python3
"""Copy a Livox ROS 2 bag's LiDAR/IMU data for use with livox_ros_driver2.

Run with ROS Jazzy and livox_ros_driver2 sourced. The source bag is read-only.
Only the package name changes; serialized messages and timestamps are retained.
"""

import argparse
import json
import sqlite3
from pathlib import Path

import rosbag2_py
from ament_index_python.packages import get_package_share_directory
from livox_ros_driver2.msg import CustomMsg
from rclpy.serialization import deserialize_message


def fields(text):
    return [" ".join(line.split("#", 1)[0].split()) for line in text.splitlines()
            if line.split("#", 1)[0].strip()]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    if args.destination.exists():
        parser.error("destination already exists; choose a new directory")

    source_files = list(args.source.glob("*.db3"))
    if len(source_files) != 1:
        parser.error("this helper expects a source bag with one .db3 file")
    share = Path(get_package_share_directory("livox_ros_driver2"))
    with sqlite3.connect(source_files[0].resolve().as_uri() + "?mode=ro", uri=True) as db:
        row = db.execute(
            "SELECT encoded_message_definition FROM message_definitions "
            "WHERE topic_type = ?", ("livox_ros_driver/msg/CustomMsg",)
        ).fetchone()
    if row is None:
        raise ValueError("source does not contain the old Livox CustomMsg definition")
    sections = row[0].split("=" * 80 + "\n")
    source_msg = fields(sections[0])
    source_point = fields(next(section.split("\n", 1)[1] for section in sections
                               if section.startswith("MSG: livox_ros_driver/CustomPoint\n")))
    target_msg = fields((share / "msg/CustomMsg.msg").read_text())
    target_msg = [line.replace("CustomPoint[]", "livox_ros_driver/CustomPoint[]")
                  for line in target_msg]
    if source_msg != target_msg or source_point != fields((share / "msg/CustomPoint.msg").read_text()):
        raise ValueError("source and installed Livox message fields differ")

    description = json.loads((share / "msg/CustomMsg.json").read_text())
    target_hash = next(entry["hash_string"] for entry in description["type_hashes"]
                       if entry["type_name"] == "livox_ros_driver2/msg/CustomMsg")
    reader = rosbag2_py.SequentialReader()
    reader.open(rosbag2_py.StorageOptions(uri=str(args.source), storage_id="sqlite3"),
                rosbag2_py.ConverterOptions("", ""))
    topics = {topic.name: topic for topic in reader.get_all_topics_and_types()}
    expected = {"/livox/lidar": "livox_ros_driver/msg/CustomMsg",
                "/livox/imu": "sensor_msgs/msg/Imu"}
    for name, message_type in expected.items():
        if name not in topics or topics[name].type != message_type:
            raise ValueError(f"unexpected source topic/type for {name}")
    reader.set_filter(rosbag2_py.StorageFilter(topics=list(expected)))
    writer = rosbag2_py.SequentialWriter()
    writer.open(rosbag2_py.StorageOptions(uri=str(args.destination), storage_id="sqlite3",
                                         max_cache_size=64 * 1024 * 1024),
                rosbag2_py.ConverterOptions("", ""))
    for name in expected:
        topic = topics[name]
        if name == "/livox/lidar":
            topic.type = "livox_ros_driver2/msg/CustomMsg"
            topic.type_description_hash = target_hash
        writer.create_topic(topic)

    counts = dict.fromkeys(expected, 0)
    while reader.has_next():
        name, data, timestamp = reader.read_next()
        if name == "/livox/lidar" and counts[name] % 1000 == 0:
            message = deserialize_message(data, CustomMsg)
            # CDR padding bytes can change on reserialization even when every
            # field is identical. Keep the original bytes; validate decoding.
            if len(message.points) != message.point_num:
                raise ValueError("LiDAR CDR validation failed")
        writer.write(name, data, timestamp)
        counts[name] += 1
        if sum(counts.values()) % 20000 == 0:
            print(f"Copied {sum(counts.values())} messages", flush=True)
    writer.close()
    reader.close()
    print(f"Created {args.destination}: {counts}")


if __name__ == "__main__":
    main()

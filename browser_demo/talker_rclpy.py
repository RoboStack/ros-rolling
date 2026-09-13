import rclpy
from rclpy.node import Node
from rclpy.event_handler import PublisherEventCallbacks
from std_msgs.msg import String

print("talker_rclpy: rclpy.init()", flush=True)
rclpy.init(args=[])

# start_parameter_services=False: the parameter get/set/list services pull in
# service_msgs.ServiceEventInfo's service-introspection "_Event" type, which
# hits the still-unpatched rosidl_typesupport_microxrcedds_cpp codegen gap
# (see rclpy_boot.c for the microxrcedds_c-only workaround used elsewhere).
# Not needed for a plain talker.
node = Node('wasm_rclpy_talker', enable_rosout=False, start_parameter_services=False)

# rmw_zenoh_pico doesn't support QoS event handlers (RCL_PUBLISHER_OFFERED_
# INCOMPATIBLE_QOS etc.) -- it fails with a plain RCLError instead of the
# UnsupportedEventTypeError rclpy's own create_event_handlers() already
# catches and ignores, so the default callback has to be turned off
# explicitly. The same fix is applied to the internal /parameter_events
# publisher via a local rclpy/node.py patch (see demo_env/README).
pub = node.create_publisher(
    String, 'chatter_rclpy', 10,
    event_callbacks=PublisherEventCallbacks(use_default_callbacks=False))

count = [0]


def timer_cb():
    msg = String()
    msg.data = 'hello from rclpy wasm32 #%d' % count[0]
    pub.publish(msg)
    print('talker_rclpy: published:', msg.data, flush=True)
    count[0] += 1


node.create_timer(1.0, timer_cb)
rclpy.spin(node)

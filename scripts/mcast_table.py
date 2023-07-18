mgid = bfrt.pre.mgid
node = bfrt.pre.node

node.add(MULTICAST_NODE_ID=24,DEV_PORT=[24,68])
node.add(MULTICAST_NODE_ID=25,DEV_PORT=[40,52])

node.add(MULTICAST_NODE_ID=40,DEV_PORT=[40,68])
node.add(MULTICAST_NODE_ID=41,DEV_PORT=[24,52])

node.add(MULTICAST_NODE_ID=52,DEV_PORT=[52,68])
node.add(MULTICAST_NODE_ID=53,DEV_PORT=[24,40])

mgid.add(MGID=24,MULTICAST_NODE_ID=[24],MULTICAST_NODE_L1_XID=[25],MULTICAST_NODE_L1_XID_VALID=[False])
mgid.add(MGID=40,MULTICAST_NODE_ID=[40],MULTICAST_NODE_L1_XID=[41],MULTICAST_NODE_L1_XID_VALID=[False])
mgid.add(MGID=52,MULTICAST_NODE_ID=[52],MULTICAST_NODE_L1_XID=[53],MULTICAST_NODE_L1_XID_VALID=[False])

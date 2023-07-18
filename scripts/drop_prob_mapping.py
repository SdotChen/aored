table = bfrt.ao_red.pipe.Egress.map_qdepth_to_prob_t

# Params to adjust
max_ratio = 0.1
min_ratio = max_ratio / 3

default_max_qdepth = 24254
MAX = 65535

min_th = int(min_ratio * default_max_qdepth)
max_th = int(max_ratio * default_max_qdepth)

for i in range(0,min_th-1):
	table.add_with_map_qdepth_to_prob(qdepth_for_match=i,prob=0)

for i in range(0,65535):
	start = int(min_th + (max_th - min_th) * i / MAX)
	end = int(min_th + (max_th - min_th) * (i+1) / MAX)
	for j in range(start,end):
		table.add_with_map_qdepth_to_prob(qdepth_for_match=j,prob=i)


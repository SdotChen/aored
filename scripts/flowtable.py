import ipaddress

server_ip_start = ipaddress.IPv4Address('6.6.241.1')
server_ip_end = ipaddress.IPv4Address('6.6.241.8')

tput_ip_start = ipaddress.IPv4Address('6.6.241.31')
tput_ip_end = ipaddress.IPv4Address('6.6.241.230')

cps_ip_start = ipaddress.IPv4Address('6.6.241.11')
cps_ip_end = ipaddress.IPv4Address('6.6.241.30')

table = bfrt.ao_red.pipe.Ingress.multicast_t

for ip in range(int(server_ip_start),int(server_ip_end)+1):
	table.add_with_multicast(ip,24)

for ip in range(int(tput_ip_start),int(tput_ip_end)+1):
	table.add_with_multicast(ip,40)

for ip in range(int(cps_ip_start),int(cps_ip_end)+1):
	table.add_with_multicast(ip,52)


/* -*- P4_16 -*- */

#include <core.p4>
#include <tna.p4>

/*************************************************************************
 ************* C O N S T A N T S    A N D   T Y P E S  *******************
**************************************************************************/
#define POWER 0
#define FREQ 1 << POWER
#define RECIRC_PORT 68
#define WQ 9
/*************************************************************************
 ***********************  H E A D E R S  *********************************
 *************************************************************************/

/*  Define all the headers the program will recognize             */
/*  The actual sets of headers processed by each gress can differ */

/* Standard ethernet header */
header ethernet_h {
    bit<48>   dst_addr;
    bit<48>   src_addr;
    bit<16>   ether_type;
}

header ipv4_h {
    bit<4>   version;
    bit<4>   ihl;
    bit<8>   diffserv;
    bit<16>  total_len;
    bit<16>  identification;
    bit<3>   flags;
    bit<13>  frag_offset;
    bit<8>   ttl;
    bit<8>   protocol;
    bit<16>  hdr_checksum;
    bit<32>  src_addr;
    bit<32>  dst_addr;
}

header udp_h {
    bit<16>  src_port;
    bit<16>  dst_port;
    bit<16>  len;
    bit<16>  checksum;
}

header p4_header_h {
	bit<32>	 delay;
	bit<32>	 depth;
	bit<32>	 recirc;
	bit<7>	 pad2;
	bit<9>	 egress_port;
	bit<16>	 drop_prob;
	bit<32>	 aver_qdepth;
	bit<8>	 color;
}

struct dual_32 {
	bit<32> val1;
	bit<32> val2;
}
/*************************************************************************
 **************  I N G R E S S   P R O C E S S I N G   *******************
 *************************************************************************/
 
    /***********************  H E A D E R S  ************************/

struct my_ingress_headers_t {
    ethernet_h   ethernet;
    ipv4_h       ipv4;
	udp_h		 udp;
    p4_header_h  p4_header;
}

    /******  G L O B A L   I N G R E S S   M E T A D A T A  *********/

struct my_ingress_metadata_t {
	bit<16>	 rndnum;
	bit<16>  drop_prob;
	bit<16>  diff;
}

    /***********************  P A R S E R  **************************/
parser IngressParser(packet_in        pkt,
    /* User */    
    out my_ingress_headers_t          hdr,
    out my_ingress_metadata_t         meta,
    /* Intrinsic */
    out ingress_intrinsic_metadata_t  ig_intr_md)
{
    /* This is a mandatory state, required by Tofino Architecture */
    state start {
        pkt.extract(ig_intr_md);
        pkt.advance(PORT_METADATA_SIZE);
        transition meta_init;
    }

	state meta_init {
		meta.rndnum = 0;
		meta.drop_prob = 0;
		meta.diff = 0;
		transition parse_ethernet;
	}

    state parse_ethernet {
        pkt.extract(hdr.ethernet);
        transition parse_ipv4;
    }

    state parse_ipv4 {
        pkt.extract(hdr.ipv4);
        transition select(hdr.ipv4.protocol) {
			0x11:		parse_udp;
			default:	accept;
		}
    }

	state parse_udp {
		pkt.extract(hdr.udp);
		transition parse_p4_header;
	}

	state parse_p4_header {
		pkt.extract(hdr.p4_header);
		transition accept;
	}
}

    /***************** M A T C H - A C T I O N  *********************/

control Ingress(
    /* User */
    inout my_ingress_headers_t                       hdr,
    inout my_ingress_metadata_t                      meta,
    /* Intrinsic */
    in    ingress_intrinsic_metadata_t               ig_intr_md,
    in    ingress_intrinsic_metadata_from_parser_t   ig_prsr_md,
    inout ingress_intrinsic_metadata_for_deparser_t  ig_dprsr_md,
    inout ingress_intrinsic_metadata_for_tm_t        ig_tm_md)
{

	Random<bit<16>>() rnd;
	Meter<bit<9>>(512,MeterType_t.BYTES) aqm_meter;

    action multicast(bit<9> port){
	    ig_tm_md.mcast_grp_a = (bit<16>)port;
		hdr.p4_header.egress_port = port;
    }

	action drop(){
		ig_dprsr_md.drop_ctl = 1;
	}

	@stage(0)
	table drop_recirc_t {
		actions = { drop;}
		default_action = drop();
		size = 1;
	}

    @stage(0)
    table multicast_t {
		key = { hdr.ipv4.dst_addr: exact;}
	    actions = { multicast; }
	    size = 512;
    }

	action set_p4_header() {
		hdr.p4_header.delay = ig_prsr_md.global_tstamp[31:0];
		hdr.p4_header.depth = 0;
		hdr.p4_header.recirc = 0;
		hdr.p4_header.color = 0;
		hdr.p4_header.pad2 = 0;
		hdr.p4_header.drop_prob = 0;
		hdr.p4_header.aver_qdepth = 0;
    }

    @stage(1)
    table set_p4_header_t {
        actions = {set_p4_header;}
        default_action = set_p4_header();
        size = 1;
    }

	action set_meter() {
		hdr.p4_header.color = aqm_meter.execute(hdr.p4_header.egress_port);
	}

	@stage(1)
	table set_meter_t {
		actions = { set_meter;}
		default_action = set_meter();
		size = 1;
	}

	Register<bit<16>,bit<9>>(512) reg_drop_prob;
	RegisterAction<bit<16>,bit<9>,bit<16>>(reg_drop_prob) _set_drop_prob = {
		void apply(inout bit<16> reg_data) {
			reg_data = hdr.p4_header.drop_prob;
		}
	};
	RegisterAction<bit<16>,bit<9>,bit<16>>(reg_drop_prob) _get_drop_prob = {
		void apply(inout bit<16> reg_data, out bit<16> result) {
			result = reg_data;
		}
	};
	
	action set_drop_prob() {
		_set_drop_prob.execute(hdr.p4_header.egress_port);
	}

	@stage(2)
	table set_drop_prob_t {
		actions = { set_drop_prob;}
		default_action = set_drop_prob();
		size = 1;
	}

	action get_drop_prob() {
		meta.drop_prob = _get_drop_prob.execute(hdr.p4_header.egress_port);
	}

	@stage(2)
	table get_drop_prob_t {
		actions = { get_drop_prob;}
		default_action = get_drop_prob();
		size = 1;
	}
	
	action get_rndnum(){
		meta.rndnum = rnd.get();
	}

	@stage(4)
	table get_rndnum_t {
		actions = {get_rndnum;}
		default_action = get_rndnum();
		size = 1;
	}

	action get_diff(){
		meta.diff = (bit<16>)meta.rndnum |-| meta.drop_prob;
	}

	@stage(5)
	table get_diff_t {
		actions = { get_diff;}
		default_action = get_diff();
		size = 1;
	}

	@stage(7)
	table drop_t {
		actions = {drop;}
		default_action = drop();
		size = 1;
	}

	Register<bit<32>,bit<9>>(512) reg_seq_recirc;
	RegisterAction<bit<32>,bit<9>,bit<32>>(reg_seq_recirc) _get_seq_recirc = {
		void apply(inout bit<32> reg_data, out bit<32> result) {
			result = reg_data;
		}
	};
	RegisterAction<bit<32>,bit<9>,bit<32>>(reg_seq_recirc) _set_seq_recirc = {
		void apply(inout bit<32> reg_data) {
			reg_data = reg_data + 1;
		}
	};

	action get_seq_recirc() {
		hdr.p4_header.recirc = _get_seq_recirc.execute(hdr.p4_header.egress_port);
	}

	@stage(3)
	table get_seq_recirc_t {
		actions = { get_seq_recirc;}
		default_action = get_seq_recirc();
		size = 1;
	}

	action set_seq_recirc() {
		_set_seq_recirc.execute(hdr.p4_header.egress_port);
	}

	@stage(3)
	table set_seq_recirc_t {
		actions = { set_seq_recirc;}
		default_action = set_seq_recirc();
		size = 1;
	}

	Register<bit<32>,bit<9>>(512) reg_aver_qdepth;
	RegisterAction<bit<32>,bit<9>,bit<32>>(reg_aver_qdepth) _get_aver_qdepth = {
		void apply(inout bit<32> reg_data, out bit<32> result) {
			result = reg_data;
		}
	};
	RegisterAction<bit<32>,bit<9>,bit<32>>(reg_aver_qdepth) _set_aver_qdepth = {
		void apply(inout bit<32> reg_data) {
			reg_data = hdr.p4_header.aver_qdepth;
		}
	};
	
	action get_aver_qdepth() {
		hdr.p4_header.aver_qdepth = _get_aver_qdepth.execute(hdr.p4_header.egress_port);
	}

	@stage(3)
	table get_aver_qdepth_t {
		actions = { get_aver_qdepth;}
		default_action = get_aver_qdepth();
		size = 1;
	}

	action set_aver_qdepth() {
		_set_aver_qdepth.execute(hdr.p4_header.egress_port);
	}

	@stage(3)
	table set_aver_qdepth_t {
		actions = { set_aver_qdepth;}
		default_action = set_aver_qdepth();
		size = 1;
	}

    apply {
		/*
			To check if a packet is from regular port or recirculate port.
		*/
        if(ig_intr_md.ingress_port == RECIRC_PORT) {
			drop_recirc_t.apply();
		} else {
			multicast_t.apply(); // stage 0
			set_p4_header_t.apply(); // stage 1
			set_meter_t.apply(); // stage 1
		}
  
		/*
			If a packet is from regular port, read the values from registers.
			If a packet is from recirculate port, write the values to registers.
		*/
		if(ig_intr_md.ingress_port == RECIRC_PORT) {
			set_drop_prob_t.apply(); // stage 2
			set_seq_recirc_t.apply(); // stage 3
			set_aver_qdepth_t.apply(); // stage 3
		} else {
			get_drop_prob_t.apply(); // stage 2
			get_seq_recirc_t.apply(); // stage 3
			get_aver_qdepth_t.apply(); // stage 3
		}

		// Only for packets from regular port.
		if(hdr.p4_header.color[1:1] == 1) {
			get_rndnum_t.apply(); // stage 4
			get_diff_t.apply(); // stage 5
			
			if(meta.diff == 0){
				drop_t.apply(); // stage 7				
			} 
		} 
    }
}

    /*********************  D E P A R S E R  ************************/

control IngressDeparser(packet_out pkt,
    /* User */
    inout my_ingress_headers_t                       hdr,
    in    my_ingress_metadata_t                      meta,
    /* Intrinsic */
    in    ingress_intrinsic_metadata_for_deparser_t  ig_dprsr_md)
{
    apply {
        pkt.emit(hdr);
    }
}


/*************************************************************************
 ****************  E G R E S S   P R O C E S S I N G   *******************
 *************************************************************************/

    /***********************  H E A D E R S  ************************/

struct my_egress_headers_t {
	ethernet_h	ethernet;
	ipv4_h		ipv4;
	udp_h		udp;
	p4_header_h	p4_header;
}

    /********  G L O B A L   E G R E S S   M E T A D A T A  *********/

struct my_egress_metadata_t {
	bit<32> sum_qdepth;
	bit<32>	weighted_qdepth;
	bit<2>	option;
	bit<32> num_writer;
	bit<32> num_reader;
	bit<1>	drop_recirc;
	bit<32>	aver_qdepth;
	bit<16>	qdepth_for_match;
}

    /***********************  P A R S E R  **************************/

parser EgressParser(packet_in        pkt,
    /* User */
    out my_egress_headers_t          hdr,
    out my_egress_metadata_t         meta,
    /* Intrinsic */
    out egress_intrinsic_metadata_t  eg_intr_md)
{
    /* This is a mandatory state, required by Tofino Architecture */
    state start {
        pkt.extract(eg_intr_md);
		pkt.extract(hdr.ethernet);
		pkt.extract(hdr.ipv4);
		transition meta_init;		
    }

	state meta_init {
		meta.sum_qdepth = 0;
		meta.weighted_qdepth = 0;
		meta.option = 0;
		meta.num_reader = 0;
		meta.num_writer = 0;
		meta.drop_recirc = 0;
		meta.aver_qdepth = 0;
		meta.qdepth_for_match = 0;
		transition select(hdr.ipv4.protocol) {
			0x11:		parse_udp;
			default:	accept;
		}
	}

	state parse_udp {
		pkt.extract(hdr.udp);
		transition parse_p4_header;
	}

    state parse_p4_header {
		pkt.extract(hdr.p4_header);
        transition accept;
    }
}

    /***************** M A T C H - A C T I O N  *********************/

control Egress(
    /* User */
    inout my_egress_headers_t                          hdr,
    inout my_egress_metadata_t                         meta,
    /* Intrinsic */    
    in    egress_intrinsic_metadata_t                  eg_intr_md,
    in    egress_intrinsic_metadata_from_parser_t      eg_prsr_md,
    inout egress_intrinsic_metadata_for_deparser_t     eg_dprsr_md,
    inout egress_intrinsic_metadata_for_output_port_t  eg_oport_md)
{
	
	action mod_dst_mac(bit<48> dst_addr){
		hdr.ethernet.dst_addr = dst_addr;
	}

	@stage(0)
	table mod_dst_mac_t {
		key = {eg_intr_md.egress_port: exact;}
		actions = { mod_dst_mac;}
		size = 512;
	}

	action mod_header() {
		hdr.p4_header.depth = (bit<13>)0 ++ eg_intr_md.enq_qdepth;
		hdr.p4_header.delay = (bit<32>)(eg_prsr_md.global_tstamp[31:0] - hdr.p4_header.delay);
	}

	@stage(0)
	table mod_header_t {
		actions = { mod_header;}
		default_action = mod_header();
		size = 1;
	}

	Register<bit<32>,bit<9>>(512) reg_process;
	RegisterAction<bit<32>,bit<9>,bit<2>>(reg_process) _process = {
		void apply(inout bit<32> reg_data, out bit<2> result) {
			if(eg_intr_md.egress_port != RECIRC_PORT) {
				if(reg_data >= FREQ) {
					reg_data = 1;
					result = 0;
				} else {
					reg_data = reg_data + 1;
					result = 2;
				}
			} else {
				result = 1;
			}
		}
	};

	action process() {
		meta.option = _process.execute(hdr.p4_header.egress_port);
	}

	@stage(1)
	table process_t {
		actions = { process;}
		default_action = process();
		size = 1;
	}

	Register<bit<32>,bit<9>>(512) reg_writer;
	RegisterAction<bit<32>,bit<9>,bit<32>>(reg_writer) _set_writer = {
		void apply(inout bit<32> reg_data) {
			if(meta.option == 0) {
				reg_data = reg_data + 1;
			}
		}
	};
	RegisterAction<bit<32>,bit<9>,bit<32>>(reg_writer) _get_writer = {
		void apply(inout bit<32> reg_data, out bit<32> result) {
			result = reg_data;
		}
	};

	action set_writer() {
		_set_writer.execute(hdr.p4_header.egress_port);
	}

	@stage(2)
	table set_writer_t {
		actions = { set_writer;}
		default_action = set_writer();
		size = 1;
	}

	action get_writer() {
		meta.num_writer = _get_writer.execute(hdr.p4_header.egress_port);
	}

	@stage(2)
	table get_writer_t {
		actions = { get_writer;}
		default_action = get_writer();
		size = 1;
	}

	Register<bit<32>,bit<9>>(512) reg_reader;
	RegisterAction<bit<32>,bit<9>,bit<1>>(reg_reader) _get_and_set_reader = {
		void apply(inout bit<32> reg_data, out bit<1> result) {
			if(reg_data < meta.num_writer) {
				reg_data = reg_data + 1;
				result = 0;
			} else {
				reg_data = meta.num_writer;
				result = 1;
			}
		}
	};

	action get_and_set_reader() {
		meta.drop_recirc = _get_and_set_reader.execute(hdr.p4_header.egress_port);
	}

	@stage(3)
	table get_and_set_reader_t {
		actions = { get_and_set_reader;}
		default_action = get_and_set_reader();
		size = 1;
	}

	Register<bit<32>,bit<9>>(512) reg_sum_qdepth;
	RegisterAction<bit<32>,bit<9>,bit<32>>(reg_sum_qdepth) _get_and_set_sum_qdepth = {
		void apply(inout bit<32> reg_data, out bit<32> result) {
			result = reg_data;
			if(meta.option == 0) {
				reg_data = hdr.p4_header.depth;
			} else if(meta.option == 2) {
				reg_data = reg_data + hdr.p4_header.depth;
			}
		}
	};

	action get_and_set_sum_qdepth() {
		meta.sum_qdepth = _get_and_set_sum_qdepth.execute(hdr.p4_header.egress_port);
	}

	@stage(3)
	table get_and_set_sum_qdepth_t {
		actions = { get_and_set_sum_qdepth;}
		default_action = get_and_set_sum_qdepth();
		size = 1;
	}

	action get_aver_qdepth() {
		meta.aver_qdepth = meta.sum_qdepth >> POWER;
	}

	@stage(4)
	table get_aver_qdepth_t {
		actions = { get_aver_qdepth;}
		default_action = get_aver_qdepth();
		size = 1;
	}

	action get_weighted_qdepth() {
		meta.weighted_qdepth = meta.aver_qdepth >> WQ;
	}

	@stage(5)
	table get_weighted_qdepth_t {
		actions = { get_weighted_qdepth;}
		default_action = get_weighted_qdepth();
		size = 1;
	}

	MathUnit< bit<32> > (false, 0, -8,
		{0xf0, 0xe0, 0xd0, 0xc0,
		0xb0, 0xa0, 0x90, 0x80,
		0x0, 0x0, 0x0, 0x0,
		0x0, 0x0, 0x0, 0x0}) coeff;
	
	Register<dual_32,bit<9>>(512) reg_aver_qdepth;
	RegisterAction<dual_32,bit<9>,bit<32>>(reg_aver_qdepth) _set_qdepth = {
		void apply(inout dual_32 reg_data) {
			if(meta.option == 0) {
				reg_data.val2 = meta.weighted_qdepth;
			}
		}
	};
	RegisterAction<dual_32,bit<9>,bit<32>>(reg_aver_qdepth) _get_qdepth = {
		void apply(inout dual_32 reg_data, out bit<32> result) {
			reg_data.val1 = reg_data.val2 + coeff.execute(reg_data.val1);
			result = reg_data.val1;
		}
	};

	action set_qdepth() {
		_set_qdepth.execute(hdr.p4_header.egress_port);
	}

	@stage(6)
	table set_qdepth_t {
		actions = { set_qdepth;}
		default_action = set_qdepth();
		size = 1;
	}

	action get_ewma() {
		hdr.p4_header.aver_qdepth = _get_qdepth.execute(hdr.p4_header.egress_port);
	}

	@stage(6)
	table get_ewma_t {
		actions = { get_ewma;}
		default_action = get_ewma();
		size = 1;
	}

	action get_qdepth() {
		hdr.p4_header.aver_qdepth = hdr.p4_header.aver_qdepth << WQ;
		meta.qdepth_for_match = (hdr.p4_header.aver_qdepth << WQ)[15:0];
	}

	@stage(7)
	table get_qdepth_t {
		actions = { get_qdepth;}
		default_action = get_qdepth();
		size = 1;
	}

	action map_qdepth_to_prob(bit<16> prob){
		hdr.p4_header.drop_prob = prob;
	}

	@stage(8)
	table map_qdepth_to_prob_t {
		//key = {meta.qdepth_for_match: range;}
		key = {meta.qdepth_for_match: exact;}
		//key = { hdr.p4_header.aver_qdepth: range;}
		actions = { map_qdepth_to_prob;}
		default_action = map_qdepth_to_prob(65535);
		size = 65536;
	}

	apply {
		
		mod_dst_mac_t.apply(); // stage 0 
		mod_header_t.apply(); // stage 0

		process_t.apply(); // stage 1
		if(meta.option % 2 == 0) {
			set_writer_t.apply(); // stage 2
			get_and_set_sum_qdepth_t.apply(); // stage 3
			get_aver_qdepth_t.apply(); // stage 4
			get_weighted_qdepth_t.apply(); // stage 5
			set_qdepth_t.apply(); // stage 6
		} else {
			// recirc pkts
			get_writer_t.apply(); // stage 2
			get_and_set_reader_t.apply(); // stage 3
			if(meta.drop_recirc == 1) {
				eg_dprsr_md.drop_ctl = 1;
				exit;
			} else {
				get_ewma_t.apply(); // stage 6
				get_qdepth_t.apply(); // stage 7
				map_qdepth_to_prob_t.apply(); // stage 8
			}
		}
	}
}

    /*********************  D E P A R S E R  ************************/

control EgressDeparser(packet_out pkt,
    /* User */
    inout my_egress_headers_t                       hdr,
    in    my_egress_metadata_t                      meta,
    /* Intrinsic */
    in    egress_intrinsic_metadata_for_deparser_t  eg_dprsr_md)
{
    apply {
        pkt.emit(hdr);
    }
}


/************ F I N A L   P A C K A G E ******************************/
Pipeline(
    IngressParser(),
    Ingress(),
    IngressDeparser(),
    EgressParser(),
    Egress(),
    EgressDeparser()
) pipe;

Switch(pipe) main;

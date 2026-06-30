package tbus_pkg;
    // master -> slave
    typedef struct packed {
        logic valid;
        logic write;
        logic [31:0] addr;
        logic [31:0] wdata;
        logic [3:0] be;
    } req_t;

    // slave -> master
    typedef struct packed {
        logic ack;
        logic [31:0] rdata;
    } rsp_t;
endpackage

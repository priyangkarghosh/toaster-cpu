package tbus_pkg;
    // originator -> completer
    typedef struct packed {
        logic valid;
        logic write;
        logic [31:0] addr;
        logic [31:0] wdata;
        logic [3:0] be;
    } req_t;

    // completer -> originator
    typedef struct packed {
        logic ack;
        logic [31:0] rdata;
    } rsp_t;
endpackage

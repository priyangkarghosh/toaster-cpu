package tbus_map_pkg;
    // completer region descriptor: base address + range mask
    // a transaction routes to a completer when (addr & mask) == base
    typedef struct packed {
        logic [31:0] base;
        logic [31:0] mask;
    } region_t;

    // completers
    localparam region_t MEM   = '{base: 32'h0000_0000, mask: 32'hF000_0000};
    localparam region_t IOHUB = '{base: 32'h1000_0000, mask: 32'hF000_0000};
endpackage

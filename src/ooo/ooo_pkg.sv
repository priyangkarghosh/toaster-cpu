package ooo_pkg;
    import riscv_pkg::*;

    typedef struct packed {
        // status  
        logic done;      
        logic [31:0] pc;

        // data
        exc_t exc;
        logic [31:0] data;
        logic [4:0] rd;

        // control
        logic rf_en;
    } rob_entry_t;

    typedef struct packed {
        // status
        exc_t exc;
        
        // side-effect data
        logic [31:0] data;
    } comp_req_t;
endpackage

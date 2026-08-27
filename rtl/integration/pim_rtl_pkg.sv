package pim_rtl_pkg;
    localparam logic [3:0] PIM_OP_NOP  = 4'h0;
    localparam logic [3:0] PIM_OP_ADD  = 4'h1;
    localparam logic [3:0] PIM_OP_MUL  = 4'h2;
    localparam logic [3:0] PIM_OP_MAC  = 4'h3;
    localparam logic [3:0] PIM_OP_MAD  = 4'h4;
    localparam logic [3:0] PIM_OP_MOV  = 4'h8;
    localparam logic [3:0] PIM_OP_FILL = 4'h9;
    localparam logic [3:0] PIM_OP_JUMP = 4'he;
    localparam logic [3:0] PIM_OP_EXIT = 4'hf;

    localparam logic [2:0] PIM_OPD_A_OUT     = 3'd0;
    localparam logic [2:0] PIM_OPD_M_OUT     = 3'd1;
    localparam logic [2:0] PIM_OPD_EVEN_BANK = 3'd2;
    localparam logic [2:0] PIM_OPD_ODD_BANK  = 3'd3;
    localparam logic [2:0] PIM_OPD_GRF_A     = 3'd4;
    localparam logic [2:0] PIM_OPD_GRF_B     = 3'd5;
    localparam logic [2:0] PIM_OPD_SRF_M     = 3'd6;
    localparam logic [2:0] PIM_OPD_SRF_A     = 3'd7;

    localparam logic [1:0] PIM_PREC_FP16 = 2'd0;
    localparam logic [1:0] PIM_PREC_INT8 = 2'd1;

    localparam logic [2:0] DRAM_CMD_NOP = 3'd0;
    localparam logic [2:0] DRAM_CMD_ACT = 3'd1;
    localparam logic [2:0] DRAM_CMD_RD  = 3'd2;
    localparam logic [2:0] DRAM_CMD_WR  = 3'd3;
    localparam logic [2:0] DRAM_CMD_PRE = 3'd4;
    localparam logic [2:0] DRAM_CMD_REF = 3'd5;
endpackage

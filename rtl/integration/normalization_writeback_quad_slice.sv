// One-entry elastic register slice for the 16-bank normalization writeback
// channel.  The protocol is lockstep across all banks, while payload storage
// is split into four physical quads so no single 2048-bit register cone spans
// the full logic die.  The slice sustains one transaction per cycle and adds
// one startup cycle when empty.
module normalization_writeback_quad_payload #(
    parameter int unsigned BANKS_PER_QUAD = 4,
    parameter int unsigned LANES = 8,
    parameter int unsigned TAG_WIDTH = 16
)(
    input  logic clk_i,
    input  logic rst_ni,
    input  logic capture_i,
    input  logic [BANKS_PER_QUAD-1:0][TAG_WIDTH-1:0] tag_i,
    input  logic [BANKS_PER_QUAD-1:0][LANES-1:0][15:0] data_i,
    input  logic [BANKS_PER_QUAD-1:0] last_i,
    output logic [BANKS_PER_QUAD-1:0][TAG_WIDTH-1:0] tag_o,
    output logic [BANKS_PER_QUAD-1:0][LANES-1:0][15:0] data_o,
    output logic [BANKS_PER_QUAD-1:0] last_o
);
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            tag_o <= '0;
            data_o <= '0;
            last_o <= '0;
        end else if (capture_i) begin
            tag_o <= tag_i;
            data_o <= data_i;
            last_o <= last_i;
        end
    end
endmodule

module normalization_writeback_quad_slice #(
    parameter int unsigned BANKS = 16,
    parameter int unsigned QUADS = 4,
    parameter int unsigned LANES = 8,
    parameter int unsigned TAG_WIDTH = 16
)(
    input  logic clk_i,
    input  logic rst_ni,

    input  logic [BANKS-1:0] source_valid_i,
    output logic [BANKS-1:0] source_ready_o,
    input  logic [BANKS-1:0][TAG_WIDTH-1:0] source_tag_i,
    input  logic [BANKS-1:0][LANES-1:0][15:0] source_data_i,
    input  logic [BANKS-1:0] source_last_i,

    output logic [BANKS-1:0] sink_valid_o,
    input  logic [BANKS-1:0] sink_ready_i,
    output logic [BANKS-1:0][TAG_WIDTH-1:0] sink_tag_o,
    output logic [BANKS-1:0][LANES-1:0][15:0] sink_data_o,
    output logic [BANKS-1:0] sink_last_o,

    output logic protocol_error_o
);
    localparam int unsigned BANKS_PER_QUAD = BANKS / QUADS;

    logic full_q;
    logic source_full, source_partial, sink_ready_full;
    logic input_ready, capture;

    initial begin
        if (BANKS != 16) $fatal(1, "normalization writeback slice requires 16 banks");
        if (QUADS != 4 || BANKS % QUADS != 0)
            $fatal(1, "normalization writeback slice requires four equal quads");
        if (!(LANES == 4 || LANES == 8 || LANES == 16))
            $fatal(1, "LANES must be 4, 8, or 16");
    end

    assign source_full = &source_valid_i;
    assign source_partial = |source_valid_i && !source_full;
    assign sink_ready_full = &sink_ready_i;
    assign input_ready = !full_q || sink_ready_full;
    assign capture = input_ready && source_full;
    assign source_ready_o = {BANKS{input_ready}};
    assign sink_valid_o = {BANKS{full_q}};

    for (genvar quad = 0; quad < QUADS; quad++) begin : g_quad
        localparam int unsigned LO = quad * BANKS_PER_QUAD;
        normalization_writeback_quad_payload #(
            .BANKS_PER_QUAD(BANKS_PER_QUAD), .LANES(LANES),
            .TAG_WIDTH(TAG_WIDTH)
        ) u_payload (
            .clk_i(clk_i), .rst_ni(rst_ni), .capture_i(capture),
            .tag_i(source_tag_i[LO +: BANKS_PER_QUAD]),
            .data_i(source_data_i[LO +: BANKS_PER_QUAD]),
            .last_i(source_last_i[LO +: BANKS_PER_QUAD]),
            .tag_o(sink_tag_o[LO +: BANKS_PER_QUAD]),
            .data_o(sink_data_o[LO +: BANKS_PER_QUAD]),
            .last_o(sink_last_o[LO +: BANKS_PER_QUAD])
        );
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            full_q <= 1'b0;
            protocol_error_o <= 1'b0;
        end else begin
            if (input_ready)
                full_q <= source_full;
            if (source_partial || (|sink_ready_i && !sink_ready_full))
                protocol_error_o <= 1'b1;
        end
    end
endmodule

// B-variant slice.  The all-bank transaction contract is unchanged, while
// each quad payload register is reset by its local asynchronous-assert,
// synchronous-deassert leaf.  rst_ni resets only the narrow occupancy/error
// control.
module normalization_writeback_quad_local_reset_slice #(
    parameter int unsigned BANKS = 16,
    parameter int unsigned QUADS = 4,
    parameter int unsigned LANES = 8,
    parameter int unsigned TAG_WIDTH = 16
)(
    input  logic clk_i,
    input  logic rst_ni,
    input  logic [QUADS-1:0] quad_rst_ni_i,
    input  logic [BANKS-1:0] source_valid_i,
    output logic [BANKS-1:0] source_ready_o,
    input  logic [BANKS-1:0][TAG_WIDTH-1:0] source_tag_i,
    input  logic [BANKS-1:0][LANES-1:0][15:0] source_data_i,
    input  logic [BANKS-1:0] source_last_i,
    output logic [BANKS-1:0] sink_valid_o,
    input  logic [BANKS-1:0] sink_ready_i,
    output logic [BANKS-1:0][TAG_WIDTH-1:0] sink_tag_o,
    output logic [BANKS-1:0][LANES-1:0][15:0] sink_data_o,
    output logic [BANKS-1:0] sink_last_o,
    output logic protocol_error_o
);
    localparam int unsigned BANKS_PER_QUAD = BANKS/QUADS;
    logic full_q;
    logic source_full, source_partial, sink_ready_full;
    logic input_ready, capture;
    logic [QUADS-1:0] payload_rst_n;

    initial begin
        if (BANKS != 16 || QUADS != 4 || BANKS_PER_QUAD != 4)
            $fatal(1, "quad-local reset writeback slice requires four quads of four banks");
    end

    assign source_full = &source_valid_i;
    assign source_partial = |source_valid_i && !source_full;
    assign sink_ready_full = &sink_ready_i;
    assign input_ready = (&payload_rst_n) && (!full_q || sink_ready_full);
    assign capture = input_ready && source_full;
    assign source_ready_o = {BANKS{input_ready}};
    assign sink_valid_o = {BANKS{full_q}};

    for (genvar quad = 0; quad < QUADS; quad++) begin : g_quad
        localparam int unsigned LO = quad*BANKS_PER_QUAD;
        normalization_quad_reset_leaf u_payload_reset_leaf (
            .clk_i(clk_i), .rst_ni(quad_rst_ni_i[quad]),
            .quad_rst_ni_o(payload_rst_n[quad])
        );
        normalization_writeback_quad_payload #(
            .BANKS_PER_QUAD(BANKS_PER_QUAD), .LANES(LANES),
            .TAG_WIDTH(TAG_WIDTH)
        ) u_payload (
            .clk_i(clk_i), .rst_ni(payload_rst_n[quad]), .capture_i(capture),
            .tag_i(source_tag_i[LO +: BANKS_PER_QUAD]),
            .data_i(source_data_i[LO +: BANKS_PER_QUAD]),
            .last_i(source_last_i[LO +: BANKS_PER_QUAD]),
            .tag_o(sink_tag_o[LO +: BANKS_PER_QUAD]),
            .data_o(sink_data_o[LO +: BANKS_PER_QUAD]),
            .last_o(sink_last_o[LO +: BANKS_PER_QUAD])
        );
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            full_q <= 1'b0;
            protocol_error_o <= 1'b0;
        end else begin
            if (input_ready) full_q <= source_full;
            if (source_partial || (|sink_ready_i && !sink_ready_full))
                protocol_error_o <= 1'b1;
        end
    end
endmodule

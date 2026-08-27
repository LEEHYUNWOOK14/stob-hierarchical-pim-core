// Phase-5 B-variant DRAM boundary.  Command sequencing remains serialized to
// preserve the frozen HBM protocol, while the wide activation, affine,
// reduction, replay, and writeback payload state is owned by four physical
// quads.  Only narrow control and one selected 256-bit DRAM word cross a quad
// boundary.
module normalization_quad_reset_leaf (
    input  logic clk_i,
    input  logic rst_ni,
    output logic quad_rst_ni_o
);
    (* async_reg = "true", keep = "true" *) logic sync_meta_q, sync_release_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            sync_meta_q <= 1'b0;
            sync_release_q <= 1'b0;
        end else begin
            sync_meta_q <= 1'b1;
            sync_release_q <= sync_meta_q;
        end
    end

    assign quad_rst_ni_o = sync_release_q;
endmodule

// Zero-cycle physical fanout split for quad-local control pulses.  The
// replicated outputs are logically identical to signal_i; keep attributes are
// intentional so synthesis does not collapse the four physical branches back
// into one chip-wide net.  This changes wiring topology only, not protocol or
// pulse timing.
module normalization_quad_control_replicator #(
    parameter int unsigned QUADS = 4
) (
    input  logic signal_i,
    output logic [QUADS-1:0] signal_o
);
    (* keep = "true", dont_touch = "true" *) logic [QUADS-1:0] branch;
    for (genvar quad = 0; quad < QUADS; quad++) begin : g_branch
        (* keep = "true", dont_touch = "true" *) logic branch_keep;
        assign branch_keep = signal_i;
        assign branch[quad] = branch_keep;
    end
    assign signal_o = branch;
endmodule

module normalization_hbm_quad_payload_store #(
    parameter int unsigned BANKS_PER_QUAD = 4,
    parameter int unsigned LANES = 8,
    parameter int unsigned DATA_WIDTH = 256
)(
    input  logic clk_i,
    input  logic rst_ni,
    input  logic selected_i,
    input  logic [$clog2(BANKS_PER_QUAD)-1:0] local_bank_i,

    input  logic capture_reduction_i,
    input  logic reduction_half_i,
    input  logic prepare_reduction_upper_i,
    input  logic capture_replay_i,
    input  logic replay_half_i,
    input  logic prepare_replay_upper_i,
    input  logic capture_affine_i,
    input  logic [DATA_WIDTH-1:0] read_data_i,

    input  logic capture_writeback_i,
    input  logic writeback_half_i,
    input  logic [BANKS_PER_QUAD*LANES-1:0][15:0] writeback_data_i,

    output logic [BANKS_PER_QUAD*LANES-1:0][15:0] reduction_data_o,
    output logic [BANKS_PER_QUAD*LANES-1:0][15:0] replay_x_o,
    output logic [BANKS_PER_QUAD*LANES-1:0][15:0] replay_gamma_o,
    output logic [BANKS_PER_QUAD*LANES-1:0][15:0] replay_beta_o,
    output logic [DATA_WIDTH-1:0] selected_write_word_o
);
    localparam int unsigned HALF_WIDTH = DATA_WIDTH/2;

    logic [DATA_WIDTH-1:0] x_word_q [0:BANKS_PER_QUAD-1];
    logic [DATA_WIDTH-1:0] affine_word_q [0:BANKS_PER_QUAD-1];
    logic [DATA_WIDTH-1:0] write_word_q [0:BANKS_PER_QUAD-1];
    logic [HALF_WIDTH-1:0] reduction_payload_q [0:BANKS_PER_QUAD-1];
    logic [HALF_WIDTH-1:0] replay_payload_q [0:BANKS_PER_QUAD-1];

    initial begin
        if (BANKS_PER_QUAD != 4)
            $fatal(1, "quad-local payload store requires four banks");
        if (LANES != 8 || DATA_WIDTH != 256)
            $fatal(1, "quad-local payload packing requires 8 lanes and 256-bit words");
    end

    always_comb begin
        reduction_data_o = '0;
        replay_x_o = '0;
        replay_gamma_o = '0;
        replay_beta_o = '0;
        selected_write_word_o = write_word_q[local_bank_i];
        for (integer bank = 0; bank < BANKS_PER_QUAD; bank++) begin
            for (integer lane = 0; lane < LANES; lane++) begin
                reduction_data_o[bank*LANES+lane] =
                    reduction_payload_q[bank][lane*16 +: 16];
                replay_x_o[bank*LANES+lane] =
                    replay_payload_q[bank][lane*16 +: 16];
                replay_gamma_o[bank*LANES+lane] =
                    affine_word_q[bank][lane*16 +: 16];
                replay_beta_o[bank*LANES+lane] =
                    affine_word_q[bank][HALF_WIDTH+(lane*16) +: 16];
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            for (integer bank = 0; bank < BANKS_PER_QUAD; bank++) begin
                x_word_q[bank] <= '0;
                affine_word_q[bank] <= '0;
                write_word_q[bank] <= '0;
                reduction_payload_q[bank] <= '0;
                replay_payload_q[bank] <= '0;
            end
        end else begin
            if (selected_i && capture_reduction_i) begin
                x_word_q[local_bank_i] <= read_data_i;
                reduction_payload_q[local_bank_i] <= reduction_half_i ?
                    read_data_i[DATA_WIDTH-1:HALF_WIDTH] :
                    read_data_i[HALF_WIDTH-1:0];
            end
            if (prepare_reduction_upper_i)
                for (integer bank = 0; bank < BANKS_PER_QUAD; bank++)
                    reduction_payload_q[bank] <= x_word_q[bank][DATA_WIDTH-1:HALF_WIDTH];

            if (selected_i && capture_replay_i) begin
                x_word_q[local_bank_i] <= read_data_i;
                replay_payload_q[local_bank_i] <= replay_half_i ?
                    read_data_i[DATA_WIDTH-1:HALF_WIDTH] :
                    read_data_i[HALF_WIDTH-1:0];
            end
            if (prepare_replay_upper_i)
                for (integer bank = 0; bank < BANKS_PER_QUAD; bank++)
                    replay_payload_q[bank] <= x_word_q[bank][DATA_WIDTH-1:HALF_WIDTH];

            if (selected_i && capture_affine_i)
                affine_word_q[local_bank_i] <= read_data_i;

            if (capture_writeback_i)
                for (integer bank = 0; bank < BANKS_PER_QUAD; bank++)
                    for (integer lane = 0; lane < LANES; lane++)
                        write_word_q[bank][(writeback_half_i*HALF_WIDTH)+(lane*16) +: 16]
                            <= writeback_data_i[bank*LANES+lane];
        end
    end
endmodule

module normalization_hbm_quad_local_boundary_adapter #(
    parameter int unsigned BANKS = 16,
    parameter int unsigned QUADS = 4,
    parameter int unsigned LANES = 8,
    parameter int unsigned TAG_WIDTH = 16,
    parameter int unsigned COUNT_WIDTH = 16,
    parameter int unsigned ROW_WIDTH = 5,
    parameter int unsigned COL_WIDTH = 5,
    parameter int unsigned DATA_WIDTH = 256
)(
    input  logic clk_i,
    input  logic rst_ni,
    input  logic [QUADS-1:0] quad_rst_ni_i,

    input  logic start_valid_i,
    output logic start_ready_o,
    input  logic [TAG_WIDTH-1:0] start_tag_i,
    input  logic [COUNT_WIDTH-1:0] start_vectors_per_bank_i,
    input  logic [ROW_WIDTH-1:0] start_row_i,
    input  logic [COL_WIDTH-1:0] start_x_base_col_i,
    input  logic [COL_WIDTH-1:0] start_affine_base_col_i,
    input  logic [COL_WIDTH-1:0] start_output_base_col_i,

    output logic [BANKS-1:0] reduction_valid_o,
    input  logic [BANKS-1:0] reduction_ready_i,
    output logic [BANKS*LANES-1:0][15:0] reduction_data_o,

    input  logic replay_request_valid_i,
    output logic replay_request_ready_o,
    input  logic [TAG_WIDTH-1:0] replay_request_tag_i,
    input  logic [COUNT_WIDTH-1:0] replay_request_vectors_per_bank_i,
    input  logic [BANKS-1:0] replay_request_bank_mask_i,

    output logic [BANKS-1:0] replay_valid_o,
    input  logic [BANKS-1:0] replay_ready_i,
    output logic [BANKS-1:0][TAG_WIDTH-1:0] replay_tag_o,
    output logic [BANKS*LANES-1:0][15:0] replay_x_o,
    output logic [BANKS*LANES-1:0][15:0] replay_gamma_o,
    output logic [BANKS*LANES-1:0][15:0] replay_beta_o,
    output logic [BANKS-1:0] replay_last_o,

    input  logic [BANKS-1:0] writeback_valid_i,
    output logic [BANKS-1:0] writeback_ready_o,
    input  logic [BANKS-1:0][TAG_WIDTH-1:0] writeback_tag_i,
    input  logic [BANKS*LANES-1:0][15:0] writeback_data_i,
    input  logic [BANKS-1:0] writeback_last_i,

    output logic cmd_valid_o,
    input  logic cmd_ready_i,
    output logic [2:0] cmd_o,
    output logic [$clog2(BANKS)-1:0] cmd_bank_o,
    output logic [ROW_WIDTH-1:0] cmd_row_o,
    output logic [COL_WIDTH-1:0] cmd_col_o,
    output logic [DATA_WIDTH-1:0] cmd_write_data_o,
    output logic [DATA_WIDTH/8-1:0] cmd_write_mask_o,
    input  logic read_valid_i,
    output logic read_ready_o,
    input  logic [DATA_WIDTH-1:0] read_data_i,

    output logic done_o,
    output logic protocol_error_o,
    output logic [31:0] cycle_count_o,
    output logic [31:0] act_command_count_o,
    output logic [31:0] read_command_count_o,
    output logic [31:0] write_command_count_o,
    output logic [31:0] pre_command_count_o,
    output logic [31:0] command_wait_cycles_o
);
`include "rtl/pim_rtl_constants.svh"
    localparam int unsigned BANK_WIDTH = $clog2(BANKS);
    localparam int unsigned BANKS_PER_QUAD = BANKS/QUADS;
    localparam int unsigned LOCAL_BANK_WIDTH = $clog2(BANKS_PER_QUAD);
    localparam int unsigned QUAD_WIDTH = $clog2(QUADS);

    typedef enum logic [4:0] {
        S_IDLE, S_ACT, S_RED_RD, S_RED_WAIT, S_RED_SEND, S_WAIT_REPLAY,
        S_REP_X_RD, S_REP_X_WAIT, S_AFF_RD, S_AFF_WAIT, S_REP_SEND,
        S_WAIT_WB, S_WR, S_PRE, S_DONE
    } state_t;
    state_t state_q;

    logic [TAG_WIDTH-1:0] tag_q;
    logic [COUNT_WIDTH-1:0] vectors_q, red_vector_q, replay_vector_q;
    logic [COUNT_WIDTH-1:0] wb_vector_q;
    logic [ROW_WIDTH-1:0] row_q;
    logic [COL_WIDTH-1:0] x_base_q, affine_base_q, output_base_q;
    logic [BANK_WIDTH-1:0] bank_q;
    logic wb_word_complete_q, wb_partial_q;
    logic error_q;
    logic command_candidate, command_fire;
    logic reduction_fire, replay_fire, writeback_fire;
    logic vector_last;
    logic prepare_reduction_upper, prepare_replay_upper;
    logic [QUADS-1:0] prepare_reduction_upper_quad;
    logic [QUADS-1:0] prepare_replay_upper_quad;
    logic [QUADS-1:0][DATA_WIDTH-1:0] quad_write_word;
    logic [QUADS-1:0][BANKS_PER_QUAD*LANES-1:0][15:0] quad_reduction_data;
    logic [QUADS-1:0][BANKS_PER_QUAD*LANES-1:0][15:0] quad_replay_x;
    logic [QUADS-1:0][BANKS_PER_QUAD*LANES-1:0][15:0] quad_replay_gamma;
    logic [QUADS-1:0][BANKS_PER_QUAD*LANES-1:0][15:0] quad_replay_beta;
    logic [QUAD_WIDTH-1:0] selected_quad;
    logic [LOCAL_BANK_WIDTH-1:0] selected_local_bank;
    logic [QUADS-1:0] payload_rst_n;

    initial begin
        if (BANKS != 16 || QUADS != 4 || BANKS_PER_QUAD != 4)
            $fatal(1, "quad-local adapter requires four quads of four banks");
        if (LANES != 8 || DATA_WIDTH != 256)
            $fatal(1, "quad-local adapter requires 8 lanes and 256-bit words");
    end

    assign selected_quad = bank_q[BANK_WIDTH-1 -: QUAD_WIDTH];
    assign selected_local_bank = bank_q[LOCAL_BANK_WIDTH-1:0];
    assign start_ready_o = state_q == S_IDLE && (&payload_rst_n);
    assign replay_request_ready_o = state_q == S_WAIT_REPLAY;
    assign read_ready_o = state_q == S_RED_WAIT || state_q == S_REP_X_WAIT || state_q == S_AFF_WAIT;
    assign done_o = state_q == S_DONE;
    assign protocol_error_o = error_q;
    assign command_fire = cmd_valid_o && cmd_ready_i;
    assign reduction_fire = (&reduction_valid_o) && (&reduction_ready_i);
    assign replay_fire = (&replay_valid_o) && (&replay_ready_i);
    assign writeback_fire = (&writeback_valid_i) && (&writeback_ready_o);
    assign vector_last = replay_vector_q == vectors_q - 1'b1;
    assign prepare_reduction_upper = state_q == S_RED_SEND && reduction_fire &&
        red_vector_q != vectors_q-1'b1 && !red_vector_q[0];
    assign prepare_replay_upper = state_q == S_REP_SEND && replay_fire &&
        !replay_vector_q[0] && !vector_last;
    assign cmd_valid_o = command_candidate && cmd_ready_i;

    normalization_quad_control_replicator #(.QUADS(QUADS))
        u_prepare_reduction_upper_replicator (
            .signal_i(prepare_reduction_upper),
            .signal_o(prepare_reduction_upper_quad)
        );
    normalization_quad_control_replicator #(.QUADS(QUADS))
        u_prepare_replay_upper_replicator (
            .signal_i(prepare_replay_upper),
            .signal_o(prepare_replay_upper_quad)
        );

    for (genvar quad = 0; quad < QUADS; quad++) begin : g_quad
        localparam int unsigned QUAD_ID = quad;
        localparam int unsigned BANK_LO = quad*BANKS_PER_QUAD;
        localparam int unsigned LANE_LO = BANK_LO*LANES;

        normalization_quad_reset_leaf u_payload_reset_leaf (
            .clk_i(clk_i), .rst_ni(quad_rst_ni_i[QUAD_ID]),
            .quad_rst_ni_o(payload_rst_n[QUAD_ID])
        );
        normalization_hbm_quad_payload_store #(
            .BANKS_PER_QUAD(BANKS_PER_QUAD), .LANES(LANES),
            .DATA_WIDTH(DATA_WIDTH)
        ) u_payload_store (
            .clk_i(clk_i), .rst_ni(payload_rst_n[QUAD_ID]),
            .selected_i(selected_quad == QUAD_ID),
            .local_bank_i(selected_local_bank),
            .capture_reduction_i(state_q == S_RED_WAIT && read_valid_i),
            .reduction_half_i(red_vector_q[0]),
            .prepare_reduction_upper_i(prepare_reduction_upper_quad[QUAD_ID]),
            .capture_replay_i(state_q == S_REP_X_WAIT && read_valid_i),
            .replay_half_i(replay_vector_q[0]),
            .prepare_replay_upper_i(prepare_replay_upper_quad[QUAD_ID]),
            .capture_affine_i(state_q == S_AFF_WAIT && read_valid_i),
            .read_data_i(read_data_i),
            .capture_writeback_i(writeback_fire),
            .writeback_half_i(wb_vector_q[0]),
            .writeback_data_i(writeback_data_i[LANE_LO +: BANKS_PER_QUAD*LANES]),
            .reduction_data_o(quad_reduction_data[QUAD_ID]),
            .replay_x_o(quad_replay_x[QUAD_ID]),
            .replay_gamma_o(quad_replay_gamma[QUAD_ID]),
            .replay_beta_o(quad_replay_beta[QUAD_ID]),
            .selected_write_word_o(quad_write_word[QUAD_ID])
        );

        assign reduction_data_o[LANE_LO +: BANKS_PER_QUAD*LANES] =
            quad_reduction_data[QUAD_ID];
        assign replay_x_o[LANE_LO +: BANKS_PER_QUAD*LANES] = quad_replay_x[QUAD_ID];
        assign replay_gamma_o[LANE_LO +: BANKS_PER_QUAD*LANES] = quad_replay_gamma[QUAD_ID];
        assign replay_beta_o[LANE_LO +: BANKS_PER_QUAD*LANES] = quad_replay_beta[QUAD_ID];
    end

    always_comb begin
        command_candidate = 1'b0;
        cmd_o = DRAM_CMD_NOP;
        cmd_bank_o = bank_q;
        cmd_row_o = row_q;
        cmd_col_o = '0;
        cmd_write_data_o = '0;
        cmd_write_mask_o = '0;
        case (state_q)
            S_ACT: begin
                command_candidate = 1'b1;
                cmd_o = DRAM_CMD_ACT;
            end
            S_RED_RD, S_REP_X_RD: begin
                command_candidate = 1'b1;
                cmd_o = DRAM_CMD_RD;
                cmd_col_o = x_base_q +
                    ((state_q == S_RED_RD ? red_vector_q : replay_vector_q) >> 1);
            end
            S_AFF_RD: begin
                command_candidate = 1'b1;
                cmd_o = DRAM_CMD_RD;
                cmd_col_o = affine_base_q + replay_vector_q;
            end
            S_WR: begin
                command_candidate = 1'b1;
                cmd_o = DRAM_CMD_WR;
                cmd_col_o = output_base_q + ((wb_vector_q - 1'b1) >> 1);
                cmd_write_data_o = quad_write_word[selected_quad];
                cmd_write_mask_o = wb_partial_q ?
                    {{(DATA_WIDTH/16){1'b0}}, {(DATA_WIDTH/16){1'b1}}} : '1;
            end
            S_PRE: begin
                command_candidate = 1'b1;
                cmd_o = DRAM_CMD_PRE;
            end
            default: begin end
        endcase
    end

    always_comb begin
        reduction_valid_o = '0;
        replay_valid_o = '0;
        replay_tag_o = '0;
        replay_last_o = '0;
        writeback_ready_o = '0;

        if (state_q == S_RED_SEND)
            reduction_valid_o = '1;
        if (state_q == S_REP_SEND) begin
            replay_valid_o = '1;
            replay_last_o = {BANKS{vector_last}};
            for (integer bank = 0; bank < BANKS; bank++)
                replay_tag_o[bank] = tag_q;
        end
        // The frozen scheduler is all-bank atomic.  Keep ready independent of
        // valid so its outward valid generation cannot deadlock.
        if (!wb_word_complete_q)
            writeback_ready_o = '1;
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q <= S_IDLE;
            tag_q <= '0;
            vectors_q <= '0;
            red_vector_q <= '0;
            replay_vector_q <= '0;
            wb_vector_q <= '0;
            row_q <= '0;
            x_base_q <= '0;
            affine_base_q <= '0;
            output_base_q <= '0;
            bank_q <= '0;
            wb_word_complete_q <= 1'b0;
            wb_partial_q <= 1'b0;
            error_q <= 1'b0;
            cycle_count_o <= '0;
            act_command_count_o <= '0;
            read_command_count_o <= '0;
            write_command_count_o <= '0;
            pre_command_count_o <= '0;
            command_wait_cycles_o <= '0;
        end else begin
            if (state_q != S_IDLE && state_q != S_DONE)
                cycle_count_o <= cycle_count_o + 1'b1;
            if (command_candidate && !cmd_ready_i)
                command_wait_cycles_o <= command_wait_cycles_o + 1'b1;
            if (command_fire) begin
                case (cmd_o)
                    DRAM_CMD_ACT: act_command_count_o <= act_command_count_o + 1'b1;
                    DRAM_CMD_RD: read_command_count_o <= read_command_count_o + 1'b1;
                    DRAM_CMD_WR: write_command_count_o <= write_command_count_o + 1'b1;
                    DRAM_CMD_PRE: pre_command_count_o <= pre_command_count_o + 1'b1;
                    default: begin end
                endcase
            end

            if (writeback_fire) begin
                for (integer bank = 0; bank < BANKS; bank++)
                    if (writeback_tag_i[bank] != tag_q ||
                        writeback_last_i[bank] != (wb_vector_q == vectors_q-1'b1))
                        error_q <= 1'b1;
                if (wb_vector_q[0] || wb_vector_q == vectors_q-1'b1) begin
                    wb_word_complete_q <= 1'b1;
                    wb_partial_q <= !wb_vector_q[0];
                end
                wb_vector_q <= wb_vector_q + 1'b1;
            end

            case (state_q)
                S_IDLE: if (start_valid_i && (&payload_rst_n)) begin
                    if (start_vectors_per_bank_i == 0) error_q <= 1'b1;
                    tag_q <= start_tag_i;
                    vectors_q <= start_vectors_per_bank_i;
                    row_q <= start_row_i;
                    x_base_q <= start_x_base_col_i;
                    affine_base_q <= start_affine_base_col_i;
                    output_base_q <= start_output_base_col_i;
                    red_vector_q <= '0;
                    replay_vector_q <= '0;
                    wb_vector_q <= '0;
                    bank_q <= '0;
                    wb_word_complete_q <= 1'b0;
                    wb_partial_q <= 1'b0;
                    error_q <= 1'b0;
                    cycle_count_o <= '0;
                    act_command_count_o <= '0;
                    read_command_count_o <= '0;
                    write_command_count_o <= '0;
                    pre_command_count_o <= '0;
                    command_wait_cycles_o <= '0;
                    state_q <= S_ACT;
                end
                S_ACT: if (command_fire) begin
                    if (bank_q == BANKS-1) begin bank_q <= '0; state_q <= S_RED_RD; end
                    else bank_q <= bank_q + 1'b1;
                end
                S_RED_RD: if (command_fire) state_q <= S_RED_WAIT;
                S_RED_WAIT: if (read_valid_i) begin
                    if (bank_q == BANKS-1) begin bank_q <= '0; state_q <= S_RED_SEND; end
                    else begin bank_q <= bank_q + 1'b1; state_q <= S_RED_RD; end
                end
                S_RED_SEND: if (reduction_fire) begin
                    if (red_vector_q == vectors_q-1'b1) state_q <= S_WAIT_REPLAY;
                    else if (red_vector_q[0]) begin
                        red_vector_q <= red_vector_q + 1'b1;
                        bank_q <= '0;
                        state_q <= S_RED_RD;
                    end else
                        red_vector_q <= red_vector_q + 1'b1;
                end
                S_WAIT_REPLAY: if (replay_request_valid_i) begin
                    if (replay_request_tag_i != tag_q ||
                        replay_request_vectors_per_bank_i != vectors_q ||
                        replay_request_bank_mask_i != {BANKS{1'b1}})
                        error_q <= 1'b1;
                    replay_vector_q <= '0;
                    bank_q <= '0;
                    state_q <= S_REP_X_RD;
                end
                S_REP_X_RD: if (command_fire) state_q <= S_REP_X_WAIT;
                S_REP_X_WAIT: if (read_valid_i) begin
                    if (bank_q == BANKS-1) begin bank_q <= '0; state_q <= S_AFF_RD; end
                    else begin bank_q <= bank_q + 1'b1; state_q <= S_REP_X_RD; end
                end
                S_AFF_RD: if (command_fire) state_q <= S_AFF_WAIT;
                S_AFF_WAIT: if (read_valid_i) begin
                    if (bank_q == BANKS-1) begin bank_q <= '0; state_q <= S_REP_SEND; end
                    else begin bank_q <= bank_q + 1'b1; state_q <= S_AFF_RD; end
                end
                S_REP_SEND: if (replay_fire) begin
                    if (replay_vector_q[0] || vector_last)
                        state_q <= S_WAIT_WB;
                    else begin
                        replay_vector_q <= replay_vector_q + 1'b1;
                        bank_q <= '0;
                        state_q <= S_AFF_RD;
                    end
                end
                S_WAIT_WB: if (wb_word_complete_q) begin
                    bank_q <= '0;
                    state_q <= S_WR;
                end
                S_WR: if (command_fire) begin
                    if (bank_q == BANKS-1) begin
                        bank_q <= '0;
                        wb_word_complete_q <= 1'b0;
                        if (replay_vector_q == vectors_q-1'b1)
                            state_q <= S_PRE;
                        else begin
                            replay_vector_q <= replay_vector_q + 1'b1;
                            state_q <= S_REP_X_RD;
                        end
                    end else bank_q <= bank_q + 1'b1;
                end
                S_PRE: if (command_fire) begin
                    if (bank_q == BANKS-1) begin bank_q <= '0; state_q <= S_DONE; end
                    else bank_q <= bank_q + 1'b1;
                end
                S_DONE: state_q <= S_IDLE;
                default: state_q <= S_IDLE;
            endcase
        end
    end
endmodule

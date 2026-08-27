// Exact first two levels of the frozen 16-bank reduction tree for one
// contiguous four-bank quad: (b0+b1)+(b2+b3).  The result is captured as a
// source-registered partial-stat packet and held under backpressure.
module mixed_precision_quad_reducer4_pipe #(
    parameter int unsigned TAG_WIDTH = 16
)(
    input  logic clk_i,
    input  logic rst_ni,
    input  logic input_valid_i,
    output logic input_ready_o,
    input  logic [TAG_WIDTH-1:0] input_tag_i,
    input  logic [3:0][31:0] partial_sum_i,
    input  logic [3:0][31:0] partial_sumsq_i,
    output logic output_valid_o,
    input  logic output_ready_i,
    output logic [TAG_WIDTH-1:0] output_tag_o,
    output logic [31:0] sum_o,
    output logic [31:0] sumsq_o
);
    logic busy_q, input_fire;
    logic [TAG_WIDTH-1:0] tag_q;
    logic [1:0] pair_sum_valid, pair_sumsq_valid;
    logic [1:0][31:0] pair_sum, pair_sumsq;
    logic quad_sum_valid, quad_sumsq_valid;
    logic [31:0] quad_sum, quad_sumsq;

    assign input_ready_o = !busy_q && (!output_valid_o || output_ready_i);
    assign input_fire = input_valid_i && input_ready_o;

    for (genvar pair = 0; pair < 2; pair++) begin : g_pair
        fp32_add_pipe4 u_sum (
            .clk_i(clk_i), .rst_ni(rst_ni), .enable_i(1'b1),
            .valid_i(input_fire), .valid_o(pair_sum_valid[pair]),
            .lhs_i(partial_sum_i[pair*2]), .rhs_i(partial_sum_i[pair*2+1]),
            .result_o(pair_sum[pair])
        );
        fp32_add_pipe4 u_sumsq (
            .clk_i(clk_i), .rst_ni(rst_ni), .enable_i(1'b1),
            .valid_i(input_fire), .valid_o(pair_sumsq_valid[pair]),
            .lhs_i(partial_sumsq_i[pair*2]), .rhs_i(partial_sumsq_i[pair*2+1]),
            .result_o(pair_sumsq[pair])
        );
    end

    fp32_add_pipe4 u_quad_sum (
        .clk_i(clk_i), .rst_ni(rst_ni), .enable_i(1'b1),
        .valid_i(&pair_sum_valid), .valid_o(quad_sum_valid),
        .lhs_i(pair_sum[0]), .rhs_i(pair_sum[1]), .result_o(quad_sum)
    );
    fp32_add_pipe4 u_quad_sumsq (
        .clk_i(clk_i), .rst_ni(rst_ni), .enable_i(1'b1),
        .valid_i(&pair_sumsq_valid), .valid_o(quad_sumsq_valid),
        .lhs_i(pair_sumsq[0]), .rhs_i(pair_sumsq[1]), .result_o(quad_sumsq)
    );

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            busy_q <= 1'b0;
            tag_q <= '0;
            output_valid_o <= 1'b0;
            output_tag_o <= '0;
            sum_o <= '0;
            sumsq_o <= '0;
        end else begin
            if (output_valid_o && output_ready_i) output_valid_o <= 1'b0;
            if (input_fire) begin
                busy_q <= 1'b1;
                tag_q <= input_tag_i;
            end
            if (quad_sum_valid && quad_sumsq_valid) begin
                busy_q <= 1'b0;
                output_valid_o <= 1'b1;
                output_tag_o <= tag_q;
                sum_o <= quad_sum;
                sumsq_o <= quad_sumsq;
            end
        end
    end
endmodule

// Destination-register boundary plus the final two levels of the frozen tree:
// (Q0+Q1)+(Q2+Q3).  The source packets are already registered in each quad;
// packet_sum_q/packet_sumsq_q are the destination registers.
module mixed_precision_quad_packet_reducer_pipe #(
    parameter int unsigned QUADS = 4,
    parameter int unsigned TAG_WIDTH = 16
)(
    input  logic clk_i,
    input  logic rst_ni,
    input  logic [QUADS-1:0] input_valid_i,
    output logic [QUADS-1:0] input_ready_o,
    input  logic [QUADS-1:0][TAG_WIDTH-1:0] input_tag_i,
    input  logic [QUADS-1:0][31:0] partial_sum_i,
    input  logic [QUADS-1:0][31:0] partial_sumsq_i,
    output logic output_valid_o,
    input  logic output_ready_i,
    output logic [TAG_WIDTH-1:0] output_tag_o,
    output logic [31:0] sum_o,
    output logic [31:0] sumsq_o
);
    logic busy_q, packet_pending_q, accept_ready, input_fire;
    logic [TAG_WIDTH-1:0] tag_q;
    logic [QUADS-1:0][31:0] packet_sum_q, packet_sumsq_q;
    logic [1:0] pair_sum_valid, pair_sumsq_valid;
    logic [1:0][31:0] pair_sum, pair_sumsq;
    logic final_sum_valid, final_sumsq_valid;
    logic [31:0] final_sum, final_sumsq;

    initial begin
        if (QUADS != 4) $fatal(1, "packet reducer requires four quad packets");
    end

    assign accept_ready = !busy_q && !packet_pending_q &&
        (!output_valid_o || output_ready_i);
    assign input_ready_o = {QUADS{accept_ready && (&input_valid_i)}};
    assign input_fire = (&input_valid_i) && accept_ready;

    for (genvar pair = 0; pair < 2; pair++) begin : g_pair
        fp32_add_pipe4 u_sum (
            .clk_i(clk_i), .rst_ni(rst_ni), .enable_i(1'b1),
            .valid_i(packet_pending_q), .valid_o(pair_sum_valid[pair]),
            .lhs_i(packet_sum_q[pair*2]), .rhs_i(packet_sum_q[pair*2+1]),
            .result_o(pair_sum[pair])
        );
        fp32_add_pipe4 u_sumsq (
            .clk_i(clk_i), .rst_ni(rst_ni), .enable_i(1'b1),
            .valid_i(packet_pending_q), .valid_o(pair_sumsq_valid[pair]),
            .lhs_i(packet_sumsq_q[pair*2]), .rhs_i(packet_sumsq_q[pair*2+1]),
            .result_o(pair_sumsq[pair])
        );
    end
    fp32_add_pipe4 u_final_sum (
        .clk_i(clk_i), .rst_ni(rst_ni), .enable_i(1'b1),
        .valid_i(&pair_sum_valid), .valid_o(final_sum_valid),
        .lhs_i(pair_sum[0]), .rhs_i(pair_sum[1]), .result_o(final_sum)
    );
    fp32_add_pipe4 u_final_sumsq (
        .clk_i(clk_i), .rst_ni(rst_ni), .enable_i(1'b1),
        .valid_i(&pair_sumsq_valid), .valid_o(final_sumsq_valid),
        .lhs_i(pair_sumsq[0]), .rhs_i(pair_sumsq[1]), .result_o(final_sumsq)
    );

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            busy_q <= 1'b0;
            packet_pending_q <= 1'b0;
            tag_q <= '0;
            packet_sum_q <= '0;
            packet_sumsq_q <= '0;
            output_valid_o <= 1'b0;
            output_tag_o <= '0;
            sum_o <= '0;
            sumsq_o <= '0;
        end else begin
            if (output_valid_o && output_ready_i) output_valid_o <= 1'b0;
            if (packet_pending_q) packet_pending_q <= 1'b0;
            if (input_fire) begin
                busy_q <= 1'b1;
                packet_pending_q <= 1'b1;
                tag_q <= input_tag_i[0];
                packet_sum_q <= partial_sum_i;
                packet_sumsq_q <= partial_sumsq_i;
            end
            if (final_sum_valid && final_sumsq_valid) begin
                busy_q <= 1'b0;
                output_valid_o <= 1'b1;
                output_tag_o <= tag_q;
                sum_o <= final_sum;
                sumsq_o <= final_sumsq;
            end
        end
    end
endmodule

module normalization_quad_scalar_packet_leaf #(
    parameter int unsigned TAG_WIDTH = 16
)(
    input  logic clk_i,
    input  logic rst_ni,
    input  logic load_i,
    output logic load_ready_o,
    input  logic mode_i,
    input  logic [TAG_WIDTH-1:0] tag_i,
    input  logic [31:0] mean_i,
    input  logic [31:0] inv_i,
    output logic valid_o,
    input  logic ready_i,
    output logic mode_o,
    output logic [TAG_WIDTH-1:0] tag_o,
    output logic [31:0] mean_o,
    output logic [31:0] inv_o
);
    assign load_ready_o = !valid_o;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            valid_o <= 1'b0;
            mode_o <= 1'b0;
            tag_o <= '0;
            mean_o <= '0;
            inv_o <= '0;
        end else begin
            if (valid_o && ready_i) valid_o <= 1'b0;
            if (load_i) begin
                valid_o <= 1'b1;
                mode_o <= mode_i;
                tag_o <= tag_i;
                mean_o <= mean_i;
                inv_o <= inv_i;
            end
        end
    end
endmodule

// Broadcasts one scalar result into four independently backpressured,
// destination-registered quad packets.  configured_o pulses only after all
// four local apply groups have consumed the same packet.
module normalization_quad_scalar_return_fabric #(
    parameter int unsigned QUADS = 4,
    parameter int unsigned TAG_WIDTH = 16
)(
    input  logic clk_i,
    input  logic rst_ni,
    input  logic [QUADS-1:0] quad_rst_ni_i,
    input  logic input_valid_i,
    output logic input_ready_o,
    input  logic input_mode_i,
    input  logic [TAG_WIDTH-1:0] input_tag_i,
    input  logic [31:0] input_mean_i,
    input  logic [31:0] input_inv_i,
    output logic [QUADS-1:0] packet_valid_o,
    input  logic [QUADS-1:0] packet_ready_i,
    output logic [QUADS-1:0] packet_mode_o,
    output logic [QUADS-1:0][TAG_WIDTH-1:0] packet_tag_o,
    output logic [QUADS-1:0][31:0] packet_mean_o,
    output logic [QUADS-1:0][31:0] packet_inv_o,
    output logic configured_o,
    output logic [TAG_WIDTH-1:0] configured_tag_o
);
    logic [QUADS-1:0] leaf_load_ready, leaf_fire;
    logic [QUADS-1:0] packet_rst_n;
    logic [QUADS-1:0] pending_q;
    logic input_fire;
    logic [TAG_WIDTH-1:0] tag_q;

    assign input_ready_o = !(|pending_q) && (&leaf_load_ready);
    assign input_fire = input_valid_i && input_ready_o;
    assign leaf_fire = packet_valid_o & packet_ready_i;

    for (genvar quad = 0; quad < QUADS; quad++) begin : g_quad
        normalization_quad_reset_leaf u_packet_reset_leaf (
            .clk_i(clk_i), .rst_ni(quad_rst_ni_i[quad]),
            .quad_rst_ni_o(packet_rst_n[quad])
        );
        normalization_quad_scalar_packet_leaf #(.TAG_WIDTH(TAG_WIDTH)) u_packet_leaf (
            .clk_i(clk_i), .rst_ni(packet_rst_n[quad]),
            .load_i(input_fire), .load_ready_o(leaf_load_ready[quad]),
            .mode_i(input_mode_i), .tag_i(input_tag_i),
            .mean_i(input_mean_i), .inv_i(input_inv_i),
            .valid_o(packet_valid_o[quad]), .ready_i(packet_ready_i[quad]),
            .mode_o(packet_mode_o[quad]), .tag_o(packet_tag_o[quad]),
            .mean_o(packet_mean_o[quad]), .inv_o(packet_inv_o[quad])
        );
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            pending_q <= '0;
            tag_q <= '0;
            configured_o <= 1'b0;
            configured_tag_o <= '0;
        end else begin
            configured_o <= 1'b0;
            if (input_fire) begin
                pending_q <= '1;
                tag_q <= input_tag_i;
            end else if (|leaf_fire) begin
                pending_q <= pending_q & ~leaf_fire;
                if (|pending_q && ((pending_q & ~leaf_fire) == '0)) begin
                    configured_o <= 1'b1;
                    configured_tag_o <= tag_q;
                end
            end
        end
    end
endmodule

module mixed_precision_quad_bank_datapath_slice #(
    parameter int unsigned BANKS_PER_QUAD = 4,
    parameter int unsigned LANES = 8,
    parameter int unsigned TAG_WIDTH = 16,
    parameter int unsigned COUNT_WIDTH = 16,
    parameter int unsigned LOCAL_REDUCE_CONTEXTS = 2,
    parameter int unsigned APPLY_FIFO_DEPTH = 16,
    parameter bit RESET_DOMAIN_PARTITION = 1'b0
)(
    input  logic clk_i,
    input  logic rst_ni,
    input  logic begin_valid_i,
    output logic begin_ready_o,
    input  logic [TAG_WIDTH-1:0] begin_tag_i,
    input  logic [COUNT_WIDTH-1:0] vectors_per_bank_i,
    input  logic [BANKS_PER_QUAD-1:0] reduce_valid_i,
    output logic [BANKS_PER_QUAD-1:0] reduce_ready_o,
    input  logic [BANKS_PER_QUAD-1:0][LANES-1:0][15:0] reduce_data_i,
    input  logic [BANKS_PER_QUAD-1:0] apply_valid_i,
    output logic [BANKS_PER_QUAD-1:0] apply_ready_o,
    input  logic [BANKS_PER_QUAD-1:0][TAG_WIDTH-1:0] apply_tag_i,
    input  logic [BANKS_PER_QUAD-1:0][LANES-1:0][15:0] apply_x_i,
    input  logic [BANKS_PER_QUAD-1:0][LANES-1:0][15:0] apply_gamma_i,
    input  logic [BANKS_PER_QUAD-1:0][LANES-1:0][15:0] apply_beta_i,
    input  logic [BANKS_PER_QUAD-1:0] apply_last_i,
    output logic [BANKS_PER_QUAD-1:0] result_valid_o,
    input  logic [BANKS_PER_QUAD-1:0] result_ready_i,
    output logic [BANKS_PER_QUAD-1:0][TAG_WIDTH-1:0] result_tag_o,
    output logic [BANKS_PER_QUAD-1:0][LANES-1:0][15:0] result_data_o,
    output logic [BANKS_PER_QUAD-1:0] result_last_o,
    output logic partial_valid_o,
    input  logic partial_ready_i,
    output logic [TAG_WIDTH-1:0] partial_tag_o,
    output logic [31:0] partial_sum_o,
    output logic [31:0] partial_sumsq_o,
    input  logic scalar_packet_valid_i,
    output logic scalar_packet_ready_o,
    input  logic scalar_packet_mode_i,
    input  logic [TAG_WIDTH-1:0] scalar_packet_tag_i,
    input  logic [31:0] scalar_packet_mean_i,
    input  logic [31:0] scalar_packet_inv_i,
    output logic protocol_error_o
);
    logic [BANKS_PER_QUAD-1:0] local_begin_ready, local_valid, local_ready;
    logic [BANKS_PER_QUAD-1:0] local_error, apply_config_ready, apply_error;
    logic [BANKS_PER_QUAD-1:0][TAG_WIDTH-1:0] local_tag;
    logic [BANKS_PER_QUAD-1:0][31:0] local_sum, local_sumsq;
    logic partial_input_ready, config_fire;
    logic tag_mismatch;
    logic [BANKS_PER_QUAD-1:0] reduce_rst_n, apply_rst_n;
    logic quad_reducer_rst_n;

    initial begin
        if (BANKS_PER_QUAD != 4)
            $fatal(1, "quad datapath slice requires four banks");
    end

    assign begin_ready_o = (&reduce_rst_n) && (&apply_rst_n) &&
        quad_reducer_rst_n && (&local_begin_ready);
    assign scalar_packet_ready_o = &apply_config_ready;
    assign config_fire = scalar_packet_valid_i && scalar_packet_ready_o;
    assign local_ready = {BANKS_PER_QUAD{partial_input_ready && (&local_valid)}};
    assign tag_mismatch = (&local_valid) &&
        (|(local_tag ^ {BANKS_PER_QUAD{local_tag[0]}}));
    assign protocol_error_o = (|local_error) || (|apply_error) || tag_mismatch;

    for (genvar bank = 0; bank < BANKS_PER_QUAD; bank++) begin : g_bank
        // A quad reset is a narrow distribution root.  Separate leaf resets
        // keep the reducer and apply state of each bank from becoming one
        // flat, tens-of-thousands-of-sinks physical net after mapping.
        normalization_quad_reset_leaf u_reduce_reset_leaf (
            .clk_i(clk_i), .rst_ni(rst_ni),
            .quad_rst_ni_o(reduce_rst_n[bank])
        );
        normalization_quad_reset_leaf u_apply_reset_leaf (
            .clk_i(clk_i), .rst_ni(rst_ni),
            .quad_rst_ni_o(apply_rst_n[bank])
        );
        mixed_precision_bank_reducer_pingpong #(
            .LANES(LANES), .TAG_WIDTH(TAG_WIDTH), .COUNT_WIDTH(COUNT_WIDTH),
            .LOCAL_CONTEXTS(LOCAL_REDUCE_CONTEXTS),
            .RESET_DOMAIN_PARTITION(RESET_DOMAIN_PARTITION)
        ) u_reduce (
            .clk_i(clk_i), .rst_ni(reduce_rst_n[bank]),
            .begin_valid_i(begin_valid_i), .begin_ready_o(local_begin_ready[bank]),
            .begin_tag_i(begin_tag_i), .begin_vector_count_i(vectors_per_bank_i),
            .vector_valid_i(reduce_valid_i[bank]), .vector_ready_o(reduce_ready_o[bank]),
            .vector_data_i(reduce_data_i[bank]), .result_valid_o(local_valid[bank]),
            .result_ready_i(local_ready[bank]), .result_tag_o(local_tag[bank]),
            .result_sum_o(local_sum[bank]), .result_sumsq_o(local_sumsq[bank]),
            .protocol_error_o(local_error[bank])
        );
        mixed_precision_bank_apply_pipe #(
            .LANES(LANES), .TAG_WIDTH(TAG_WIDTH), .FIFO_DEPTH(APPLY_FIFO_DEPTH)
        ) u_apply (
            .clk_i(clk_i), .rst_ni(apply_rst_n[bank]),
            .config_valid_i(config_fire), .config_ready_o(apply_config_ready[bank]),
            .config_rms_norm_i(scalar_packet_mode_i),
            .config_tag_i(scalar_packet_tag_i), .config_mean_i(scalar_packet_mean_i),
            .config_inv_std_i(scalar_packet_inv_i),
            .vector_valid_i(apply_valid_i[bank]), .vector_ready_o(apply_ready_o[bank]),
            .vector_tag_i(apply_tag_i[bank]), .x_i(apply_x_i[bank]),
            .gamma_i(apply_gamma_i[bank]), .beta_i(apply_beta_i[bank]),
            .vector_last_i(apply_last_i[bank]), .result_valid_o(result_valid_o[bank]),
            .result_ready_i(result_ready_i[bank]), .result_tag_o(result_tag_o[bank]),
            .result_data_o(result_data_o[bank]), .result_last_o(result_last_o[bank]),
            .context_error_o(apply_error[bank])
        );
    end

    normalization_quad_reset_leaf u_quad_reducer_reset_leaf (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .quad_rst_ni_o(quad_reducer_rst_n)
    );
    mixed_precision_quad_reducer4_pipe #(.TAG_WIDTH(TAG_WIDTH)) u_quad_reducer (
        .clk_i(clk_i), .rst_ni(quad_reducer_rst_n), .input_valid_i(&local_valid),
        .input_ready_o(partial_input_ready), .input_tag_i(local_tag[0]),
        .partial_sum_i(local_sum), .partial_sumsq_i(local_sumsq),
        .output_valid_o(partial_valid_o), .output_ready_i(partial_ready_i),
        .output_tag_o(partial_tag_o), .sum_o(partial_sum_o), .sumsq_o(partial_sumsq_o)
    );
endmodule

module mixed_precision_quad_local_multirow_datapath #(
    parameter int unsigned BANKS = 16,
    parameter int unsigned QUADS = 4,
    parameter int unsigned LANES = 8,
    parameter int unsigned SCALAR_ENGINES = 4,
    parameter int unsigned CONTEXTS = 8,
    parameter int unsigned TAG_WIDTH = 16,
    parameter int unsigned COUNT_WIDTH = 16,
    parameter int unsigned LOCAL_REDUCE_CONTEXTS = 2,
    parameter int unsigned APPLY_FIFO_DEPTH = 16,
    parameter bit RESET_DOMAIN_PARTITION = 1'b0
)(
    input  logic clk_i,
    input  logic rst_ni,
    input  logic [QUADS-1:0] quad_rst_ni_i,
    input  logic begin_valid_i,
    output logic begin_ready_o,
    input  logic rms_norm_i,
    input  logic [TAG_WIDTH-1:0] tag_i,
    input  logic [COUNT_WIDTH-1:0] vectors_per_bank_i,
    input  logic [31:0] inv_hidden_i,
    input  logic [31:0] epsilon_i,
    input  logic [BANKS-1:0] reduce_valid_i,
    output logic [BANKS-1:0] reduce_ready_o,
    input  logic [BANKS-1:0][LANES-1:0][15:0] reduce_data_i,
    input  logic [BANKS-1:0] apply_valid_i,
    output logic [BANKS-1:0] apply_ready_o,
    input  logic [BANKS-1:0][TAG_WIDTH-1:0] apply_tag_i,
    input  logic [BANKS-1:0][LANES-1:0][15:0] apply_x_i,
    input  logic [BANKS-1:0][LANES-1:0][15:0] apply_gamma_i,
    input  logic [BANKS-1:0][LANES-1:0][15:0] apply_beta_i,
    input  logic [BANKS-1:0] apply_last_i,
    output logic [BANKS-1:0] result_valid_o,
    input  logic [BANKS-1:0] result_ready_i,
    output logic [BANKS-1:0][TAG_WIDTH-1:0] result_tag_o,
    output logic [BANKS-1:0][LANES-1:0][15:0] result_data_o,
    output logic [BANKS-1:0] result_last_o,
    output logic scalar_configured_o,
    output logic [TAG_WIDTH-1:0] scalar_configured_tag_o,
    output logic [$clog2(CONTEXTS+1)-1:0] context_occupancy_o,
    output logic protocol_error_o
);
    localparam int unsigned BANKS_PER_QUAD = BANKS/QUADS;
    logic [QUADS-1:0] quad_begin_ready, quad_partial_valid, quad_partial_ready;
    logic [QUADS-1:0][TAG_WIDTH-1:0] quad_partial_tag;
    logic [QUADS-1:0][31:0] quad_partial_sum, quad_partial_sumsq;
    logic [QUADS-1:0] quad_scalar_valid, quad_scalar_ready, quad_scalar_mode;
    logic [QUADS-1:0][TAG_WIDTH-1:0] quad_scalar_tag;
    logic [QUADS-1:0][31:0] quad_scalar_mean, quad_scalar_inv;
    logic [QUADS-1:0] quad_error;
    logic context_allocate_ready, context_hit, context_mode;
    logic context_duplicate_error, context_miss_error;
    logic [31:0] context_invh, context_eps;
    logic begin_fire;
    logic global_out_valid, global_out_ready;
    logic [TAG_WIDTH-1:0] global_out_tag;
    logic [31:0] global_sum, global_sumsq;
    logic scalar_request_ready, scalar_valid, scalar_ready;
    logic scalar_mode, scalar_clamped;
    logic [TAG_WIDTH-1:0] scalar_tag;
    logic [31:0] scalar_mean, scalar_inv;
    logic quad_tag_mismatch;
    logic context_rst_n, packet_reducer_rst_n, scalar_array_rst_n;
    logic scalar_return_control_rst_n;

    initial begin
        if (BANKS != 16 || QUADS != 4 || BANKS_PER_QUAD != 4)
            $fatal(1, "quad-local datapath requires four quads of four banks");
    end

    assign begin_ready_o = (&quad_begin_ready) && context_allocate_ready &&
        (&quad_rst_ni_i) && context_rst_n && packet_reducer_rst_n &&
        scalar_array_rst_n && scalar_return_control_rst_n;
    assign begin_fire = begin_valid_i && begin_ready_o;
    assign global_out_ready = context_hit && scalar_request_ready;
    assign quad_tag_mismatch = (&quad_partial_valid) &&
        (|(quad_partial_tag ^ {QUADS{quad_partial_tag[0]}}));
    assign protocol_error_o = (|quad_error) || context_duplicate_error ||
        context_miss_error || quad_tag_mismatch;

    // Split the central control reset before it reaches the context table,
    // packet reducer, scalar engines, and scalar-return coordinator.
    normalization_quad_reset_leaf u_context_reset_leaf (
        .clk_i(clk_i), .rst_ni(rst_ni), .quad_rst_ni_o(context_rst_n)
    );
    normalization_quad_reset_leaf u_packet_reducer_reset_leaf (
        .clk_i(clk_i), .rst_ni(rst_ni), .quad_rst_ni_o(packet_reducer_rst_n)
    );
    normalization_quad_reset_leaf u_scalar_array_reset_leaf (
        .clk_i(clk_i), .rst_ni(rst_ni), .quad_rst_ni_o(scalar_array_rst_n)
    );
    normalization_quad_reset_leaf u_scalar_return_control_reset_leaf (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .quad_rst_ni_o(scalar_return_control_rst_n)
    );

    mixed_precision_row_context_table #(
        .ENTRIES(CONTEXTS), .TAG_WIDTH(TAG_WIDTH)
    ) u_context (
        .clk_i(clk_i), .rst_ni(context_rst_n),
        .allocate_valid_i(begin_fire), .allocate_ready_o(context_allocate_ready),
        .allocate_tag_i(tag_i), .allocate_rms_norm_i(rms_norm_i),
        .allocate_inv_hidden_i(inv_hidden_i), .allocate_epsilon_i(epsilon_i),
        .lookup_valid_i(global_out_valid), .lookup_hit_o(context_hit),
        .lookup_tag_i(global_out_tag), .lookup_rms_norm_o(context_mode),
        .lookup_inv_hidden_o(context_invh), .lookup_epsilon_o(context_eps),
        .lookup_consume_i(global_out_valid && global_out_ready),
        .duplicate_tag_error_o(context_duplicate_error),
        .lookup_miss_error_o(context_miss_error), .occupancy_o(context_occupancy_o)
    );

    for (genvar quad = 0; quad < QUADS; quad++) begin : g_quad
        localparam int unsigned LO = quad*BANKS_PER_QUAD;
        mixed_precision_quad_bank_datapath_slice #(
            .BANKS_PER_QUAD(BANKS_PER_QUAD), .LANES(LANES),
            .TAG_WIDTH(TAG_WIDTH), .COUNT_WIDTH(COUNT_WIDTH),
            .LOCAL_REDUCE_CONTEXTS(LOCAL_REDUCE_CONTEXTS),
            .APPLY_FIFO_DEPTH(APPLY_FIFO_DEPTH),
            .RESET_DOMAIN_PARTITION(RESET_DOMAIN_PARTITION)
        ) u_bank_slice (
            .clk_i(clk_i), .rst_ni(quad_rst_ni_i[quad]),
            .begin_valid_i(begin_fire), .begin_ready_o(quad_begin_ready[quad]),
            .begin_tag_i(tag_i), .vectors_per_bank_i(vectors_per_bank_i),
            .reduce_valid_i(reduce_valid_i[LO +: BANKS_PER_QUAD]),
            .reduce_ready_o(reduce_ready_o[LO +: BANKS_PER_QUAD]),
            .reduce_data_i(reduce_data_i[LO +: BANKS_PER_QUAD]),
            .apply_valid_i(apply_valid_i[LO +: BANKS_PER_QUAD]),
            .apply_ready_o(apply_ready_o[LO +: BANKS_PER_QUAD]),
            .apply_tag_i(apply_tag_i[LO +: BANKS_PER_QUAD]),
            .apply_x_i(apply_x_i[LO +: BANKS_PER_QUAD]),
            .apply_gamma_i(apply_gamma_i[LO +: BANKS_PER_QUAD]),
            .apply_beta_i(apply_beta_i[LO +: BANKS_PER_QUAD]),
            .apply_last_i(apply_last_i[LO +: BANKS_PER_QUAD]),
            .result_valid_o(result_valid_o[LO +: BANKS_PER_QUAD]),
            .result_ready_i(result_ready_i[LO +: BANKS_PER_QUAD]),
            .result_tag_o(result_tag_o[LO +: BANKS_PER_QUAD]),
            .result_data_o(result_data_o[LO +: BANKS_PER_QUAD]),
            .result_last_o(result_last_o[LO +: BANKS_PER_QUAD]),
            .partial_valid_o(quad_partial_valid[quad]),
            .partial_ready_i(quad_partial_ready[quad]),
            .partial_tag_o(quad_partial_tag[quad]),
            .partial_sum_o(quad_partial_sum[quad]),
            .partial_sumsq_o(quad_partial_sumsq[quad]),
            .scalar_packet_valid_i(quad_scalar_valid[quad]),
            .scalar_packet_ready_o(quad_scalar_ready[quad]),
            .scalar_packet_mode_i(quad_scalar_mode[quad]),
            .scalar_packet_tag_i(quad_scalar_tag[quad]),
            .scalar_packet_mean_i(quad_scalar_mean[quad]),
            .scalar_packet_inv_i(quad_scalar_inv[quad]),
            .protocol_error_o(quad_error[quad])
        );
    end

    mixed_precision_quad_packet_reducer_pipe #(
        .QUADS(QUADS), .TAG_WIDTH(TAG_WIDTH)
    ) u_packet_reducer (
        .clk_i(clk_i), .rst_ni(packet_reducer_rst_n), .input_valid_i(quad_partial_valid),
        .input_ready_o(quad_partial_ready), .input_tag_i(quad_partial_tag),
        .partial_sum_i(quad_partial_sum), .partial_sumsq_i(quad_partial_sumsq),
        .output_valid_o(global_out_valid), .output_ready_i(global_out_ready),
        .output_tag_o(global_out_tag), .sum_o(global_sum), .sumsq_o(global_sumsq)
    );

    mixed_precision_scalar_engine_array #(
        .ENGINES(SCALAR_ENGINES), .TAG_WIDTH(TAG_WIDTH)
    ) u_scalar_array (
        .clk_i(clk_i), .rst_ni(scalar_array_rst_n),
        .request_valid_i(global_out_valid && context_hit),
        .request_ready_o(scalar_request_ready), .request_rms_norm_i(context_mode),
        .request_tag_i(global_out_tag), .sum_i(global_sum), .sumsq_i(global_sumsq),
        .inv_hidden_i(context_invh), .epsilon_i(context_eps),
        .response_valid_o(scalar_valid), .response_ready_i(scalar_ready),
        .response_rms_norm_o(scalar_mode), .response_tag_o(scalar_tag),
        .mean_o(scalar_mean), .inv_std_o(scalar_inv),
        .variance_clamped_o(scalar_clamped)
    );

    normalization_quad_scalar_return_fabric #(
        .QUADS(QUADS), .TAG_WIDTH(TAG_WIDTH)
    ) u_scalar_return (
        .clk_i(clk_i), .rst_ni(scalar_return_control_rst_n),
        .quad_rst_ni_i(quad_rst_ni_i),
        .input_valid_i(scalar_valid), .input_ready_o(scalar_ready),
        .input_mode_i(scalar_mode), .input_tag_i(scalar_tag),
        .input_mean_i(scalar_mean), .input_inv_i(scalar_inv),
        .packet_valid_o(quad_scalar_valid), .packet_ready_i(quad_scalar_ready),
        .packet_mode_o(quad_scalar_mode), .packet_tag_o(quad_scalar_tag),
        .packet_mean_o(quad_scalar_mean), .packet_inv_o(quad_scalar_inv),
        .configured_o(scalar_configured_o),
        .configured_tag_o(scalar_configured_tag_o)
    );
endmodule

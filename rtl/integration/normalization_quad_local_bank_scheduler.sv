// A quad-local, one-entry completion pipe.  It collapses four identical bank
// tags into one registered descriptor only after the complete quad has been
// accepted.  The central PCU therefore never consumes the 16-bank tag bus.
module normalization_registered_quad_completion_descriptor #(
    parameter int unsigned BANKS_PER_QUAD = 4,
    parameter int unsigned TAG_WIDTH = 16
)(
    input  logic clk_i,
    input  logic rst_ni,
    input  logic [BANKS_PER_QUAD-1:0] writeback_valid_i,
    input  logic [BANKS_PER_QUAD-1:0] writeback_ready_i,
    input  logic [BANKS_PER_QUAD-1:0] writeback_last_i,
    input  logic [BANKS_PER_QUAD-1:0][TAG_WIDTH-1:0] writeback_tag_i,
    output logic completion_valid_o,
    output logic [TAG_WIDTH-1:0] completion_tag_o,
    output logic protocol_error_o
);
    logic all_fire, all_last, tag_match;

    initial begin
        if (BANKS_PER_QUAD != 4)
            $fatal(1, "completion descriptor requires four banks");
    end

    always_comb begin
        all_fire = &(writeback_valid_i & writeback_ready_i);
        all_last = &writeback_last_i;
        tag_match = 1'b1;
        for (integer bank = 1; bank < BANKS_PER_QUAD; bank++)
            if (writeback_tag_i[bank] != writeback_tag_i[0])
                tag_match = 1'b0;
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            completion_valid_o <= 1'b0;
            completion_tag_o <= '0;
            protocol_error_o <= 1'b0;
        end else begin
            completion_valid_o <= all_fire && all_last && tag_match;
            if (all_fire && all_last && tag_match)
                completion_tag_o <= writeback_tag_i[0];
            if (all_fire && ((|writeback_last_i) != all_last ||
                             (all_last && !tag_match)))
                protocol_error_o <= 1'b1;
        end
    end
endmodule

// Four-bank scheduler leaf.  Wide payloads never leave this ownership scope;
// the central coordinator sees only full/partial/ready status and broadcasts
// one narrow grant per traffic class.
module normalization_quad_bank_scheduler_leaf #(
    parameter int unsigned BANKS_PER_QUAD = 4,
    parameter int unsigned LANES = 8,
    parameter int unsigned TAG_WIDTH = 16
)(
    input  logic [BANKS_PER_QUAD-1:0] reduction_valid_i,
    output logic [BANKS_PER_QUAD-1:0] reduction_ready_o,
    input  logic [BANKS_PER_QUAD-1:0][LANES-1:0][15:0] reduction_data_i,
    output logic [BANKS_PER_QUAD-1:0] core_reduction_valid_o,
    input  logic [BANKS_PER_QUAD-1:0] core_reduction_ready_i,
    output logic [BANKS_PER_QUAD-1:0][LANES-1:0][15:0] core_reduction_data_o,

    input  logic [BANKS_PER_QUAD-1:0] replay_valid_i,
    output logic [BANKS_PER_QUAD-1:0] replay_ready_o,
    input  logic [BANKS_PER_QUAD-1:0][TAG_WIDTH-1:0] replay_tag_i,
    input  logic [BANKS_PER_QUAD-1:0][LANES-1:0][15:0] replay_x_i,
    input  logic [BANKS_PER_QUAD-1:0][LANES-1:0][15:0] replay_gamma_i,
    input  logic [BANKS_PER_QUAD-1:0][LANES-1:0][15:0] replay_beta_i,
    input  logic [BANKS_PER_QUAD-1:0] replay_last_i,
    output logic [BANKS_PER_QUAD-1:0] core_replay_valid_o,
    input  logic [BANKS_PER_QUAD-1:0] core_replay_ready_i,
    output logic [BANKS_PER_QUAD-1:0][TAG_WIDTH-1:0] core_replay_tag_o,
    output logic [BANKS_PER_QUAD-1:0][LANES-1:0][15:0] core_replay_x_o,
    output logic [BANKS_PER_QUAD-1:0][LANES-1:0][15:0] core_replay_gamma_o,
    output logic [BANKS_PER_QUAD-1:0][LANES-1:0][15:0] core_replay_beta_o,
    output logic [BANKS_PER_QUAD-1:0] core_replay_last_o,

    input  logic [BANKS_PER_QUAD-1:0] core_writeback_valid_i,
    output logic [BANKS_PER_QUAD-1:0] core_writeback_ready_o,
    input  logic [BANKS_PER_QUAD-1:0][TAG_WIDTH-1:0] core_writeback_tag_i,
    input  logic [BANKS_PER_QUAD-1:0][LANES-1:0][15:0] core_writeback_data_i,
    input  logic [BANKS_PER_QUAD-1:0] core_writeback_last_i,
    output logic [BANKS_PER_QUAD-1:0] bank_writeback_valid_o,
    input  logic [BANKS_PER_QUAD-1:0] bank_writeback_ready_i,
    output logic [BANKS_PER_QUAD-1:0][TAG_WIDTH-1:0] bank_writeback_tag_o,
    output logic [BANKS_PER_QUAD-1:0][LANES-1:0][15:0] bank_writeback_data_o,
    output logic [BANKS_PER_QUAD-1:0] bank_writeback_last_o,

    input  logic reduction_grant_i,
    input  logic replay_grant_i,
    input  logic writeback_grant_i,
    output logic reduction_full_o,
    output logic reduction_partial_o,
    output logic reduction_sink_ready_o,
    output logic replay_full_o,
    output logic replay_partial_o,
    output logic replay_sink_ready_o,
    output logic writeback_full_o,
    output logic writeback_partial_o,
    output logic writeback_sink_ready_o
);
    initial begin
        if (BANKS_PER_QUAD != 4)
            $fatal(1, "quad scheduler leaf requires four banks");
    end

    always_comb begin
        reduction_full_o = &reduction_valid_i;
        reduction_partial_o = |reduction_valid_i && !reduction_full_o;
        reduction_sink_ready_o = &core_reduction_ready_i;
        replay_full_o = &replay_valid_i;
        replay_partial_o = |replay_valid_i && !replay_full_o;
        replay_sink_ready_o = &core_replay_ready_i;
        writeback_full_o = &core_writeback_valid_i;
        writeback_partial_o = |core_writeback_valid_i && !writeback_full_o;
        writeback_sink_ready_o = &bank_writeback_ready_i;

        reduction_ready_o = {BANKS_PER_QUAD{reduction_grant_i}};
        core_reduction_valid_o = {BANKS_PER_QUAD{reduction_grant_i}};
        replay_ready_o = {BANKS_PER_QUAD{replay_grant_i}};
        core_replay_valid_o = {BANKS_PER_QUAD{replay_grant_i}};
        core_writeback_ready_o = {BANKS_PER_QUAD{writeback_grant_i}};
        bank_writeback_valid_o = {BANKS_PER_QUAD{writeback_grant_i}};
    end

    assign core_reduction_data_o = reduction_data_i;
    assign core_replay_tag_o = replay_tag_i;
    assign core_replay_x_o = replay_x_i;
    assign core_replay_gamma_o = replay_gamma_i;
    assign core_replay_beta_o = replay_beta_i;
    assign core_replay_last_o = replay_last_i;
    assign bank_writeback_tag_o = core_writeback_tag_i;
    assign bank_writeback_data_o = core_writeback_data_i;
    assign bank_writeback_last_o = core_writeback_last_i;
endmodule

module normalization_quad_local_bank_scheduler #(
    parameter int unsigned BANKS = 16,
    parameter int unsigned QUADS = 4,
    parameter int unsigned LANES = 8,
    parameter int unsigned TAG_WIDTH = 16,
    parameter int unsigned STARVE_LIMIT = 16,
    parameter bit SHARED_RW_PORT = 1'b0
)(
    input  logic clk_i,
    input  logic rst_ni,
    input  logic [QUADS-1:0] quad_rst_ni_i,
    input  logic counter_clear_i,

    input  logic [BANKS-1:0] reduction_valid_i,
    output logic [BANKS-1:0] reduction_ready_o,
    input  logic [BANKS-1:0][LANES-1:0][15:0] reduction_data_i,
    output logic [BANKS-1:0] core_reduction_valid_o,
    input  logic [BANKS-1:0] core_reduction_ready_i,
    output logic [BANKS-1:0][LANES-1:0][15:0] core_reduction_data_o,

    input  logic [BANKS-1:0] replay_valid_i,
    output logic [BANKS-1:0] replay_ready_o,
    input  logic [BANKS-1:0][TAG_WIDTH-1:0] replay_tag_i,
    input  logic [BANKS-1:0][LANES-1:0][15:0] replay_x_i,
    input  logic [BANKS-1:0][LANES-1:0][15:0] replay_gamma_i,
    input  logic [BANKS-1:0][LANES-1:0][15:0] replay_beta_i,
    input  logic [BANKS-1:0] replay_last_i,
    output logic [BANKS-1:0] core_replay_valid_o,
    input  logic [BANKS-1:0] core_replay_ready_i,
    output logic [BANKS-1:0][TAG_WIDTH-1:0] core_replay_tag_o,
    output logic [BANKS-1:0][LANES-1:0][15:0] core_replay_x_o,
    output logic [BANKS-1:0][LANES-1:0][15:0] core_replay_gamma_o,
    output logic [BANKS-1:0][LANES-1:0][15:0] core_replay_beta_o,
    output logic [BANKS-1:0] core_replay_last_o,

    input  logic [BANKS-1:0] core_writeback_valid_i,
    output logic [BANKS-1:0] core_writeback_ready_o,
    input  logic [BANKS-1:0][TAG_WIDTH-1:0] core_writeback_tag_i,
    input  logic [BANKS-1:0][LANES-1:0][15:0] core_writeback_data_i,
    input  logic [BANKS-1:0] core_writeback_last_i,
    output logic [BANKS-1:0] bank_writeback_valid_o,
    input  logic [BANKS-1:0] bank_writeback_ready_i,
    output logic [BANKS-1:0][TAG_WIDTH-1:0] bank_writeback_tag_o,
    output logic [BANKS-1:0][LANES-1:0][15:0] bank_writeback_data_o,
    output logic [BANKS-1:0] bank_writeback_last_o,

    output logic [31:0] reduction_grants_o,
    output logic [31:0] replay_grants_o,
    output logic [31:0] writeback_grants_o,
    output logic [31:0] read_conflict_cycles_o,
    output logic [31:0] bank_skew_cycles_o,
    output logic quad_completion_valid_o,
    output logic [TAG_WIDTH-1:0] quad_completion_tag_o,
    output logic protocol_error_o
);
    localparam int unsigned BANKS_PER_QUAD = BANKS/QUADS;
    localparam int unsigned AGE_WIDTH = (STARVE_LIMIT <= 1) ? 1 : $clog2(STARVE_LIMIT+1);
    localparam logic [AGE_WIDTH-1:0] AGE_LIMIT = STARVE_LIMIT[AGE_WIDTH-1:0];

    logic [QUADS-1:0] quad_reduction_full, quad_reduction_partial;
    logic [QUADS-1:0] quad_reduction_sink_ready;
    logic [QUADS-1:0] quad_replay_full, quad_replay_partial;
    logic [QUADS-1:0] quad_replay_sink_ready;
    logic [QUADS-1:0] quad_writeback_full, quad_writeback_partial;
    logic [QUADS-1:0] quad_writeback_sink_ready;
    logic reduction_full, replay_full, writeback_full;
    logic reduction_partial, replay_partial, writeback_partial;
    logic reduction_eligible, replay_eligible, writeback_eligible;
    logic reduction_grant, replay_grant, writeback_grant;
    logic read_rr_q;
    logic [AGE_WIDTH-1:0] reduction_age_q, replay_age_q, writeback_age_q;
    logic [QUADS-1:0] completion_descriptor_error;
    logic [QUADS-1:0] completion_descriptor_valid;
    logic [QUADS-1:0][TAG_WIDTH-1:0] completion_descriptor_tag;
    logic completion_descriptor_mismatch;

    initial begin
        if (BANKS != 16 || QUADS != 4 || BANKS_PER_QUAD != 4)
            $fatal(1, "quad-local scheduler requires four quads of four banks");
        if (STARVE_LIMIT < 2)
            $fatal(1, "STARVE_LIMIT must be at least two");
    end

    for (genvar quad = 0; quad < QUADS; quad++) begin : g_quad
        localparam int unsigned LO = quad*BANKS_PER_QUAD;
        normalization_quad_bank_scheduler_leaf #(
            .BANKS_PER_QUAD(BANKS_PER_QUAD), .LANES(LANES),
            .TAG_WIDTH(TAG_WIDTH)
        ) u_scheduler_leaf (
            .reduction_valid_i(reduction_valid_i[LO +: BANKS_PER_QUAD]),
            .reduction_ready_o(reduction_ready_o[LO +: BANKS_PER_QUAD]),
            .reduction_data_i(reduction_data_i[LO +: BANKS_PER_QUAD]),
            .core_reduction_valid_o(core_reduction_valid_o[LO +: BANKS_PER_QUAD]),
            .core_reduction_ready_i(core_reduction_ready_i[LO +: BANKS_PER_QUAD]),
            .core_reduction_data_o(core_reduction_data_o[LO +: BANKS_PER_QUAD]),
            .replay_valid_i(replay_valid_i[LO +: BANKS_PER_QUAD]),
            .replay_ready_o(replay_ready_o[LO +: BANKS_PER_QUAD]),
            .replay_tag_i(replay_tag_i[LO +: BANKS_PER_QUAD]),
            .replay_x_i(replay_x_i[LO +: BANKS_PER_QUAD]),
            .replay_gamma_i(replay_gamma_i[LO +: BANKS_PER_QUAD]),
            .replay_beta_i(replay_beta_i[LO +: BANKS_PER_QUAD]),
            .replay_last_i(replay_last_i[LO +: BANKS_PER_QUAD]),
            .core_replay_valid_o(core_replay_valid_o[LO +: BANKS_PER_QUAD]),
            .core_replay_ready_i(core_replay_ready_i[LO +: BANKS_PER_QUAD]),
            .core_replay_tag_o(core_replay_tag_o[LO +: BANKS_PER_QUAD]),
            .core_replay_x_o(core_replay_x_o[LO +: BANKS_PER_QUAD]),
            .core_replay_gamma_o(core_replay_gamma_o[LO +: BANKS_PER_QUAD]),
            .core_replay_beta_o(core_replay_beta_o[LO +: BANKS_PER_QUAD]),
            .core_replay_last_o(core_replay_last_o[LO +: BANKS_PER_QUAD]),
            .core_writeback_valid_i(core_writeback_valid_i[LO +: BANKS_PER_QUAD]),
            .core_writeback_ready_o(core_writeback_ready_o[LO +: BANKS_PER_QUAD]),
            .core_writeback_tag_i(core_writeback_tag_i[LO +: BANKS_PER_QUAD]),
            .core_writeback_data_i(core_writeback_data_i[LO +: BANKS_PER_QUAD]),
            .core_writeback_last_i(core_writeback_last_i[LO +: BANKS_PER_QUAD]),
            .bank_writeback_valid_o(bank_writeback_valid_o[LO +: BANKS_PER_QUAD]),
            .bank_writeback_ready_i(bank_writeback_ready_i[LO +: BANKS_PER_QUAD]),
            .bank_writeback_tag_o(bank_writeback_tag_o[LO +: BANKS_PER_QUAD]),
            .bank_writeback_data_o(bank_writeback_data_o[LO +: BANKS_PER_QUAD]),
            .bank_writeback_last_o(bank_writeback_last_o[LO +: BANKS_PER_QUAD]),
            .reduction_grant_i(reduction_grant), .replay_grant_i(replay_grant),
            .writeback_grant_i(writeback_grant),
            .reduction_full_o(quad_reduction_full[quad]),
            .reduction_partial_o(quad_reduction_partial[quad]),
            .reduction_sink_ready_o(quad_reduction_sink_ready[quad]),
            .replay_full_o(quad_replay_full[quad]),
            .replay_partial_o(quad_replay_partial[quad]),
            .replay_sink_ready_o(quad_replay_sink_ready[quad]),
            .writeback_full_o(quad_writeback_full[quad]),
            .writeback_partial_o(quad_writeback_partial[quad]),
            .writeback_sink_ready_o(quad_writeback_sink_ready[quad])
        );

        normalization_registered_quad_completion_descriptor #(
            .BANKS_PER_QUAD(BANKS_PER_QUAD), .TAG_WIDTH(TAG_WIDTH)
        ) u_completion_descriptor (
            .clk_i(clk_i), .rst_ni(quad_rst_ni_i[quad]),
            .writeback_valid_i(bank_writeback_valid_o[LO +: BANKS_PER_QUAD]),
            .writeback_ready_i(bank_writeback_ready_i[LO +: BANKS_PER_QUAD]),
            .writeback_last_i(bank_writeback_last_o[LO +: BANKS_PER_QUAD]),
            .writeback_tag_i(bank_writeback_tag_o[LO +: BANKS_PER_QUAD]),
            .completion_valid_o(completion_descriptor_valid[quad]),
            .completion_tag_o(completion_descriptor_tag[quad]),
            .protocol_error_o(completion_descriptor_error[quad])
        );
    end

    always_comb begin
        quad_completion_valid_o = &completion_descriptor_valid;
        quad_completion_tag_o = completion_descriptor_tag[0];
        completion_descriptor_mismatch =
            (|completion_descriptor_valid) && !(&completion_descriptor_valid);
        if (&completion_descriptor_valid) begin
            for (integer quad = 1; quad < QUADS; quad++)
                if (completion_descriptor_tag[quad] != completion_descriptor_tag[0])
                    completion_descriptor_mismatch = 1'b1;
        end
        reduction_full = &quad_reduction_full;
        replay_full = &quad_replay_full;
        writeback_full = &quad_writeback_full;
        reduction_partial = (|quad_reduction_partial) ||
            ((|quad_reduction_full) && !reduction_full);
        replay_partial = (|quad_replay_partial) ||
            ((|quad_replay_full) && !replay_full);
        writeback_partial = (|quad_writeback_partial) ||
            ((|quad_writeback_full) && !writeback_full);
        reduction_eligible = reduction_full && (&quad_reduction_sink_ready);
        replay_eligible = replay_full && (&quad_replay_sink_ready);
        writeback_eligible = writeback_full && (&quad_writeback_sink_ready);

        reduction_grant = 1'b0;
        replay_grant = 1'b0;
        writeback_grant = 1'b0;
        if (SHARED_RW_PORT) begin
            if (reduction_eligible && reduction_age_q >= AGE_LIMIT-1'b1)
                reduction_grant = 1'b1;
            else if (replay_eligible && replay_age_q >= AGE_LIMIT-1'b1)
                replay_grant = 1'b1;
            else if (writeback_eligible && writeback_age_q >= AGE_LIMIT-1'b1)
                writeback_grant = 1'b1;
            else if (writeback_eligible)
                writeback_grant = 1'b1;
            else if (reduction_eligible && replay_eligible) begin
                reduction_grant = !read_rr_q;
                replay_grant = read_rr_q;
            end else if (reduction_eligible)
                reduction_grant = 1'b1;
            else if (replay_eligible)
                replay_grant = 1'b1;
        end else begin
            writeback_grant = writeback_eligible;
            if (reduction_eligible && replay_eligible) begin
                reduction_grant = !read_rr_q;
                replay_grant = read_rr_q;
            end else if (reduction_eligible)
                reduction_grant = 1'b1;
            else if (replay_eligible)
                replay_grant = 1'b1;
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            read_rr_q <= 1'b0;
            reduction_age_q <= '0;
            replay_age_q <= '0;
            writeback_age_q <= '0;
            reduction_grants_o <= '0;
            replay_grants_o <= '0;
            writeback_grants_o <= '0;
            read_conflict_cycles_o <= '0;
            bank_skew_cycles_o <= '0;
            protocol_error_o <= 1'b0;
        end else begin
            if (reduction_grant || replay_grant) read_rr_q <= reduction_grant;
            if (!reduction_eligible || reduction_grant) reduction_age_q <= '0;
            else if (reduction_age_q < AGE_LIMIT) reduction_age_q <= reduction_age_q + 1'b1;
            if (!replay_eligible || replay_grant) replay_age_q <= '0;
            else if (replay_age_q < AGE_LIMIT) replay_age_q <= replay_age_q + 1'b1;
            if (!writeback_eligible || writeback_grant) writeback_age_q <= '0;
            else if (writeback_age_q < AGE_LIMIT) writeback_age_q <= writeback_age_q + 1'b1;

            if (counter_clear_i) begin
                reduction_grants_o <= '0;
                replay_grants_o <= '0;
                writeback_grants_o <= '0;
                read_conflict_cycles_o <= '0;
                bank_skew_cycles_o <= '0;
            end else begin
                if (reduction_grant) reduction_grants_o <= reduction_grants_o + 1'b1;
                if (replay_grant) replay_grants_o <= replay_grants_o + 1'b1;
                if (writeback_grant) writeback_grants_o <= writeback_grants_o + 1'b1;
                if (reduction_full && replay_full)
                    read_conflict_cycles_o <= read_conflict_cycles_o + 1'b1;
                if (reduction_partial || replay_partial || writeback_partial)
                    bank_skew_cycles_o <= bank_skew_cycles_o + 1'b1;
            end

            if ((reduction_grant && replay_grant) ||
                (SHARED_RW_PORT && writeback_grant && (reduction_grant || replay_grant)) ||
                (reduction_age_q >= AGE_LIMIT && !reduction_grant) ||
                (replay_age_q >= AGE_LIMIT && !replay_grant) ||
                (writeback_age_q >= AGE_LIMIT && !writeback_grant) ||
                (|completion_descriptor_error) || completion_descriptor_mismatch)
                protocol_error_o <= 1'b1;
        end
    end
endmodule

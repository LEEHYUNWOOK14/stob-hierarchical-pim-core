// Lockstep bank scheduler for the logic-die normalization PCU.
//
// The production policy is split read/write: reduction and replay compete for
// one bank-read service slot, while write-back has a separately backpressured
// path.  SHARED_RW_PORT is retained as a conservative single-port experiment.
// A transaction is issued only when all 16 banks are valid/ready, preserving
// row alignment when an individual bank is delayed.
module normalization_bank_scheduler #(
    parameter int unsigned BANKS = 16,
    parameter int unsigned LANES = 8,
    parameter int unsigned TAG_WIDTH = 16,
    parameter int unsigned STARVE_LIMIT = 16,
    parameter bit SHARED_RW_PORT = 1'b0
)(
    input  logic clk_i,
    input  logic rst_ni,
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
    output logic protocol_error_o
);
    localparam int unsigned AGE_WIDTH = (STARVE_LIMIT <= 1) ? 1 : $clog2(STARVE_LIMIT + 1);
    localparam logic [AGE_WIDTH-1:0] AGE_LIMIT = STARVE_LIMIT[AGE_WIDTH-1:0];

    logic reduction_full, replay_full, writeback_full;
    logic reduction_partial, replay_partial, writeback_partial;
    logic reduction_sink_ready, replay_sink_ready, writeback_sink_ready;
    logic reduction_eligible, replay_eligible, writeback_eligible;
    logic reduction_grant, replay_grant, writeback_grant;
    logic read_rr_q;
    logic [AGE_WIDTH-1:0] reduction_age_q, replay_age_q, writeback_age_q;

    initial begin
        if (BANKS != 16) $fatal(1, "normalization scheduler requires 16 lockstep banks");
        if (!(LANES == 4 || LANES == 8 || LANES == 16)) $fatal(1, "LANES must be 4, 8, or 16");
        if (STARVE_LIMIT < 2) $fatal(1, "STARVE_LIMIT must be at least two");
    end

    always_comb begin
        reduction_full = &reduction_valid_i;
        replay_full = &replay_valid_i;
        writeback_full = &core_writeback_valid_i;
        reduction_partial = |reduction_valid_i && !reduction_full;
        replay_partial = |replay_valid_i && !replay_full;
        writeback_partial = |core_writeback_valid_i && !writeback_full;
        reduction_sink_ready = &core_reduction_ready_i;
        replay_sink_ready = &core_replay_ready_i;
        writeback_sink_ready = &bank_writeback_ready_i;
        reduction_eligible = reduction_full && reduction_sink_ready;
        replay_eligible = replay_full && replay_sink_ready;
        writeback_eligible = writeback_full && writeback_sink_ready;

        reduction_grant = 1'b0;
        replay_grant = 1'b0;
        writeback_grant = 1'b0;

        if (SHARED_RW_PORT) begin
            // Age overrides the normal write-back-first policy.  Age is counted
            // only while the destination can accept, so downstream stalls do
            // not create a false starvation violation.
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
            // Production split-R/W policy: output draining can never consume a
            // read slot, while reduction and replay are fair round-robin peers.
            writeback_grant = writeback_eligible;
            if (reduction_eligible && replay_eligible) begin
                reduction_grant = !read_rr_q;
                replay_grant = read_rr_q;
            end else if (reduction_eligible)
                reduction_grant = 1'b1;
            else if (replay_eligible)
                replay_grant = 1'b1;
        end

        reduction_ready_o = {BANKS{reduction_grant}};
        replay_ready_o = {BANKS{replay_grant}};
        core_reduction_valid_o = {BANKS{reduction_grant}};
        core_replay_valid_o = {BANKS{replay_grant}};
        core_writeback_ready_o = {BANKS{writeback_grant}};
        bank_writeback_valid_o = {BANKS{writeback_grant}};
    end

    // Payloads are isolated by valid/ready; the scheduler changes no data.
    assign core_reduction_data_o = reduction_data_i;
    assign core_replay_tag_o = replay_tag_i;
    assign core_replay_x_o = replay_x_i;
    assign core_replay_gamma_o = replay_gamma_i;
    assign core_replay_beta_o = replay_beta_i;
    assign core_replay_last_o = replay_last_i;
    assign bank_writeback_tag_o = core_writeback_tag_i;
    assign bank_writeback_data_o = core_writeback_data_i;
    assign bank_writeback_last_o = core_writeback_last_i;

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
            // The next tie goes to the opposite read class.
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
                if (reduction_full && replay_full) read_conflict_cycles_o <= read_conflict_cycles_o + 1'b1;
                if (reduction_partial || replay_partial || writeback_partial)
                    bank_skew_cycles_o <= bank_skew_cycles_o + 1'b1;
            end

            // Sticky errors indicate an impossible grant combination or an
            // eligible requester that exceeded the configured service bound.
            if ((reduction_grant && replay_grant) ||
                (SHARED_RW_PORT && writeback_grant && (reduction_grant || replay_grant)) ||
                (reduction_age_q >= AGE_LIMIT && !reduction_grant) ||
                (replay_age_q >= AGE_LIMIT && !replay_grant) ||
                (writeback_age_q >= AGE_LIMIT && !writeback_grant))
                protocol_error_o <= 1'b1;
        end
    end
endmodule

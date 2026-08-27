// Phase-5 B2 candidate.  The integrated B datapath remains frozen while this
// separately selectable top enables the registered per-quad completion
// descriptor.  Synthesis flattens the parameterized implementation, yielding
// four 16-bit completion tags instead of a central 16-bank tag comparator.
module logic_die_normalization_hbm_quad_local_b2_top #(
    parameter int unsigned BANKS = 16,
    parameter int unsigned LANES = 8,
    parameter int unsigned SCALAR_ENGINES = 4,
    parameter int unsigned CONTEXTS = 8,
    parameter int unsigned LOCAL_REDUCE_CONTEXTS = 2,
    parameter int unsigned APPLY_FIFO_DEPTH = 16,
    parameter int unsigned TAG_WIDTH = 16,
    parameter int unsigned COUNT_WIDTH = 16,
    parameter int unsigned ROW_WIDTH = 5,
    parameter int unsigned COL_WIDTH = 5,
    parameter int unsigned DATA_WIDTH = 256,
    parameter bit RESET_DOMAIN_PARTITION = 1'b0
)(
    input  logic clk_i,
    input  logic rst_ni,
    input  logic counter_clear_i,

    input  logic job_valid_i,
    output logic job_ready_o,
    input  logic job_rms_norm_i,
    input  logic [TAG_WIDTH-1:0] job_tag_i,
    input  logic [COUNT_WIDTH-1:0] job_vectors_per_bank_i,
    input  logic [31:0] job_inv_hidden_i,
    input  logic [31:0] job_epsilon_i,
    input  logic [ROW_WIDTH-1:0] job_row_i,
    input  logic [COL_WIDTH-1:0] job_x_base_col_i,
    input  logic [COL_WIDTH-1:0] job_affine_base_col_i,
    input  logic [COL_WIDTH-1:0] job_output_base_col_i,

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
    output logic [31:0] adapter_cycle_count_o,
    output logic [31:0] adapter_command_wait_cycles_o
);
    logic_die_normalization_hbm_quad_local_ab_top #(
        .BANKS(BANKS), .LANES(LANES), .SCALAR_ENGINES(SCALAR_ENGINES),
        .CONTEXTS(CONTEXTS), .LOCAL_REDUCE_CONTEXTS(LOCAL_REDUCE_CONTEXTS),
        .APPLY_FIFO_DEPTH(APPLY_FIFO_DEPTH), .TAG_WIDTH(TAG_WIDTH),
        .COUNT_WIDTH(COUNT_WIDTH), .ROW_WIDTH(ROW_WIDTH), .COL_WIDTH(COL_WIDTH),
        .DATA_WIDTH(DATA_WIDTH), .REGISTERED_QUAD_COMPLETION(1'b1),
        .RESET_DOMAIN_PARTITION(RESET_DOMAIN_PARTITION)
    ) u_b2_implementation (
        .clk_i(clk_i), .rst_ni(rst_ni), .counter_clear_i(counter_clear_i),
        .job_valid_i(job_valid_i), .job_ready_o(job_ready_o),
        .job_rms_norm_i(job_rms_norm_i), .job_tag_i(job_tag_i),
        .job_vectors_per_bank_i(job_vectors_per_bank_i),
        .job_inv_hidden_i(job_inv_hidden_i), .job_epsilon_i(job_epsilon_i),
        .job_row_i(job_row_i), .job_x_base_col_i(job_x_base_col_i),
        .job_affine_base_col_i(job_affine_base_col_i),
        .job_output_base_col_i(job_output_base_col_i),
        .cmd_valid_o(cmd_valid_o), .cmd_ready_i(cmd_ready_i), .cmd_o(cmd_o),
        .cmd_bank_o(cmd_bank_o), .cmd_row_o(cmd_row_o), .cmd_col_o(cmd_col_o),
        .cmd_write_data_o(cmd_write_data_o), .cmd_write_mask_o(cmd_write_mask_o),
        .read_valid_i(read_valid_i), .read_ready_o(read_ready_o),
        .read_data_i(read_data_i), .done_o(done_o),
        .protocol_error_o(protocol_error_o),
        .adapter_cycle_count_o(adapter_cycle_count_o),
        .adapter_command_wait_cycles_o(adapter_command_wait_cycles_o)
    );
endmodule

module mixed_precision_multirow_datapath #(
    parameter int unsigned BANKS=16,LANES=4,SCALAR_ENGINES=4,CONTEXTS=8,TAG_WIDTH=16,COUNT_WIDTH=16,
    parameter int unsigned LOCAL_REDUCE_CONTEXTS=2,
    parameter int unsigned APPLY_FIFO_DEPTH=16
)(
    input logic clk_i,input logic rst_ni,
    input logic begin_valid_i,output logic begin_ready_o,input logic rms_norm_i,input logic[TAG_WIDTH-1:0]tag_i,input logic[COUNT_WIDTH-1:0]vectors_per_bank_i,input logic[31:0]inv_hidden_i,epsilon_i,
    input logic[BANKS-1:0]reduce_valid_i,output logic[BANKS-1:0]reduce_ready_o,input logic[BANKS-1:0][LANES-1:0][15:0]reduce_data_i,
    input logic[BANKS-1:0]apply_valid_i,output logic[BANKS-1:0]apply_ready_o,input logic[BANKS-1:0][TAG_WIDTH-1:0]apply_tag_i,input logic[BANKS-1:0][LANES-1:0][15:0]apply_x_i,apply_gamma_i,apply_beta_i,input logic[BANKS-1:0]apply_last_i,
    output logic[BANKS-1:0]result_valid_o,input logic[BANKS-1:0]result_ready_i,output logic[BANKS-1:0][TAG_WIDTH-1:0]result_tag_o,output logic[BANKS-1:0][LANES-1:0][15:0]result_data_o,output logic[BANKS-1:0]result_last_o,
    output logic scalar_configured_o,output logic[TAG_WIDTH-1:0]scalar_configured_tag_o,output logic[$clog2(CONTEXTS+1)-1:0]context_occupancy_o,output logic protocol_error_o
);
  initial begin if(BANKS!=16)$fatal(1,"global tree requires BANKS=16");if(!(LANES==4||LANES==8||LANES==16))$fatal(1,"LANES invalid");end
  logic[BANKS-1:0]local_begin_ready,local_valid,local_ready,local_error,apply_config_ready,apply_error;logic[BANKS-1:0][TAG_WIDTH-1:0]local_tag;logic[BANKS-1:0][31:0]local_sum,local_sumsq;
  logic global_valid,global_ready,global_out_valid,global_out_ready;logic[TAG_WIDTH-1:0]global_tag,global_out_tag;logic[31:0]global_sum,global_sumsq;
  logic context_allocate_ready,context_hit,context_mode,context_duplicate_error,context_miss_error;logic[31:0]context_invh,context_eps;logic begin_fire,scalar_request_ready;
  logic scalar_valid,scalar_ready,scalar_mode,scalar_clamped;logic[TAG_WIDTH-1:0]scalar_tag;logic[31:0]scalar_mean,scalar_inv;
  logic all_local_begin_ready,all_apply_config_ready;
  always_comb begin all_local_begin_ready=&local_begin_ready;all_apply_config_ready=&apply_config_ready;end
  assign begin_ready_o=all_local_begin_ready&&context_allocate_ready;assign begin_fire=begin_valid_i&&begin_ready_o;
  mixed_precision_row_context_table #(.ENTRIES(CONTEXTS),.TAG_WIDTH(TAG_WIDTH))u_context(.clk_i,.rst_ni,.allocate_valid_i(begin_fire),.allocate_ready_o(context_allocate_ready),.allocate_tag_i(tag_i),.allocate_rms_norm_i(rms_norm_i),.allocate_inv_hidden_i(inv_hidden_i),.allocate_epsilon_i(epsilon_i),
    .lookup_valid_i(global_out_valid),.lookup_hit_o(context_hit),.lookup_tag_i(global_out_tag),.lookup_rms_norm_o(context_mode),.lookup_inv_hidden_o(context_invh),.lookup_epsilon_o(context_eps),.lookup_consume_i(global_out_valid&&global_out_ready),
    .duplicate_tag_error_o(context_duplicate_error),.lookup_miss_error_o(context_miss_error),.occupancy_o(context_occupancy_o));
  for(genvar bank=0;bank<BANKS;bank++)begin:g_bank
    mixed_precision_bank_reducer_pingpong #(.LANES(LANES),.TAG_WIDTH(TAG_WIDTH),.COUNT_WIDTH(COUNT_WIDTH),.LOCAL_CONTEXTS(LOCAL_REDUCE_CONTEXTS))u_reduce(.clk_i,.rst_ni,.begin_valid_i(begin_fire),.begin_ready_o(local_begin_ready[bank]),.begin_tag_i(tag_i),.begin_vector_count_i(vectors_per_bank_i),
      .vector_valid_i(reduce_valid_i[bank]),.vector_ready_o(reduce_ready_o[bank]),.vector_data_i(reduce_data_i[bank]),.result_valid_o(local_valid[bank]),.result_ready_i(local_ready[bank]),.result_tag_o(local_tag[bank]),.result_sum_o(local_sum[bank]),.result_sumsq_o(local_sumsq[bank]),.protocol_error_o(local_error[bank]));
    mixed_precision_bank_apply_pipe #(.LANES(LANES),.TAG_WIDTH(TAG_WIDTH),.FIFO_DEPTH(APPLY_FIFO_DEPTH))u_apply(.clk_i,.rst_ni,.config_valid_i(scalar_valid&&scalar_ready),.config_ready_o(apply_config_ready[bank]),.config_rms_norm_i(scalar_mode),.config_tag_i(scalar_tag),.config_mean_i(scalar_mean),.config_inv_std_i(scalar_inv),
      .vector_valid_i(apply_valid_i[bank]),.vector_ready_o(apply_ready_o[bank]),.vector_tag_i(apply_tag_i[bank]),.x_i(apply_x_i[bank]),.gamma_i(apply_gamma_i[bank]),.beta_i(apply_beta_i[bank]),.vector_last_i(apply_last_i[bank]),
      .result_valid_o(result_valid_o[bank]),.result_ready_i(result_ready_i[bank]),.result_tag_o(result_tag_o[bank]),.result_data_o(result_data_o[bank]),.result_last_o(result_last_o[bank]),.context_error_o(apply_error[bank]));
  end
  assign global_valid=&local_valid;assign global_tag=local_tag[0];assign local_ready={BANKS{global_ready&&global_valid}};
  mixed_precision_global_reducer16_pipe #(.TAG_WIDTH(TAG_WIDTH))u_global(.clk_i,.rst_ni,.input_valid_i(global_valid),.input_ready_o(global_ready),.input_tag_i(global_tag),.partial_sum_i(local_sum),.partial_sumsq_i(local_sumsq),.output_valid_o(global_out_valid),.output_ready_i(global_out_ready),.output_tag_o(global_out_tag),.sum_o(global_sum),.sumsq_o(global_sumsq));
  assign global_out_ready=context_hit&&scalar_request_ready;
  mixed_precision_scalar_engine_array #(.ENGINES(SCALAR_ENGINES),.TAG_WIDTH(TAG_WIDTH))u_scalar_array(.clk_i,.rst_ni,.request_valid_i(global_out_valid&&context_hit),.request_ready_o(scalar_request_ready),.request_rms_norm_i(context_mode),.request_tag_i(global_out_tag),.sum_i(global_sum),.sumsq_i(global_sumsq),.inv_hidden_i(context_invh),.epsilon_i(context_eps),
    .response_valid_o(scalar_valid),.response_ready_i(scalar_ready),.response_rms_norm_o(scalar_mode),.response_tag_o(scalar_tag),.mean_o(scalar_mean),.inv_std_o(scalar_inv),.variance_clamped_o(scalar_clamped));
  assign scalar_ready=all_apply_config_ready;
  assign protocol_error_o=|local_error|| |apply_error||context_duplicate_error||context_miss_error||(global_valid&&(|(local_tag^{BANKS{local_tag[0]}})));
  always_ff@(posedge clk_i or negedge rst_ni)begin if(!rst_ni)begin scalar_configured_o<=0;scalar_configured_tag_o<=0;end else begin scalar_configured_o<=0;if(scalar_valid&&scalar_ready)begin scalar_configured_o<=1;scalar_configured_tag_o<=scalar_tag;end end end
endmodule

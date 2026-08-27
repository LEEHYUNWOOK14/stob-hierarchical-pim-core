module mixed_precision_scalar_engine_array #(
    parameter int unsigned ENGINES=4,TAG_WIDTH=16
)(
    input logic clk_i,input logic rst_ni,
    input logic request_valid_i,output logic request_ready_o,input logic request_rms_norm_i,input logic[TAG_WIDTH-1:0]request_tag_i,input logic[31:0]sum_i,sumsq_i,inv_hidden_i,epsilon_i,
    output logic response_valid_o,input logic response_ready_i,output logic response_rms_norm_o,output logic[TAG_WIDTH-1:0]response_tag_o,output logic[31:0]mean_o,inv_std_o,output logic variance_clamped_o
);
  localparam int PTR_WIDTH=$clog2(ENGINES);initial if(!(ENGINES==4||ENGINES==8||ENGINES==16))$fatal(1,"ENGINES must be 4, 8, or 16");
  logic[PTR_WIDTH-1:0]dispatch_rr_q,response_rr_q;logic dispatch_found,response_found;integer dispatch_sel,response_sel,idx;
  logic[ENGINES-1:0]engine_req_valid,engine_req_ready,engine_resp_valid,engine_resp_ready,engine_resp_mode,engine_resp_clamped;
  logic[ENGINES-1:0][TAG_WIDTH-1:0]engine_resp_tag;logic[ENGINES-1:0][31:0]engine_mean,engine_inv;
  always_comb begin
    dispatch_found=0;dispatch_sel=0;engine_req_valid=0;
    for(integer off=0;off<ENGINES;off++)begin idx=(dispatch_rr_q+off)&(ENGINES-1);if(!dispatch_found&&engine_req_ready[idx])begin dispatch_found=1;dispatch_sel=idx;end end
    request_ready_o=dispatch_found;if(request_valid_i&&dispatch_found)engine_req_valid[dispatch_sel]=1;
    response_found=0;response_sel=0;engine_resp_ready=0;
    for(integer off=0;off<ENGINES;off++)begin idx=(response_rr_q+off)&(ENGINES-1);if(!response_found&&engine_resp_valid[idx])begin response_found=1;response_sel=idx;end end
    response_valid_o=response_found;response_rms_norm_o=response_found?engine_resp_mode[response_sel]:0;response_tag_o=response_found?engine_resp_tag[response_sel]:0;
    mean_o=response_found?engine_mean[response_sel]:0;inv_std_o=response_found?engine_inv[response_sel]:0;variance_clamped_o=response_found?engine_resp_clamped[response_sel]:0;
    if(response_found)engine_resp_ready[response_sel]=response_ready_i;
  end
  for(genvar e=0;e<ENGINES;e++)begin:g_engine
    mixed_precision_scalar_nr2_pipe #(.TAG_WIDTH(TAG_WIDTH))u_engine(.clk_i,.rst_ni,.request_valid_i(engine_req_valid[e]),.request_ready_o(engine_req_ready[e]),
      .request_rms_norm_i(request_rms_norm_i),.request_tag_i(request_tag_i),.sum_i(sum_i),.sumsq_i(sumsq_i),.inv_hidden_i(inv_hidden_i),.epsilon_i(epsilon_i),
      .response_valid_o(engine_resp_valid[e]),.response_ready_i(engine_resp_ready[e]),.response_rms_norm_o(engine_resp_mode[e]),.response_tag_o(engine_resp_tag[e]),
      .mean_o(engine_mean[e]),.inv_std_o(engine_inv[e]),.variance_clamped_o(engine_resp_clamped[e]));
  end
  always_ff@(posedge clk_i or negedge rst_ni)begin
    if(!rst_ni)begin dispatch_rr_q<=0;response_rr_q<=0;end
    else begin if(request_valid_i&&request_ready_o)dispatch_rr_q<=dispatch_sel+1; if(response_valid_o&&response_ready_i)response_rr_q<=response_sel+1;end
  end
endmodule

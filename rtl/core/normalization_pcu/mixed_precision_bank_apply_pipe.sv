// Parameterized C11 apply path for 4/8/16 lanes. Latency=12, II=1.
module mixed_precision_bank_apply_pipe #(
    parameter int unsigned LANES=4,TAG_WIDTH=16,FIFO_DEPTH=16
)(
    input logic clk_i,input logic rst_ni,
    input logic config_valid_i,output logic config_ready_o,input logic config_rms_norm_i,input logic[TAG_WIDTH-1:0]config_tag_i,input logic[31:0]config_mean_i,config_inv_std_i,
    input logic vector_valid_i,output logic vector_ready_o,input logic[TAG_WIDTH-1:0]vector_tag_i,input logic[LANES-1:0][15:0]x_i,gamma_i,beta_i,input logic vector_last_i,
    output logic result_valid_o,input logic result_ready_i,output logic[TAG_WIDTH-1:0]result_tag_o,output logic[LANES-1:0][15:0]result_data_o,output logic result_last_o,output logic context_error_o
);
  localparam int META_DEPTH=12;localparam int FIFO_PTR_WIDTH=$clog2(FIFO_DEPTH);
  initial begin if(!(LANES==4||LANES==8||LANES==16))$fatal(1,"LANES must be 4, 8, or 16");if(FIFO_DEPTH!=(1<<FIFO_PTR_WIDTH))$fatal(1,"FIFO_DEPTH must be power of two");end
  logic active_q,mode_q,accept,push,pop;logic[TAG_WIDTH-1:0]tag_q;logic[31:0]mean_q,inv_q;
  logic[META_DEPTH-1:0]meta_valid_q,meta_last_q,meta_mode_q;logic[META_DEPTH-1:0][TAG_WIDTH-1:0]meta_tag_q;logic[META_DEPTH-1:0][31:0]meta_inv_q;
  logic[META_DEPTH-1:0][LANES-1:0][31:0]meta_gamma_q,meta_beta_q;
  logic[LANES-1:0][31:0]x32,gamma32,beta32,centered,normalized,scaled,shifted;logic[LANES-1:0]center_valid,norm_valid,scale_valid,shift_valid;logic[LANES-1:0][15:0]narrowed;
  logic[FIFO_PTR_WIDTH:0]fifo_count_q,inflight_q;logic[FIFO_PTR_WIDTH-1:0]rd_ptr_q;logic[FIFO_DEPTH-1:0]wr_onehot_q;
  logic[FIFO_DEPTH-1:0][LANES*16-1:0]fifo_data_q;logic[FIFO_DEPTH-1:0][TAG_WIDTH-1:0]fifo_tag_q;logic[FIFO_DEPTH-1:0]fifo_last_q;
  assign result_valid_o=fifo_count_q!=0;assign config_ready_o=!active_q;
  assign vector_ready_o=active_q&&vector_tag_i==tag_q&&((fifo_count_q+inflight_q)<FIFO_DEPTH);assign accept=vector_valid_i&&vector_ready_o;
  assign push=shift_valid[0];assign pop=result_valid_o&&result_ready_i;assign result_data_o=fifo_data_q[rd_ptr_q];assign result_tag_o=fifo_tag_q[rd_ptr_q];assign result_last_o=fifo_last_q[rd_ptr_q];
  for(genvar lane=0;lane<LANES;lane++)begin:g_lane
    bf16_to_fp32 ux(.bf16_i(x_i[lane]),.fp32_o(x32[lane]));bf16_to_fp32 ug(.bf16_i(gamma_i[lane]),.fp32_o(gamma32[lane]));bf16_to_fp32 ub(.bf16_i(beta_i[lane]),.fp32_o(beta32[lane]));
    fp32_add_pipe4 uc(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(accept),.valid_o(center_valid[lane]),.lhs_i(x32[lane]),.rhs_i({~mean_q[31],mean_q[30:0]}),.result_o(centered[lane]));
    fp32_mul_pipe4 un(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(center_valid[lane]),.valid_o(norm_valid[lane]),.lhs_i(centered[lane]),.rhs_i(meta_inv_q[2]),.result_o(normalized[lane]));
    fp32_mul_pipe4 us(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(norm_valid[lane]),.valid_o(scale_valid[lane]),.lhs_i(normalized[lane]),.rhs_i(meta_gamma_q[5][lane]),.result_o(scaled[lane]));
    fp32_add_pipe4 uh(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(scale_valid[lane]),.valid_o(shift_valid[lane]),.lhs_i(scaled[lane]),.rhs_i(meta_mode_q[8]?32'h0:meta_beta_q[8][lane]),.result_o(shifted[lane]));
    fp32_to_bf16_rne ur(.fp32_i(shifted[lane]),.bf16_o(narrowed[lane]));
  end
  always_ff@(posedge clk_i or negedge rst_ni)begin
    if(!rst_ni)begin
      active_q<=0;mode_q<=0;tag_q<=0;mean_q<=0;inv_q<=0;meta_valid_q<=0;meta_last_q<=0;meta_mode_q<=0;meta_tag_q<=0;meta_inv_q<=0;meta_gamma_q<=0;meta_beta_q<=0;context_error_o<=0;
      fifo_count_q<=0;inflight_q<=0;rd_ptr_q<=0;wr_onehot_q<=1;fifo_data_q<=0;fifo_tag_q<=0;fifo_last_q<=0;
    end else begin
      context_error_o<=0;if(config_valid_i&&config_ready_o)begin active_q<=1;mode_q<=config_rms_norm_i;tag_q<=config_tag_i;mean_q<=config_rms_norm_i?0:config_mean_i;inv_q<=config_inv_std_i;end
      if(vector_valid_i&&(!active_q||vector_tag_i!=tag_q))context_error_o<=1;
      meta_valid_q[0]<=accept;meta_last_q[0]<=accept&&vector_last_i;meta_mode_q[0]<=mode_q;meta_tag_q[0]<=vector_tag_i;meta_inv_q[0]<=inv_q;meta_gamma_q[0]<=gamma32;meta_beta_q[0]<=beta32;
      for(integer stage=1;stage<META_DEPTH;stage++)begin meta_valid_q[stage]<=meta_valid_q[stage-1];meta_last_q[stage]<=meta_last_q[stage-1];meta_mode_q[stage]<=meta_mode_q[stage-1];meta_tag_q[stage]<=meta_tag_q[stage-1];meta_inv_q[stage]<=meta_inv_q[stage-1];meta_gamma_q[stage]<=meta_gamma_q[stage-1];meta_beta_q[stage]<=meta_beta_q[stage-1];end
      if(accept&&vector_last_i)active_q<=0;
      if(push)begin for(integer slot=0;slot<FIFO_DEPTH;slot++)if(wr_onehot_q[slot])begin fifo_data_q[slot]<=narrowed;fifo_tag_q[slot]<=meta_tag_q[META_DEPTH-1];fifo_last_q[slot]<=meta_last_q[META_DEPTH-1];end wr_onehot_q<={wr_onehot_q[FIFO_DEPTH-2:0],wr_onehot_q[FIFO_DEPTH-1]};end
      if(pop)rd_ptr_q<=rd_ptr_q+1'b1;
      case({push,pop})2'b10:fifo_count_q<=fifo_count_q+1'b1;2'b01:fifo_count_q<=fifo_count_q-1'b1;default:fifo_count_q<=fifo_count_q;endcase
      case({accept,push})2'b10:inflight_q<=inflight_q+1'b1;2'b01:inflight_q<=inflight_q-1'b1;default:inflight_q<=inflight_q;endcase
    end
  end
endmodule

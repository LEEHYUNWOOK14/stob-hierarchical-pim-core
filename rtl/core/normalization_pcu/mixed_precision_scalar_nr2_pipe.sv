// C11 scalar path. Reuses one pipelined adder and multiplier; arithmetic order
// is identical to mixed_precision_scalar_nr2, including two Newton iterations.
module mixed_precision_scalar_nr2_pipe #(
    parameter int unsigned TAG_WIDTH=16
)(
    input logic clk_i,input logic rst_ni,
    input logic request_valid_i,output logic request_ready_o,
    input logic request_rms_norm_i,input logic[TAG_WIDTH-1:0]request_tag_i,
    input logic[31:0]sum_i,sumsq_i,inv_hidden_i,epsilon_i,
    output logic response_valid_o,input logic response_ready_i,
    output logic response_rms_norm_o,output logic[TAG_WIDTH-1:0]response_tag_o,
    output logic[31:0]mean_o,inv_std_o,output logic variance_clamped_o
);
  typedef enum logic[5:0]{IDLE,M_MEAN_S,M_MEAN_W,M_MS_S,M_MS_W,M_MEAN2_S,M_MEAN2_W,A_VAR_S,A_VAR_W,A_EPS_S,A_EPS_W,
    LUT_S,LUT_W,M_YY_S,M_YY_W,M_XYY_S,M_XYY_W,M_HALF_S,M_HALF_W,A_CORR_S,A_CORR_W,M_UPD_S,M_UPD_W}state_t;
  state_t state_q;
  logic mode_q,clamped_q,iteration_q;
  logic[TAG_WIDTH-1:0]tag_q;
  logic[31:0]sum_q,sumsq_q,inv_hidden_q,epsilon_q,mean_q,mean_square_q,mean2_q,variance_q,argument_q,y_q,yy_q,xyy_q,half_q,correction_q;
  logic mul_in_valid,mul_out_valid,add_in_valid,add_out_valid;
  logic[31:0]mul_lhs,mul_rhs,mul_result,add_lhs,add_rhs,add_result;
  logic[15:0]argument_bf16,lut_output_bf16;logic[31:0]lut_output_fp32;
  logic lut_input_valid,lut_input_ready,lut_output_valid,lut_output_ready;

  // Do not make request readiness depend combinationally on response_ready_i.
  // In an engine array that dependency closes a loop through the response and
  // request arbiters.  The retained response register is a one-entry buffer;
  // a new request is accepted on the cycle after that buffer is consumed.
  assign request_ready_o=state_q==IDLE&&!response_valid_o;
  assign mul_in_valid=state_q==M_MEAN_S||state_q==M_MS_S||state_q==M_MEAN2_S||state_q==M_YY_S||state_q==M_XYY_S||state_q==M_HALF_S||state_q==M_UPD_S;
  assign add_in_valid=state_q==A_VAR_S||state_q==A_EPS_S||state_q==A_CORR_S;
  always@*begin
    mul_lhs=0;mul_rhs=0;
    case(state_q)
      M_MEAN_S:begin mul_lhs=sum_q;mul_rhs=inv_hidden_q;end
      M_MS_S:begin mul_lhs=sumsq_q;mul_rhs=inv_hidden_q;end
      M_MEAN2_S:begin mul_lhs=mean_q;mul_rhs=mean_q;end
      M_YY_S:begin mul_lhs=y_q;mul_rhs=y_q;end
      M_XYY_S:begin mul_lhs=argument_q;mul_rhs=yy_q;end
      M_HALF_S:begin mul_lhs=32'h3f000000;mul_rhs=xyy_q;end
      M_UPD_S:begin mul_lhs=y_q;mul_rhs=correction_q;end
      default:begin mul_lhs=0;mul_rhs=0;end
    endcase
    add_lhs=0;add_rhs=0;
    case(state_q)
      A_VAR_S:begin add_lhs=mean_square_q;add_rhs={~mean2_q[31],mean2_q[30:0]};end
      A_EPS_S:begin add_lhs=variance_q;add_rhs=epsilon_q;end
      A_CORR_S:begin add_lhs=32'h3fc00000;add_rhs={~half_q[31],half_q[30:0]};end
      default:begin add_lhs=0;add_rhs=0;end
    endcase
  end
  fp32_mul_pipe4 u_mul(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(mul_in_valid),.valid_o(mul_out_valid),.lhs_i(mul_lhs),.rhs_i(mul_rhs),.result_o(mul_result));
  fp32_add_pipe4 u_add(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(add_in_valid),.valid_o(add_out_valid),.lhs_i(add_lhs),.rhs_i(add_rhs),.result_o(add_result));
  fp32_to_bf16_rne u_arg_narrow(.fp32_i(argument_q),.bf16_o(argument_bf16));
  bf16_to_fp32 u_seed_expand(.bf16_i(lut_output_bf16),.fp32_o(lut_output_fp32));
  assign lut_input_valid=state_q==LUT_S;assign lut_output_ready=state_q==LUT_W;
  bf16_rsqrt_lut256 u_lut(.clk_i,.rst_ni,.input_valid_i(lut_input_valid),.input_ready_o(lut_input_ready),.input_data_i(argument_bf16),.output_valid_o(lut_output_valid),.output_ready_i(lut_output_ready),.output_data_o(lut_output_bf16));

  always_ff@(posedge clk_i or negedge rst_ni)begin
    if(!rst_ni)begin
      state_q<=IDLE;mode_q<=0;clamped_q<=0;iteration_q<=0;tag_q<=0;sum_q<=0;sumsq_q<=0;inv_hidden_q<=0;epsilon_q<=0;mean_q<=0;mean_square_q<=0;mean2_q<=0;variance_q<=0;argument_q<=0;y_q<=0;yy_q<=0;xyy_q<=0;half_q<=0;correction_q<=0;
      response_valid_o<=0;response_rms_norm_o<=0;response_tag_o<=0;mean_o<=0;inv_std_o<=0;variance_clamped_o<=0;
    end else begin
      if(response_valid_o&&response_ready_i)response_valid_o<=0;
      case(state_q)
        IDLE:if(request_valid_i&&request_ready_o)begin mode_q<=request_rms_norm_i;tag_q<=request_tag_i;sum_q<=sum_i;sumsq_q<=sumsq_i;inv_hidden_q<=inv_hidden_i;epsilon_q<=epsilon_i;mean_q<=0;clamped_q<=0;iteration_q<=0;state_q<=request_rms_norm_i?M_MS_S:M_MEAN_S;end
        M_MEAN_S:state_q<=M_MEAN_W;M_MEAN_W:if(mul_out_valid)begin mean_q<=mul_result;state_q<=M_MS_S;end
        M_MS_S:state_q<=M_MS_W;M_MS_W:if(mul_out_valid)begin mean_square_q<=mul_result;state_q<=mode_q?A_EPS_S:M_MEAN2_S;if(mode_q)variance_q<=mul_result;end
        M_MEAN2_S:state_q<=M_MEAN2_W;M_MEAN2_W:if(mul_out_valid)begin mean2_q<=mul_result;state_q<=A_VAR_S;end
        A_VAR_S:state_q<=A_VAR_W;A_VAR_W:if(add_out_valid)begin if(add_result[31]&&|add_result[30:0])begin variance_q<=0;clamped_q<=1;end else variance_q<=add_result;state_q<=A_EPS_S;end
        A_EPS_S:state_q<=A_EPS_W;A_EPS_W:if(add_out_valid)begin argument_q<=add_result;state_q<=LUT_S;end
        LUT_S:if(lut_input_ready)state_q<=LUT_W;LUT_W:if(lut_output_valid)begin y_q<=lut_output_fp32;state_q<=M_YY_S;end
        M_YY_S:state_q<=M_YY_W;M_YY_W:if(mul_out_valid)begin yy_q<=mul_result;state_q<=M_XYY_S;end
        M_XYY_S:state_q<=M_XYY_W;M_XYY_W:if(mul_out_valid)begin xyy_q<=mul_result;state_q<=M_HALF_S;end
        M_HALF_S:state_q<=M_HALF_W;M_HALF_W:if(mul_out_valid)begin half_q<=mul_result;state_q<=A_CORR_S;end
        A_CORR_S:state_q<=A_CORR_W;A_CORR_W:if(add_out_valid)begin correction_q<=add_result;state_q<=M_UPD_S;end
        M_UPD_S:state_q<=M_UPD_W;M_UPD_W:if(mul_out_valid)begin
          if(!iteration_q)begin y_q<=mul_result;iteration_q<=1;state_q<=M_YY_S;end
          else if(!response_valid_o||response_ready_i)begin response_valid_o<=1;response_rms_norm_o<=mode_q;response_tag_o<=tag_q;mean_o<=mean_q;inv_std_o<=mul_result;variance_clamped_o<=clamped_q;state_q<=IDLE;end
        end
        default:state_q<=IDLE;
      endcase
    end
  end
endmodule

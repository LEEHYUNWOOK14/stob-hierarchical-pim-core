// Parameterized local reducer.  Two contexts remain the default because the
// measured 128/2048-wide traces gained no cycles from four while state doubled.
module mixed_precision_bank_reducer_pingpong #(
    parameter int unsigned LANES=4,TAG_WIDTH=16,COUNT_WIDTH=16,
    parameter int unsigned LOCAL_CONTEXTS=2
)(
    input logic clk_i,input logic rst_ni,input logic begin_valid_i,output logic begin_ready_o,input logic[TAG_WIDTH-1:0]begin_tag_i,input logic[COUNT_WIDTH-1:0]begin_vector_count_i,
    input logic vector_valid_i,output logic vector_ready_o,input logic[LANES-1:0][15:0]vector_data_i,
    output logic result_valid_o,input logic result_ready_i,output logic[TAG_WIDTH-1:0]result_tag_o,output logic[31:0]result_sum_o,result_sumsq_o,output logic protocol_error_o
);
  localparam int PAIRS=LANES/2,MID1=LANES/4,SLOT_LATENCY=3*$clog2(LANES);
  localparam int CTX_W=(LOCAL_CONTEXTS<=1)?1:$clog2(LOCAL_CONTEXTS);
  initial begin
    if(!(LANES==4||LANES==8||LANES==16))$fatal(1,"LANES invalid");
    if(LOCAL_CONTEXTS<2)$fatal(1,"LOCAL_CONTEXTS must be at least two");
  end

  logic[LOCAL_CONTEXTS-1:0]ctx_valid_q,combine_pending_q,result_valid_q;
  logic[TAG_WIDTH-1:0]ctx_tag_q[0:LOCAL_CONTEXTS-1];
  logic[COUNT_WIDTH-1:0]expected_q[0:LOCAL_CONTEXTS-1],completed_q[0:LOCAL_CONTEXTS-1];
  logic[3:0][31:0]sum_slot_q[0:LOCAL_CONTEXTS-1],sumsq_slot_q[0:LOCAL_CONTEXTS-1];
  logic[31:0]ctx_result_sum_q[0:LOCAL_CONTEXTS-1],ctx_result_sumsq_q[0:LOCAL_CONTEXTS-1];
  logic input_active_q;logic[CTX_W-1:0]input_ctx_q;
  logic[COUNT_WIDTH-1:0]input_remaining_q;logic[1:0]input_slot_q;
  logic free_found,result_found,combine_found;logic[CTX_W-1:0]free_ctx,result_ctx,combine_sel;
  logic begin_fire,input_fire;
  always_comb begin
    free_found=0;free_ctx=0;result_found=0;result_ctx=0;combine_found=0;combine_sel=0;
    for(integer c=0;c<LOCAL_CONTEXTS;c++)begin
      if(!ctx_valid_q[c]&&!free_found)begin free_found=1;free_ctx=c[CTX_W-1:0];end
      if(result_valid_q[c]&&!result_found)begin result_found=1;result_ctx=c[CTX_W-1:0];end
      if(combine_pending_q[c]&&!combine_found)begin combine_found=1;combine_sel=c[CTX_W-1:0];end
    end
  end
  assign begin_ready_o=!input_active_q&&free_found;
  assign begin_fire=begin_valid_i&&begin_ready_o;
  assign vector_ready_o=input_active_q&&input_remaining_q!=0;
  assign input_fire=vector_valid_i&&vector_ready_o;

  logic x_valid_q;logic[LANES-1:0][31:0]expanded,square,x_q,square_q;
  logic[CTX_W-1:0]ctx_delay_q[0:SLOT_LATENCY];
  logic[1:0]slot_delay_q[0:SLOT_LATENCY];
  logic[PAIRS-1:0]pv,pqv;logic[PAIRS-1:0][31:0]ps,pq;
  logic[MID1-1:0]m1v,m1qv;logic[MID1-1:0][31:0]m1s,m1q;
  logic[1:0]m2v,m2qv;logic[1:0][31:0]m2s,m2q;
  logic vector_sum_valid,vector_sumsq_valid;logic[31:0]vector_sum,vector_sumsq;
  for(genvar lane=0;lane<LANES;lane++)begin:g_lane
    bf16_to_fp32 ux(.bf16_i(vector_data_i[lane]),.fp32_o(expanded[lane]));
    fp32_mul um(.lhs_i(expanded[lane]),.rhs_i(expanded[lane]),.result_o(square[lane]));
  end
  for(genvar p=0;p<PAIRS;p++)begin:g_pair
    fp32_add_pipe4 us(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(x_valid_q),.valid_o(pv[p]),.lhs_i(x_q[p*2]),.rhs_i(x_q[p*2+1]),.result_o(ps[p]));
    fp32_add_pipe4 uq(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(x_valid_q),.valid_o(pqv[p]),.lhs_i(square_q[p*2]),.rhs_i(square_q[p*2+1]),.result_o(pq[p]));
  end
  for(genvar n=0;n<MID1;n++)begin:g_m1
    fp32_add_pipe4 us(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(&pv),.valid_o(m1v[n]),.lhs_i(ps[n*2]),.rhs_i(ps[n*2+1]),.result_o(m1s[n]));
    fp32_add_pipe4 uq(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(&pqv),.valid_o(m1qv[n]),.lhs_i(pq[n*2]),.rhs_i(pq[n*2+1]),.result_o(m1q[n]));
  end
  generate
    if(LANES==4)begin:g4
      assign vector_sum_valid=m1v[0];assign vector_sumsq_valid=m1qv[0];assign vector_sum=m1s[0];assign vector_sumsq=m1q[0];
    end else if(LANES==8)begin:g8
      fp32_add_pipe4 us(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(&m1v),.valid_o(vector_sum_valid),.lhs_i(m1s[0]),.rhs_i(m1s[1]),.result_o(vector_sum));
      fp32_add_pipe4 uq(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(&m1qv),.valid_o(vector_sumsq_valid),.lhs_i(m1q[0]),.rhs_i(m1q[1]),.result_o(vector_sumsq));
    end else begin:g16
      for(genvar n=0;n<2;n++)begin:g_m2
        fp32_add_pipe4 us(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(&m1v),.valid_o(m2v[n]),.lhs_i(m1s[n*2]),.rhs_i(m1s[n*2+1]),.result_o(m2s[n]));
        fp32_add_pipe4 uq(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(&m1qv),.valid_o(m2qv[n]),.lhs_i(m1q[n*2]),.rhs_i(m1q[n*2+1]),.result_o(m2q[n]));
      end
      fp32_add_pipe4 usf(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(&m2v),.valid_o(vector_sum_valid),.lhs_i(m2s[0]),.rhs_i(m2s[1]),.result_o(vector_sum));
      fp32_add_pipe4 uqf(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(&m2qv),.valid_o(vector_sumsq_valid),.lhs_i(m2q[0]),.rhs_i(m2q[1]),.result_o(vector_sumsq));
    end
  endgenerate

  logic accv,accqv;logic[31:0]accs,accq,acc_lhs_sum,acc_lhs_sumsq;
  logic[CTX_W-1:0]acc_ctx_q[0:2];logic[1:0]acc_slot_q[0:2];
  assign acc_lhs_sum=sum_slot_q[ctx_delay_q[SLOT_LATENCY]][slot_delay_q[SLOT_LATENCY]];
  assign acc_lhs_sumsq=sumsq_slot_q[ctx_delay_q[SLOT_LATENCY]][slot_delay_q[SLOT_LATENCY]];
  fp32_add_pipe4 uas(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(vector_sum_valid),.valid_o(accv),.lhs_i(acc_lhs_sum),.rhs_i(vector_sum),.result_o(accs));
  fp32_add_pipe4 uaq(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(vector_sumsq_valid),.valid_o(accqv),.lhs_i(acc_lhs_sumsq),.rhs_i(vector_sumsq),.result_o(accq));

  logic combine_busy_q,combine_issue;logic[CTX_W-1:0]combine_ctx_q;
  logic[1:0]csv,cqv;logic[1:0][31:0]cs,cq;logic fsv,fqv;logic[31:0]fs,fq;
  assign combine_issue=!combine_busy_q&&combine_found;
  for(genvar p=0;p<2;p++)begin:g_combine
    fp32_add_pipe4 us(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(combine_issue),.valid_o(csv[p]),.lhs_i(sum_slot_q[combine_sel][p*2]),.rhs_i(sum_slot_q[combine_sel][p*2+1]),.result_o(cs[p]));
    fp32_add_pipe4 uq(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(combine_issue),.valid_o(cqv[p]),.lhs_i(sumsq_slot_q[combine_sel][p*2]),.rhs_i(sumsq_slot_q[combine_sel][p*2+1]),.result_o(cq[p]));
  end
  fp32_add_pipe4 ufs(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(&csv),.valid_o(fsv),.lhs_i(cs[0]),.rhs_i(cs[1]),.result_o(fs));
  fp32_add_pipe4 ufq(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(&cqv),.valid_o(fqv),.lhs_i(cq[0]),.rhs_i(cq[1]),.result_o(fq));

  assign result_valid_o=result_found;
  assign result_tag_o=ctx_tag_q[result_ctx];
  assign result_sum_o=ctx_result_sum_q[result_ctx];
  assign result_sumsq_o=ctx_result_sumsq_q[result_ctx];

  always_ff@(posedge clk_i or negedge rst_ni)begin
    if(!rst_ni)begin
      ctx_valid_q<=0;combine_pending_q<=0;result_valid_q<=0;
      for(integer c=0;c<LOCAL_CONTEXTS;c++)begin
        ctx_tag_q[c]<=0;expected_q[c]<=0;completed_q[c]<=0;sum_slot_q[c]<=0;sumsq_slot_q[c]<=0;
        ctx_result_sum_q[c]<=0;ctx_result_sumsq_q[c]<=0;
      end
      input_active_q<=0;input_ctx_q<=0;input_remaining_q<=0;input_slot_q<=0;x_valid_q<=0;x_q<=0;square_q<=0;
      for(integer i=0;i<=SLOT_LATENCY;i++)begin ctx_delay_q[i]<=0;slot_delay_q[i]<=0;end
      for(integer i=0;i<3;i++)begin acc_ctx_q[i]<=0;acc_slot_q[i]<=0;end
      combine_busy_q<=0;combine_ctx_q<=0;protocol_error_o<=0;
    end else begin
      protocol_error_o<=0;x_valid_q<=input_fire;
      if(begin_fire)begin
        ctx_valid_q[free_ctx]<=1;ctx_tag_q[free_ctx]<=begin_tag_i;expected_q[free_ctx]<=begin_vector_count_i;
        completed_q[free_ctx]<=0;sum_slot_q[free_ctx]<=0;sumsq_slot_q[free_ctx]<=0;
        input_active_q<=1;input_ctx_q<=free_ctx;input_remaining_q<=begin_vector_count_i;input_slot_q<=0;
        if(begin_vector_count_i==0)protocol_error_o<=1;
      end
      if(input_fire)begin
        x_q<=expanded;square_q<=square;ctx_delay_q[0]<=input_ctx_q;slot_delay_q[0]<=input_slot_q;
        input_slot_q<=input_slot_q+1'b1;input_remaining_q<=input_remaining_q-1'b1;
        if(input_remaining_q==1)input_active_q<=0;
      end
      for(integer i=1;i<=SLOT_LATENCY;i++)begin ctx_delay_q[i]<=ctx_delay_q[i-1];slot_delay_q[i]<=slot_delay_q[i-1];end
      if(vector_sum_valid)begin acc_ctx_q[0]<=ctx_delay_q[SLOT_LATENCY];acc_slot_q[0]<=slot_delay_q[SLOT_LATENCY];end
      acc_ctx_q[1]<=acc_ctx_q[0];acc_ctx_q[2]<=acc_ctx_q[1];acc_slot_q[1]<=acc_slot_q[0];acc_slot_q[2]<=acc_slot_q[1];
      if(accv&&accqv)begin
        sum_slot_q[acc_ctx_q[2]][acc_slot_q[2]]<=accs;sumsq_slot_q[acc_ctx_q[2]][acc_slot_q[2]]<=accq;
        completed_q[acc_ctx_q[2]]<=completed_q[acc_ctx_q[2]]+1'b1;
        if(completed_q[acc_ctx_q[2]]+1'b1==expected_q[acc_ctx_q[2]])combine_pending_q[acc_ctx_q[2]]<=1;
      end
      if(combine_issue)begin combine_pending_q[combine_sel]<=0;combine_busy_q<=1;combine_ctx_q<=combine_sel;end
      if(fsv&&fqv)begin
        ctx_result_sum_q[combine_ctx_q]<=fs;ctx_result_sumsq_q[combine_ctx_q]<=fq;
        result_valid_q[combine_ctx_q]<=1;combine_busy_q<=0;
      end
      if(result_valid_o&&result_ready_i)begin result_valid_q[result_ctx]<=0;ctx_valid_q[result_ctx]<=0;end
      if(vector_valid_i&&!vector_ready_o)protocol_error_o<=1;
    end
  end
endmodule

// Four-level balanced FP32 tree using the timing-split adder.
// One row is kept in flight; output is captured and held under backpressure.
module mixed_precision_global_reducer16_pipe #(
    parameter int unsigned TAG_WIDTH=16
)(
    input logic clk_i,input logic rst_ni,input logic input_valid_i,output logic input_ready_o,
    input logic[TAG_WIDTH-1:0]input_tag_i,input logic[15:0][31:0]partial_sum_i,partial_sumsq_i,
    output logic output_valid_o,input logic output_ready_i,output logic[TAG_WIDTH-1:0]output_tag_o,
    output logic[31:0]sum_o,sumsq_o
);
    logic busy_q;logic[TAG_WIDTH-1:0]tag_q;logic input_fire;
    logic[7:0]v0s,v0q;logic[7:0][31:0]s0,q0;
    logic[3:0]v1s,v1q;logic[3:0][31:0]s1,q1;
    logic[1:0]v2s,v2q;logic[1:0][31:0]s2,q2;
    logic v3s,v3q;logic[31:0]s3,q3;
    assign input_ready_o=!busy_q&&(!output_valid_o||output_ready_i);assign input_fire=input_valid_i&&input_ready_o;
    for(genvar n=0;n<8;n++)begin:g0
      fp32_add_pipe4 us(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(input_fire),.valid_o(v0s[n]),.lhs_i(partial_sum_i[n*2]),.rhs_i(partial_sum_i[n*2+1]),.result_o(s0[n]));
      fp32_add_pipe4 uq(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(input_fire),.valid_o(v0q[n]),.lhs_i(partial_sumsq_i[n*2]),.rhs_i(partial_sumsq_i[n*2+1]),.result_o(q0[n]));
    end
    for(genvar n=0;n<4;n++)begin:g1
      fp32_add_pipe4 us(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(&v0s),.valid_o(v1s[n]),.lhs_i(s0[n*2]),.rhs_i(s0[n*2+1]),.result_o(s1[n]));
      fp32_add_pipe4 uq(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(&v0q),.valid_o(v1q[n]),.lhs_i(q0[n*2]),.rhs_i(q0[n*2+1]),.result_o(q1[n]));
    end
    for(genvar n=0;n<2;n++)begin:g2
      fp32_add_pipe4 us(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(&v1s),.valid_o(v2s[n]),.lhs_i(s1[n*2]),.rhs_i(s1[n*2+1]),.result_o(s2[n]));
      fp32_add_pipe4 uq(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(&v1q),.valid_o(v2q[n]),.lhs_i(q1[n*2]),.rhs_i(q1[n*2+1]),.result_o(q2[n]));
    end
    fp32_add_pipe4 us3(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(&v2s),.valid_o(v3s),.lhs_i(s2[0]),.rhs_i(s2[1]),.result_o(s3));
    fp32_add_pipe4 uq3(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(&v2q),.valid_o(v3q),.lhs_i(q2[0]),.rhs_i(q2[1]),.result_o(q3));
    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin busy_q<=0;tag_q<=0;output_valid_o<=0;output_tag_o<=0;sum_o<=0;sumsq_o<=0;end
      else begin
        if(output_valid_o&&output_ready_i)output_valid_o<=0;
        if(input_fire)begin busy_q<=1;tag_q<=input_tag_i;end
        if(v3s&&v3q)begin busy_q<=0;output_valid_o<=1;output_tag_o<=tag_q;sum_o<=s3;sumsq_o<=q3;end
      end
    end
endmodule


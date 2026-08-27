// Four-stage IEEE-754 binary32 multiplier. II=1, latency=3 cycles.
// S0 decode/multiply, S1 leading-one/exponent, S2 round, S3 pack.
module fp32_mul_pipe4(
    input logic clk_i,input logic rst_ni,input logic enable_i,input logic valid_i,output logic valid_o,
    input logic[31:0]lhs_i,rhs_i,output logic[31:0]result_o
);
    logic[2:0] valid_q;
    assign valid_o=valid_q[2];

    logic sign0_d,sign0_q,nan0_d,nan0_q,inf0_d,inf0_q,zero0_d,zero0_q,invalid0_d,invalid0_q;
    logic[7:0] lhs_exp_d,rhs_exp_d;
    logic[22:0] lhs_frac_d,rhs_frac_d;
    logic[23:0] lhs_sig_d,rhs_sig_d;
    logic[47:0] product0_d,product0_q;
    integer lhs_unbiased_d,rhs_unbiased_d;
    logic[10:0] base_exp0_d,base_exp0_q;
    always @* begin
      lhs_exp_d=lhs_i[30:23];rhs_exp_d=rhs_i[30:23];lhs_frac_d=lhs_i[22:0];rhs_frac_d=rhs_i[22:0];
      lhs_sig_d={lhs_exp_d!=0,lhs_frac_d};rhs_sig_d={rhs_exp_d!=0,rhs_frac_d};
      product0_d=lhs_sig_d*rhs_sig_d;sign0_d=lhs_i[31]^rhs_i[31];
      lhs_unbiased_d=lhs_exp_d==0?-126:lhs_exp_d-127;
      rhs_unbiased_d=rhs_exp_d==0?-126:rhs_exp_d-127;
      base_exp0_d=lhs_unbiased_d+rhs_unbiased_d-46;
      nan0_d=(lhs_exp_d==8'hff&&lhs_frac_d!=0)||(rhs_exp_d==8'hff&&rhs_frac_d!=0);
      inf0_d=(lhs_exp_d==8'hff)||(rhs_exp_d==8'hff);
      zero0_d=(lhs_exp_d==0&&lhs_frac_d==0)||(rhs_exp_d==0&&rhs_frac_d==0);
      invalid0_d=inf0_d&&zero0_d;
    end

    logic sign1_q,nan1_q,inf1_q,zero1_q,invalid1_q;
    logic[47:0] product1_q;
    logic[10:0] base_exp1_q,exponent1_d,exponent1_q;
    logic[5:0] msb1_d,msb1_q;
    integer scan_i;
    always @* begin
      msb1_d=0;
      for(scan_i=0;scan_i<48;scan_i=scan_i+1)if(product0_q[scan_i])msb1_d=scan_i;
      exponent1_d=$signed(base_exp0_q)+$signed({1'b0,msb1_d});
    end

    logic sign2_q,nan2_q,inf2_q,zero2_q,invalid2_q,normal2_d,normal2_q;
    logic[10:0] exponent2_d,exponent2_q;
    logic[127:0] magnitude2_d,rounded2_d,rounded2_q,low_mask2_d;
    logic round_up2_d;
    integer shift2_d;
    always @* begin
      magnitude2_d={80'b0,product1_q};rounded2_d=0;low_mask2_d=0;round_up2_d=0;
      exponent2_d=exponent1_q;normal2_d=$signed(exponent1_q)>=-126;shift2_d=0;
      if(normal2_d)shift2_d=$signed({1'b0,msb1_q})-23;
      else shift2_d=-($signed(base_exp1_q)+149);
      if(shift2_d>=128)rounded2_d=0;
      else if(shift2_d>0)begin
        rounded2_d=magnitude2_d>>shift2_d;
        low_mask2_d=(128'd1<<(shift2_d-1))-1'b1;
        round_up2_d=magnitude2_d[shift2_d-1]&&((|(magnitude2_d&low_mask2_d))||rounded2_d[0]);
        rounded2_d=rounded2_d+round_up2_d;
      end else rounded2_d=magnitude2_d<<(-shift2_d);
      if(normal2_d&&rounded2_d>=(128'd1<<24))begin rounded2_d=rounded2_d>>1;exponent2_d=exponent1_q+1'b1;end
    end

    logic[7:0] packed_exp3_d;
    logic[31:0] result3_d;
    always @* begin
      packed_exp3_d=$signed(exponent2_q)+127;
      if(nan2_q||invalid2_q)result3_d=32'h7fc00000;
      else if(inf2_q)result3_d={sign2_q,8'hff,23'b0};
      else if(zero2_q)result3_d={sign2_q,31'b0};
      else if(normal2_q&&$signed(exponent2_q)>=128)result3_d={sign2_q,8'hff,23'b0};
      else if(normal2_q)result3_d={sign2_q,packed_exp3_d,rounded2_q[22:0]};
      else if(rounded2_q>=(128'd1<<23))result3_d={sign2_q,8'd1,23'd0};
      else result3_d={sign2_q,8'd0,rounded2_q[22:0]};
    end
    assign result_o=result3_d;

    always_ff @(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin
        valid_q<=0;sign0_q<=0;nan0_q<=0;inf0_q<=0;zero0_q<=0;invalid0_q<=0;product0_q<=0;base_exp0_q<=0;
        sign1_q<=0;nan1_q<=0;inf1_q<=0;zero1_q<=0;invalid1_q<=0;product1_q<=0;base_exp1_q<=0;msb1_q<=0;exponent1_q<=0;
        sign2_q<=0;nan2_q<=0;inf2_q<=0;zero2_q<=0;invalid2_q<=0;normal2_q<=0;exponent2_q<=0;rounded2_q<=0;
      end else if(enable_i)begin
        valid_q[0]<=valid_i;valid_q[1]<=valid_q[0];valid_q[2]<=valid_q[1];
        sign0_q<=sign0_d;nan0_q<=nan0_d;inf0_q<=inf0_d;zero0_q<=zero0_d;invalid0_q<=invalid0_d;product0_q<=product0_d;base_exp0_q<=base_exp0_d;
        sign1_q<=sign0_q;nan1_q<=nan0_q;inf1_q<=inf0_q;zero1_q<=zero0_q;invalid1_q<=invalid0_q;product1_q<=product0_q;base_exp1_q<=base_exp0_q;msb1_q<=msb1_d;exponent1_q<=exponent1_d;
        sign2_q<=sign1_q;nan2_q<=nan1_q;inf2_q<=inf1_q;zero2_q<=zero1_q;invalid2_q<=invalid1_q;normal2_q<=normal2_d;exponent2_q<=exponent2_d;rounded2_q<=rounded2_d;
      end
    end
endmodule

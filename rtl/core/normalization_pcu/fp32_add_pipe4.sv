// Four-stage IEEE-754 binary32 adder. II=1, latency=3 cycles.
// S0 order/align, S1 add/sub, S2 normalize, S3 round/pack.
module fp32_add_pipe4(
    input logic clk_i,input logic rst_ni,input logic enable_i,input logic valid_i,output logic valid_o,
    input logic[31:0]lhs_i,rhs_i,output logic[31:0]result_o
);
    assign valid_o=valid_q[2];
    assign result_o=result3_d;
    function automatic[26:0]shift_right_sticky(input logic[26:0]value,input integer amount);
      logic sticky;begin
        if(amount<=0)shift_right_sticky=value;
        else if(amount>=27)shift_right_sticky={26'b0,|value};
        else begin sticky=|(value&((27'b1<<amount)-1'b1));shift_right_sticky=value>>amount;shift_right_sticky[0]|=sticky;end
      end
    endfunction
    function automatic[4:0]leading_zeros27(input logic[26:0]value);
      integer i;logic found;begin leading_zeros27=27;found=0;for(i=26;i>=0;i=i-1)if(!found&&value[i])begin leading_zeros27=26-i;found=1;end end
    endfunction
    logic[2:0]valid_q;
    logic[7:0]le_d,se_d,le_q;logic[23:0]ls_d,ss_d;
    logic[26:0]large_d,small_d,large_q,small_q;
    logic lsign_d,ssign_d,lsign_q,ssign_q,nan_d,inf_d,invalid_inf_d,zeros_d,nan0_q,inf0_q,invalid0_q,zeros0_q;
    integer shift_d;logic[7:0]lexp,rexp;logic[22:0]lfrac,rfrac;logic[23:0]lsig,rsig;
    always@*begin
      lexp=lhs_i[30:23];rexp=rhs_i[30:23];lfrac=lhs_i[22:0];rfrac=rhs_i[22:0];lsig={lexp!=0,lfrac};rsig={rexp!=0,rfrac};
      le_d=lexp==0?8'd1:lexp;se_d=rexp==0?8'd1:rexp;ls_d=lsig;ss_d=rsig;lsign_d=lhs_i[31];ssign_d=rhs_i[31];
      if({rexp==0?8'd1:rexp,rsig}>{lexp==0?8'd1:lexp,lsig})begin le_d=rexp==0?8'd1:rexp;se_d=lexp==0?8'd1:lexp;ls_d=rsig;ss_d=lsig;lsign_d=rhs_i[31];ssign_d=lhs_i[31];end
      large_d={ls_d,3'b0};shift_d=le_d-se_d;small_d=shift_right_sticky({ss_d,3'b0},shift_d);
      nan_d=(lexp==8'hff&&lfrac!=0)||(rexp==8'hff&&rfrac!=0);
      inf_d=(lexp==8'hff&&lfrac==0)||(rexp==8'hff&&rfrac==0);
      invalid_inf_d=(lexp==8'hff&&lfrac==0&&rexp==8'hff&&rfrac==0&&lhs_i[31]!=rhs_i[31]);
      zeros_d=(lexp==0&&lfrac==0&&rexp==0&&rfrac==0);
      if(zeros_d)lsign_d=lhs_i[31]&rhs_i[31];
    end
    logic[27:0]add1_d;logic[26:0]mag1_d,mag1_q;logic[8:0]exp1_d,exp1_q;
    logic sign1_d,sign1_q,nan1_q,inf1_q,invalid1_q,zeros1_q;
    always@*begin
      add1_d=0;mag1_d=0;exp1_d={1'b0,le_q};sign1_d=lsign_q;
      if(lsign_q==ssign_q)begin add1_d={1'b0,large_q}+{1'b0,small_q};if(add1_d[27])begin mag1_d=add1_d[27:1];mag1_d[0]|=add1_d[0];exp1_d={1'b0,le_q}+1'b1;end else mag1_d=add1_d[26:0];end
      else mag1_d=large_q-small_q;
    end
    logic[4:0]lz2_d;integer norm_shift_d;logic[26:0]mag2_d,mag2_q;logic[8:0]exp2_d,exp2_q;
    logic sign2_q,nan2_q,inf2_q,invalid2_q,zeros2_q;
    always@*begin
      lz2_d=leading_zeros27(mag1_q);norm_shift_d=lz2_d;if(norm_shift_d>exp1_q-1)norm_shift_d=exp1_q-1;if(norm_shift_d<0)norm_shift_d=0;
      mag2_d=mag1_q<<norm_shift_d;exp2_d=exp1_q-norm_shift_d;
    end
    logic round3_d;logic[24:0]rounded3_d;logic[8:0]packed_exp_d;logic[31:0]result3_d;
    always@*begin
      round3_d=mag2_q[2]&&(mag2_q[1]||mag2_q[0]||mag2_q[3]);rounded3_d={1'b0,mag2_q[26:3]}+round3_d;packed_exp_d=exp2_q;
      if(rounded3_d[24])begin rounded3_d>>=1;packed_exp_d=exp2_q+1'b1;end
      result3_d={sign2_q,packed_exp_d[7:0],rounded3_d[22:0]};
      if(nan2_q||invalid2_q)result3_d=32'h7fc00000;
      else if(inf2_q)result3_d={sign2_q,8'hff,23'b0};
      else if(zeros2_q)result3_d={sign2_q,31'b0};
      else if(mag2_q==0)result3_d=0;
      else if(packed_exp_d>=255)result3_d={sign2_q,8'hff,23'b0};
      else if(packed_exp_d<=1&&!rounded3_d[23])result3_d={sign2_q,8'b0,rounded3_d[22:0]};
    end
    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin valid_q<=0;large_q<=0;small_q<=0;le_q<=0;lsign_q<=0;ssign_q<=0;nan0_q<=0;inf0_q<=0;invalid0_q<=0;zeros0_q<=0;mag1_q<=0;exp1_q<=0;sign1_q<=0;nan1_q<=0;inf1_q<=0;invalid1_q<=0;zeros1_q<=0;mag2_q<=0;exp2_q<=0;sign2_q<=0;nan2_q<=0;inf2_q<=0;invalid2_q<=0;zeros2_q<=0;end
      else if(enable_i)begin
        valid_q[0]<=valid_i;valid_q[1]<=valid_q[0];valid_q[2]<=valid_q[1];
        // Data stages advance with the global enable.  Valid qualifies the
        // result but is deliberately not used as a wide clock-enable; this
        // avoids a high-fanout timing path after replication in reduction trees.
        large_q<=large_d;small_q<=small_d;le_q<=le_d;lsign_q<=lsign_d;ssign_q<=ssign_d;nan0_q<=nan_d;inf0_q<=inf_d;invalid0_q<=invalid_inf_d;zeros0_q<=zeros_d;
        mag1_q<=mag1_d;exp1_q<=exp1_d;sign1_q<=sign1_d;nan1_q<=nan0_q;inf1_q<=inf0_q;invalid1_q<=invalid0_q;zeros1_q<=zeros0_q;
        mag2_q<=mag2_d;exp2_q<=exp2_d;sign2_q<=sign1_q;nan2_q<=nan1_q;inf2_q<=inf1_q;invalid2_q<=invalid1_q;zeros2_q<=zeros1_q;
      end
    end
endmodule

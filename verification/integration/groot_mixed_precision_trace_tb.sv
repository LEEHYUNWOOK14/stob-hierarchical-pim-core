module groot_mixed_precision_trace_tb;
  localparam int B=16,L=4,MAX_HIDDEN=2048,MAX_ROWS=280,MAX_ELEMENTS=MAX_HIDDEN*MAX_ROWS;
  logic clk=0,rst_n=0;always #5 clk=~clk;
  logic begin_valid,begin_ready;logic[15:0]tag;logic[15:0]vectors_per_bank;
  logic[31:0]inv_hidden,epsilon;
  logic[B-1:0]reduce_valid,reduce_ready,apply_valid,apply_ready,apply_last;
  logic[B*L-1:0][15:0]reduce_data,apply_x,apply_gamma,apply_beta;
  logic[B-1:0][15:0]apply_tag;
  logic[B-1:0]result_valid,result_ready,result_last;logic[B-1:0][15:0]result_tag;
  logic[B*L-1:0][15:0]result_data;
  logic configured,protocol_error;logic[31:0]scalar_mean,scalar_inv;
  logic[15:0]x_mem[0:MAX_ELEMENTS-1],gamma_mem[0:MAX_HIDDEN-1],beta_mem[0:MAX_HIDDEN-1];
  logic[15:0]mixed_mem[0:MAX_ELEMENTS-1],pytorch_mem[0:MAX_ELEMENTS-1],actual_mem[0:MAX_ELEMENTS-1];
  logic[31:0]mean_mem[0:MAX_ROWS-1],inv_mem[0:MAX_ROWS-1];
  integer hidden,rows,vectors,outputs,mixed_mismatches,pytorch_mismatches,cycles,outfile;
  string profile,x_file,gamma_file,beta_file,mixed_file,pytorch_file,mean_file,inv_file,actual_file;
`ifdef GROOT_C11
  mixed_precision_normalization_datapath_c11 dut(
`else
  mixed_precision_normalization_datapath dut(
`endif
    .clk_i(clk),.rst_ni(rst_n),.begin_valid_i(begin_valid),.begin_ready_o(begin_ready),.rms_norm_i(1'b0),.tag_i(tag),
    .vectors_per_bank_i(vectors_per_bank),.inv_hidden_i(inv_hidden),.epsilon_i(epsilon),
    .reduce_valid_i(reduce_valid),.reduce_ready_o(reduce_ready),.reduce_data_i(reduce_data),
    .apply_valid_i(apply_valid),.apply_ready_o(apply_ready),.apply_tag_i(apply_tag),.apply_x_i(apply_x),
    .apply_gamma_i(apply_gamma),.apply_beta_i(apply_beta),.apply_last_i(apply_last),
    .result_valid_o(result_valid),.result_ready_i(result_ready),.result_tag_o(result_tag),.result_data_o(result_data),
    .result_last_o(result_last),.scalar_configured_o(configured),.scalar_mean_o(scalar_mean),.scalar_inv_std_o(scalar_inv),
    .protocol_error_o(protocol_error));
  always@(posedge clk)if(rst_n)begin
    integer mixed_delta,pytorch_delta;mixed_delta=0;pytorch_delta=0;cycles<=cycles+1;
    for(integer b=0;b<B;b++)if(result_valid[b]&&result_ready[b])begin
      integer vector_index,column;vector_index=outputs/(B*L);
      for(integer lane=0;lane<L;lane++)begin
        column=vector_index*B*L+b*L+lane;actual_mem[column]<=result_data[b*L+lane];
        if(result_data[b*L+lane]!==mixed_mem[column])mixed_delta++;
        if(result_data[b*L+lane]!==pytorch_mem[column])pytorch_delta++;
      end
    end
    mixed_mismatches<=mixed_mismatches+mixed_delta;pytorch_mismatches<=pytorch_mismatches+pytorch_delta;
    if(|(result_valid&result_ready))outputs<=outputs+B*L;
  end
  task automatic send_reduce_row(input integer row);begin
    @(negedge clk);reduce_valid='1;
    for(integer vector_index=0;vector_index<vectors;vector_index++)begin
      for(integer b=0;b<B;b++)for(integer lane=0;lane<L;lane++)reduce_data[b*L+lane]=x_mem[row*hidden+vector_index*B*L+b*L+lane];
      #1;while(reduce_ready!={B{1'b1}})@(negedge clk);@(negedge clk);
    end
    reduce_valid='0;
  end endtask
  task automatic send_apply_row(input integer row);begin
    @(negedge clk);apply_valid='1;
    for(integer vector_index=0;vector_index<vectors;vector_index++)begin
      for(integer b=0;b<B;b++)begin
        apply_tag[b]=tag;apply_last[b]=(vector_index==vectors-1);
        for(integer lane=0;lane<L;lane++)begin
          integer column;column=vector_index*B*L+b*L+lane;
          apply_x[b*L+lane]=x_mem[row*hidden+column];apply_gamma[b*L+lane]=gamma_mem[column];apply_beta[b*L+lane]=beta_mem[column];
        end
      end
      #1;while(apply_ready!={B{1'b1}})@(negedge clk);@(negedge clk);
    end
    apply_valid='0;
  end endtask
  initial begin
    if(!$value$plusargs("PROFILE=%s",profile)||!$value$plusargs("ROWS=%d",rows)||!$value$plusargs("HIDDEN=%d",hidden)||!$value$plusargs("VECTORS=%d",vectors)||
       !$value$plusargs("INVH=%h",inv_hidden)||!$value$plusargs("EPS=%h",epsilon)||!$value$plusargs("MEANS=%s",mean_file)||
       !$value$plusargs("INVS=%s",inv_file)||!$value$plusargs("X=%s",x_file)||!$value$plusargs("GAMMA=%s",gamma_file)||
       !$value$plusargs("BETA=%s",beta_file)||!$value$plusargs("MIXED=%s",mixed_file)||!$value$plusargs("PYTORCH=%s",pytorch_file)||
       !$value$plusargs("ACTUAL=%s",actual_file))$fatal(1,"missing plusargs");
    $readmemh(gamma_file,gamma_mem,0,hidden-1);$readmemh(beta_file,beta_mem,0,hidden-1);
    $readmemh(x_file,x_mem,0,rows*hidden-1);$readmemh(mixed_file,mixed_mem,0,rows*hidden-1);$readmemh(pytorch_file,pytorch_mem,0,rows*hidden-1);
    $readmemh(mean_file,mean_mem,0,rows-1);$readmemh(inv_file,inv_mem,0,rows-1);
    tag=16'h6a00;vectors_per_bank=vectors;begin_valid=0;reduce_valid=0;reduce_data=0;apply_valid=0;apply_tag=0;apply_x=0;apply_gamma=0;apply_beta=0;apply_last=0;
    result_ready='1;outputs=0;mixed_mismatches=0;pytorch_mismatches=0;cycles=0;
    repeat(3)@(negedge clk);rst_n=1;
    for(integer row=0;row<rows;row++)begin
      tag=16'h6000+row;@(negedge clk);begin_valid=1;#1;while(!begin_ready)@(negedge clk);@(negedge clk);begin_valid=0;
      send_reduce_row(row);
      while(!configured)@(negedge clk);
      if(scalar_mean!==mean_mem[row]||scalar_inv!==inv_mem[row])$fatal(1,"scalar mismatch row=%0d mean=%h/%h inv=%h/%h",row,scalar_mean,mean_mem[row],scalar_inv,inv_mem[row]);
      send_apply_row(row);
      while(outputs<(row+1)*hidden)@(negedge clk);
    end
    @(negedge clk);outfile=$fopen(actual_file,"w");if(!outfile)$fatal(1,"cannot open actual");for(integer i=0;i<rows*hidden;i++)$fdisplay(outfile,"%04h",actual_mem[i]);$fclose(outfile);
    if(protocol_error||mixed_mismatches)$fatal(1,"mixed trace failure protocol=%0d mixed_mismatches=%0d",protocol_error,mixed_mismatches);
    $display("GROOT_MIXED_PRECISION_TRACE_TB PASS profile=%s rows=%0d hidden=%0d elements=%0d mixed_mismatches=%0d pytorch_bit_mismatches=%0d cycles=%0d",profile,rows,hidden,rows*hidden,mixed_mismatches,pytorch_mismatches,cycles);$finish;
  end
  initial begin#10000000;$fatal(1,"timeout");end
endmodule

module groot_actual_trace_bf16_tb;
  localparam int B=16,MAX_HIDDEN=2048;
  logic clk=0,rst_n=0;always #5 clk=~clk;
  logic begin_valid,begin_ready;logic[15:0]tag,inv_hidden,epsilon;
  logic[B-1:0][15:0]counts;
  logic[B-1:0]reduce_valid,reduce_ready,apply_valid,apply_ready,apply_last;
  logic[B-1:0][15:0]reduce_data,apply_tag,apply_x,apply_gamma,apply_beta;
  logic[B-1:0]result_valid,result_ready,result_last;logic[B-1:0][15:0]result_tag,result_data;
  logic configured,protocol_error;logic[15:0]scalar_mean,scalar_inv;
  logic[15:0]x_mem[0:MAX_HIDDEN-1],gamma_mem[0:MAX_HIDDEN-1];
  logic[15:0]beta_mem[0:MAX_HIDDEN-1],expected_mem[0:MAX_HIDDEN-1],actual_mem[0:MAX_HIDDEN-1];
  integer hidden,per_bank,accepted,outputs,exact_mismatches,cycles,outfile;
  string profile,x_file,gamma_file,beta_file,expected_file,actual_file;

  hierarchical_normalization_datapath #(.BANKS(B),.DATA_FORMAT(1))dut(
    .clk_i(clk),.rst_ni(rst_n),.begin_valid_i(begin_valid),.begin_ready_o(begin_ready),
    .rms_norm_i(1'b0),.tag_i(tag),.expected_bank_mask_i({B{1'b1}}),
    .bank_element_count_i(counts),.inv_hidden_i(inv_hidden),.epsilon_i(epsilon),
    .reduce_element_valid_i(reduce_valid),.reduce_element_ready_o(reduce_ready),
    .reduce_element_data_i(reduce_data),.apply_element_valid_i(apply_valid),
    .apply_element_ready_o(apply_ready),.apply_element_tag_i(apply_tag),.apply_x_i(apply_x),
    .apply_gamma_i(apply_gamma),.apply_beta_i(apply_beta),.apply_last_i(apply_last),
    .result_valid_o(result_valid),.result_ready_i(result_ready),.result_tag_o(result_tag),
    .result_data_o(result_data),.result_last_o(result_last),.scalar_configured_o(configured),
    .scalar_mean_o(scalar_mean),.scalar_inv_std_o(scalar_inv),.protocol_error_o(protocol_error));

  always@(posedge clk)if(rst_n)begin
    integer cycle_mismatches;cycle_mismatches=0;
    cycles<=cycles+1;
    for(integer b=0;b<B;b++)if(result_valid[b]&&result_ready[b])begin
      integer local_index,column;local_index=outputs/B;
      column=(local_index/4)*B*4+b*4+(local_index%4);
      actual_mem[column]<=result_data[b];
      if(result_data[b]!==expected_mem[column])cycle_mismatches=cycle_mismatches+1;
    end
    if(cycle_mismatches)exact_mismatches<=exact_mismatches+cycle_mismatches;
    if(|(result_valid&result_ready))outputs<=outputs+B;
  end

  task automatic send_reduce_group(input integer local_index);begin
    @(negedge clk);reduce_valid='1;
    for(integer b=0;b<B;b++)begin
      integer column;column=(local_index/4)*B*4+b*4+(local_index%4);reduce_data[b]=x_mem[column];
    end
    #1;while(reduce_ready!={B{1'b1}})@(negedge clk);@(negedge clk);reduce_valid='0;
  end endtask

  task automatic send_apply_group(input integer local_index);begin
    @(negedge clk);apply_valid='1;
    for(integer b=0;b<B;b++)begin
      integer column;column=(local_index/4)*B*4+b*4+(local_index%4);
      apply_tag[b]=tag;apply_x[b]=x_mem[column];apply_gamma[b]=gamma_mem[column];
      apply_beta[b]=beta_mem[column];apply_last[b]=(local_index==per_bank-1);
    end
    #1;while(apply_ready!={B{1'b1}})@(negedge clk);@(negedge clk);apply_valid='0;
  end endtask

  initial begin
    if(!$value$plusargs("PROFILE=%s",profile)||!$value$plusargs("HIDDEN=%d",hidden)||
       !$value$plusargs("INVH=%h",inv_hidden)||!$value$plusargs("EPS=%h",epsilon)||
       !$value$plusargs("X=%s",x_file)||!$value$plusargs("GAMMA=%s",gamma_file)||
       !$value$plusargs("BETA=%s",beta_file)||!$value$plusargs("EXPECTED=%s",expected_file)||
       !$value$plusargs("ACTUAL=%s",actual_file))$fatal(1,"missing plusargs");
    if(hidden>B*4*(MAX_HIDDEN/(B*4))||hidden%B)$fatal(1,"unsupported hidden=%0d",hidden);
    $readmemh(x_file,x_mem,0,hidden-1);$readmemh(gamma_file,gamma_mem,0,hidden-1);
    $readmemh(beta_file,beta_mem,0,hidden-1);$readmemh(expected_file,expected_mem,0,hidden-1);
    tag=16'h5a00;per_bank=hidden/B;counts={B{per_bank[15:0]}};begin_valid=0;
    reduce_valid=0;reduce_data=0;apply_valid=0;apply_tag=0;apply_x=0;apply_gamma=0;
    apply_beta=0;apply_last=0;result_ready='1;outputs=0;exact_mismatches=0;cycles=0;
    repeat(3)@(negedge clk);rst_n=1;@(negedge clk);begin_valid=1;#1;
    while(!begin_ready)@(negedge clk);@(negedge clk);begin_valid=0;
    for(integer i=0;i<per_bank;i++)send_reduce_group(i);
    while(!configured)@(negedge clk);
    for(integer i=0;i<per_bank;i++)send_apply_group(i);
    while(outputs<hidden)@(negedge clk);@(negedge clk);
    outfile=$fopen(actual_file,"w");if(!outfile)$fatal(1,"cannot open actual output");
    for(integer i=0;i<hidden;i++)$fdisplay(outfile,"%04h",actual_mem[i]);$fclose(outfile);
    if(protocol_error)$fatal(1,"protocol error");
    $display("GROOT_ACTUAL_TRACE_BF16_TB PASS profile=%s hidden=%0d outputs=%0d exact_mismatches=%0d mean=%h inv=%h cycles=%0d",
      profile,hidden,outputs,exact_mismatches,scalar_mean,scalar_inv,cycles);$finish;
  end
  initial begin#10000000;$fatal(1,"actual trace BF16 timeout");end
endmodule

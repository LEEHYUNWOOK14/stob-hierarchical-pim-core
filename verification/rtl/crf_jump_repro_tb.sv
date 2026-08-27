module crf_jump_repro_tb;
  logic clk=0,rst_n=0,prog_v,prog_r,start,cmd_v,cmd_r=1,active,done;
  logic [2:0] addr,pc; logic [31:0] pdata,cmd; integer accepted;
  always #5 clk=~clk;
  pim_crf #(.DEPTH(8)) dut(.clk_i(clk),.rst_ni(rst_n),.program_valid_i(prog_v),
    .program_ready_o(prog_r),.program_addr_i(addr),.program_data_i(pdata),.start_i(start),
    .command_ready_i(cmd_r),.command_valid_o(cmd_v),.command_o(cmd),.active_o(active),
    .done_o(done),.pc_o(pc));
  task put(input [2:0] a,input [31:0] d);
    begin @(negedge clk);addr=a;pdata=d;prog_v=1;@(posedge clk);@(negedge clk);prog_v=0;end
  endtask
  always @(posedge clk) if(rst_n && cmd_v && cmd_r) accepted<=accepted+1;
  initial begin
    prog_v=0;start=0;addr=0;pdata=0;accepted=0;
    repeat(3)@(posedge clk);rst_n=1;
    put(0,32'h00000000);                       // NOP
    put(1,{4'he,17'd1,11'd1});                 // JUMP once to PC 0
    put(2,32'hf0000000);                       // EXIT
    @(negedge clk);start=1;@(posedge clk);@(negedge clk);start=0;
    repeat(12) begin
      @(posedge clk);
      if(done) begin
        if(accepted!=5)$fatal(1,"finite JUMP retired unexpected command count %0d",accepted);
        $display("AUDIT_FIX PASS: finite JUMP completed; accepted=%0d",accepted);
        $finish;
      end
    end
    $fatal(1,"finite JUMP did not complete active=%b accepted=%0d pc=%0d",active,accepted,pc);
  end
endmodule

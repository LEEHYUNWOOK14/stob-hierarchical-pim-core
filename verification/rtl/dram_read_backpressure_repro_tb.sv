module dram_read_backpressure_repro_tb;
  logic clk=0,rst_n=0,cv,cr,rv,rr=0,terr; logic [2:0] cmd;
  logic bank; logic [1:0] row,col; logic [31:0] wd,rd; logic [3:0] wm='1;
  always #5 clk=~clk;
  dram_bank_array_model #(.BANKS(2),.ROWS(4),.COLS(4),.DATA_WIDTH(32),
    .TRCD_RD(0),.TRCD_WR(0),.TRAS(0),.TRP(0),.TWR(0),.TCCD(0),
    .TRRD(0),.TFAW(0),.TRFC(0),.TWTR(0),.TRTW(0),
    .READ_LATENCY(1),.PIM_READ_PORTS(1)) dut(
    // This test isolates response backpressure; extended timing is tested separately.
    .clk_i(clk),.rst_ni(rst_n),.cmd_valid_i(cv),.cmd_ready_o(cr),.cmd_i(cmd),
    .bank_i(bank),.row_i(row),.col_i(col),.write_data_i(wd),.write_mask_i(wm),
    .read_valid_o(rv),.read_ready_i(rr),.read_data_o(rd),.timing_error_o(terr),
    .pim_read_enable_i('0),.pim_read_bank_i('0),.pim_read_row_i('0),
    .pim_read_col_i('0),.pim_read_valid_o(),.pim_read_data_o());
  task issue(input [2:0] c,input [1:0] cc,input [31:0] d);
    begin @(negedge clk);cmd=c;col=cc;wd=d;cv=1;#1;if(!cr)$fatal(1,"command not ready");
      @(posedge clk);@(negedge clk);cv=0;end
  endtask
  initial begin
    cv=0;cmd=0;bank=0;row=0;col=0;wd=0;
    repeat(3)@(posedge clk);rst_n=1;
    issue(3'd1,0,0);issue(3'd3,0,32'haaaa1111);issue(3'd3,1,32'hbbbb2222);
    issue(3'd2,0,0);wait(rv);#1;if(rd!==32'haaaa1111)$fatal(1,"first read wrong");
    @(negedge clk);cmd=3'd2;col=1;cv=1;#1;
    if(cr)$fatal(1,"second read accepted while prior response was stalled");
    repeat(2)begin @(posedge clk);#1;if(!rv||rd!==32'haaaa1111)$fatal(1,"stalled response changed");end
    rr=1;do @(posedge clk);while(!cr);@(negedge clk);cv=0;
    wait(rv);#1;if(rd!==32'hbbbb2222)$fatal(1,"second read wrong after release");
    $display("AUDIT_FIX PASS: stalled DRAM response stayed stable and blocked overwrite");$finish;
  end
endmodule

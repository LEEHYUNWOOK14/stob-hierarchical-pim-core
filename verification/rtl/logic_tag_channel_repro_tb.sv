module logic_tag_channel_repro_tb;
  localparam CH=2,PCU=2,DW=32,TW=64;
  logic clk=0,rst_n=0,ov,ordy,cv,crdy;
  logic och,cch; logic [TW-1:0] tag; logic [1:0] prec;
  logic [DW-1:0] s0,s1,s2,acc; logic [15:0] epoch,ordinal;
  logic [31:0] sig,cword; logic [CH-1:0] expected;
  logic [PCU-1:0] rv,rr='1; logic [PCU-1:0][TW-1:0] rtag;
  logic [PCU-1:0][DW-1:0] rdata; logic [PCU-1:0] rch;
  logic dup,ctx,operr; logic [7:0] occ;
  logic ep_begin,ep_begin_ready,ep_fill,ep_release,ep_active; logic ep_fill_ch;
  logic [15:0] ep_release_id;
  always #5 clk=~clk;
  logic_die_pim_top #(.CHANNELS(CH),.PCUS(PCU),.DATA_WIDTH(DW),.TAG_WIDTH(TW),
    .WEIGHT_BUFFER_BYTES(64),.USE_SHARED_WEIGHT(1'b0)) dut(
    .clk_i(clk),.rst_ni(rst_n),.operand_valid_i(ov),.operand_ready_o(ordy),
    .operand_channel_i(och),.operand_tag_i(tag),.operand_precision_i(prec),
    .operand_src0_i(s0),.operand_src1_i(s1),.operand_src2_i(s2),.operand_accum_i(acc),
    .command_valid_i(cv),.command_ready_o(crdy),.command_channel_i(cch),
    .command_epoch_i(epoch),.command_ordinal_i(ordinal),.command_signature_i(sig),
    .command_word_i(cword),.command_expected_mask_i(expected),
    .epoch_begin_valid_i(ep_begin),.epoch_begin_ready_o(ep_begin_ready),.epoch_begin_id_i(16'd1),
    .epoch_expected_mask_i(2'b10),.epoch_fill_done_valid_i(ep_fill),
    .epoch_fill_done_channel_i(ep_fill_ch),.epoch_execution_done_i(1'b0),
    .epoch_release_valid_o(ep_release),.epoch_release_id_o(ep_release_id),.epoch_active_o(ep_active),
    .weight_write_valid_i(1'b0),.weight_write_addr_i('0),.weight_write_data_i('0),
    .weight_write_mask_i('0),.weight_read_valid_i(1'b0),.weight_read_addr_i('0),
    .weight_response_ready_i(1'b1),.weight_context_commit_i(1'b0),.weight_context_id_i('0),
    .result_valid_o(rv),.result_ready_i(rr),.result_tag_o(rtag),.result_data_o(rdata),
    .result_channel_o(rch),.reduced_result_ready_i(1'b1),
    .coalescer_duplicate_error_o(dup),
    .coalescer_context_error_o(ctx),.operand_context_error_o(operr),
    .coalescer_occupancy_o(occ));
  initial begin
    ov=0;cv=0;ep_begin=0;ep_fill=0;ep_fill_ch=1;
    och=1;cch=1;tag=64'h100;prec=1;s0=32'd1;s1=32'd2;s2=0;acc=0;
    epoch=1;ordinal=0;sig=32'h11;cword=32'h10000000;expected=2'b10;
    repeat(3)@(posedge clk);rst_n=1;
    @(negedge clk);ov=1;do @(posedge clk);while(!ordy);@(negedge clk);ov=0;
    @(negedge clk);cv=1;do @(posedge clk);while(!crdy);@(negedge clk);cv=0;
    repeat(5) begin @(posedge clk);if(|rv)$fatal(1,"command bypassed unreleased epoch");end
    @(negedge clk);ep_begin=1;@(posedge clk);@(negedge clk);ep_begin=0;
    @(negedge clk);ep_fill=1;@(posedge clk);@(negedge clk);ep_fill=0;
    wait(ep_release);
    wait(rv[0]);#1;
    if(rtag[0]==64'h100 && rch[0]==1) begin
      $display("AUDIT_FIX PASS: epoch gated dispatch and independent source channel metadata");
      $finish;
    end
    $fatal(1,"defect not reproduced tag=%h channel=%b",rtag[0],rch[0]);
  end
endmodule

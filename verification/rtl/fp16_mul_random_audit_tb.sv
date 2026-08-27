module fp16_mul_random_audit_tb;
  logic [15:0] a,b,y; integer fd,n,rc,mismatches; reg [15:0] expected;
  fp16_mul dut(.lhs_i(a),.rhs_i(b),.result_o(y));
  initial begin
    fd=$fopen("/tmp/audit_fp16_mul_vectors.txt","r");if(!fd)$fatal(1,"vector open failed");
    n=0;mismatches=0;
    while(!$feof(fd)) begin
      rc=$fscanf(fd,"%h %h %h\n",a,b,expected);
      if(rc==3)begin #1;n=n+1;
        // The C++ half library and RTL both canonicalize NaN differently; compare NaN class.
        if((&expected[14:10] && |expected[9:0]) && (&y[14:10] && |y[9:0])) begin end
        else if(y!==expected)begin
          if(mismatches<10)$display("MISMATCH a=%h b=%h rtl=%h ref=%h",a,b,y,expected);
          mismatches=mismatches+1;
        end
      end
    end
    $display("FP16_MUL_AUDIT vectors=%0d mismatches=%0d",n,mismatches);
    if(mismatches)$fatal(1,"FP16 multiplier differs from C++ half reference");
    $finish;
  end
endmodule

module bf16_to_fp32 (
    input  logic [15:0] bf16_i,
    output logic [31:0] fp32_o
);
    // BF16 is the upper 16 bits of IEEE-754 binary32.
    assign fp32_o = {bf16_i, 16'h0000};
endmodule


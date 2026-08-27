module fp32_to_bf16_rne (
    input  logic [31:0] fp32_i,
    output logic [15:0] bf16_o
);
    logic [15:0] upper;
    logic [15:0] lower;
    logic round_up;
    logic [16:0] rounded;
    always @* begin
        upper = fp32_i[31:16];
        lower = fp32_i[15:0];
        round_up = (lower > 16'h8000) ||
                   (lower == 16'h8000 && upper[0]);
        rounded = {1'b0, upper} + round_up;
        if (fp32_i[30:23] == 8'hff) begin
            if (|fp32_i[22:0]) bf16_o = 16'h7fc0;
            else bf16_o = {fp32_i[31], 8'hff, 7'h00};
        end else if (rounded[16]) begin
            bf16_o = {fp32_i[31], 8'hff, 7'h00};
        end else begin
            bf16_o = rounded[15:0];
        end
    end
endmodule

